#!/bin/bash
# This script renders charts that changed relative to the base branch and sends
# the output to a live API server with `kubectl apply --dry-run=server`. Pass
# --all instead of a base ref to check every chart in the repository.
#
# `helm template` only checks that a chart renders to YAML. The API server also
# runs its own validation, which catches objects that render but can't be
# applied: required fields left empty, two volumeMounts with the same
# mountPath, invalid host names, custom resources that don't match their CRD.
#
# kubectl must point at a disposable cluster (CI uses kind). The script creates
# one namespace per chart and values file, and applies every chart's CRDs for
# real first, so custom resources validate even when the chart that ships
# their CRD didn't change.
#
# Charts are rendered the same way as in lint-charts.sh: once per
# ci/*-values.yaml file, or with default values if there are none. Remote
# dependencies are fetched with `helm dependency build --skip-refresh`, so the
# repositories must already be added (see add-helm-repos.sh).
#
# Known limits: objects in a namespace the chart itself creates fail, because a
# dry-run doesn't create the Namespace; helm test hooks are skipped, since
# their ServiceAccounts never exist in a dry-run.

set -uo pipefail

base_ref="${1:-origin/main}"
release="lint-test"

all_charts=$(find charts -mindepth 2 -maxdepth 2 -name Chart.yaml -exec dirname {} \; | sort)

if [[ "$base_ref" == "--all" ]]; then
    echo "Dry-running all charts"
    charts="$all_charts"
else
    echo "Dry-running charts changed against base: $base_ref"
    changed_files=$(git diff --name-only "$base_ref"...HEAD 2>/dev/null || git diff --name-only "$base_ref" HEAD)
    # Reduce each changed path to its top-level chart directory, keeping only
    # charts that still exist.
    charts=$(echo "$changed_files" | grep -E '^charts/[^/]+/' | cut -d/ -f1-2 | sort -u |
        while read -r dir; do [[ -f "$dir/Chart.yaml" ]] && echo "$dir"; done)
fi
echo "=============================================="

if [[ -z "$charts" ]]; then
    echo "No charts to dry-run."
    exit 0
fi

kubectl version || { echo "ERROR: kubectl can't reach a cluster"; exit 1; }

# Prints the values files to render a chart with, one per line; an empty line
# means "default values only".
values_files() {
    local found=false f
    for f in "$1"/ci/*-values.yaml; do
        [[ -f "$f" ]] && { echo "$f"; found=true; }
    done
    [[ "$found" == "true" ]] || echo ""
}

# render <chart> <values file or empty> <namespace>
render() {
    local values_args=()
    [[ -n "$2" ]] && values_args=(--values "$2")
    helm template "$release" "$1" --namespace "$3" --include-crds --skip-tests "${values_args[@]}"
}

# Splits rendered YAML on document separators and keeps either the CRDs
# (`crds`) or everything else (`objects`). The kind may be quoted, as in the
# Keycloak operator's generated CRDs.
select_docs() {
    awk -v want="$1" '
        function flush() {
            if (has_kind && ((want == "crds") == is_crd)) printf "%s---\n", doc
            doc = ""; has_kind = 0; is_crd = 0
        }
        /^---[[:space:]]*$/ { flush(); next }
        { doc = doc $0 "\n" }
        /^kind:/ { has_kind = 1 }
        /^kind:[[:space:]]*["\047]?CustomResourceDefinition["\047]?[[:space:]]*$/ { is_crd = 1 }
        END { flush() }'
}

# A namespace name for a chart and values file: dr-<chart>-<values name>.
namespace_for() {
    local suffix="default"
    [[ -n "$2" ]] && suffix=$(basename "$2" -values.yaml)
    echo "dr-$(basename "$1")-$suffix" | tr 'A-Z_.' 'a-z--' | cut -c1-63 | sed 's/-*$//'
}

# Fetch remote dependencies for a chart. Local sub-charts (file:// or no
# repository) are already present in the chart's charts/ directory.
build_deps() {
    if grep -qE '^\s*repository:\s*"?(https?|oci)://' "$1/Chart.yaml"; then
        helm dependency build --skip-refresh "$1"
    fi
}

# Custom resources only validate once their CRD exists, and a dry-run never
# creates one, so apply the CRDs of every chart for real first. A chart that
# fails here is reported by its own check below if it changed.
echo "::group::Apply CRDs from all charts"
crd_file=$(mktemp)
trap 'rm -f "$crd_file"' EXIT
for chart_dir in $all_charts; do
    build_deps "$chart_dir" > /dev/null 2>&1 || { echo "skip $chart_dir: dependency build failed"; continue; }
    while IFS= read -r values; do
        render "$chart_dir" "$values" default 2>/dev/null | select_docs crds >> "$crd_file"
    done < <(values_files "$chart_dir")
done
if grep -q '^kind:' "$crd_file"; then
    kubectl apply --server-side --force-conflicts -f "$crd_file" &&
        kubectl wait --for=condition=Established crd --all --timeout=120s
fi
echo "::endgroup::"

failed_charts=()

for chart_dir in $charts; do
    echo "::group::$chart_dir"
    chart_failed=false

    if ! build_deps "$chart_dir"; then
        echo "::error file=$chart_dir/Chart.yaml::helm dependency build failed for $chart_dir"
        chart_failed=true
    fi

    if [[ "$chart_failed" == "false" ]]; then
        while IFS= read -r values; do
            label="${values:-default values}"
            ns=$(namespace_for "$chart_dir" "$values")
            echo "--- server-side dry-run ($label, namespace $ns)"

            if ! rendered=$(render "$chart_dir" "$values" "$ns"); then
                echo "::error file=$chart_dir/Chart.yaml::helm template failed for $chart_dir ($label)"
                chart_failed=true
                continue
            fi

            kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - > /dev/null
            # kubectl applies every object and reports all errors at the end.
            if ! select_docs objects <<< "$rendered" | kubectl apply --dry-run=server -n "$ns" -f - > /dev/null; then
                echo "::error file=$chart_dir/Chart.yaml::server-side dry-run failed for $chart_dir ($label)"
                chart_failed=true
            fi
        done < <(values_files "$chart_dir")
    fi

    echo "::endgroup::"
    [[ "$chart_failed" == "true" ]] && failed_charts+=("$chart_dir")
done

echo "=============================================="

if [[ ${#failed_charts[@]} -gt 0 ]]; then
    echo "ERROR: The following charts failed the server-side dry-run:"
    printf '  - %s\n' "${failed_charts[@]}"
    exit 1
fi

echo "SUCCESS: All charts passed the server-side dry-run."
exit 0
