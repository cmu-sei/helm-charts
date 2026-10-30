#!/bin/bash
# This script runs `helm lint` and `helm template` against charts that changed
# relative to the base branch. Pass --all instead of a base ref to check every
# chart in the repository.
#
# Changes inside a sub-chart (e.g., charts/alloy/charts/alloy-api) are checked
# through the top-level parent chart (charts/alloy), since sub-charts are
# rendered with the parent's values.
#
# Charts with remote dependencies have them fetched with `helm dependency build`,
# so the dependency repositories must already be added with `helm repo add`.
#
# If a chart has ci/*-values.yaml files, the chart is linted and rendered once
# per file instead of with its default values (the chart-testing convention).
# Use these to supply values the chart requires but doesn't default.

set -uo pipefail

base_ref="${1:-origin/main}"

if [[ "$base_ref" == "--all" ]]; then
    echo "Linting all charts"
    charts=$(find charts -mindepth 2 -maxdepth 2 -name Chart.yaml -exec dirname {} \; | sort)
else
    echo "Linting charts changed against base: $base_ref"
    changed_files=$(git diff --name-only "$base_ref"...HEAD 2>/dev/null || git diff --name-only "$base_ref" HEAD)
    # Reduce each changed path to its top-level chart directory, keeping only
    # charts that still exist (deleted charts can't be linted).
    charts=$(echo "$changed_files" | grep -E '^charts/[^/]+/' | cut -d/ -f1-2 | sort -u |
        while read -r dir; do [[ -f "$dir/Chart.yaml" ]] && echo "$dir"; done)
fi
echo "=============================================="

if [[ -z "$charts" ]]; then
    echo "No charts to lint."
    exit 0
fi

failed_charts=()

for chart_dir in $charts; do
    echo "::group::$chart_dir"
    chart_failed=false

    # Fetch remote dependencies. Local sub-charts (file:// or no repository)
    # are already present in the chart's charts/ directory.
    if grep -qE '^\s*repository:\s*"?(https?|oci)://' "$chart_dir/Chart.yaml"; then
        if ! helm dependency build "$chart_dir"; then
            echo "::error file=$chart_dir/Chart.yaml::helm dependency build failed for $chart_dir"
            chart_failed=true
        fi
    fi

    if [[ "$chart_failed" == "false" ]]; then
        values_files=()
        for f in "$chart_dir"/ci/*-values.yaml; do
            [[ -f "$f" ]] && values_files+=("$f")
        done
        # An empty entry means "default values only".
        [[ ${#values_files[@]} -eq 0 ]] && values_files=("")

        for values in "${values_files[@]}"; do
            values_args=()
            label="default values"
            if [[ -n "$values" ]]; then
                values_args=(--values "$values")
                label="$values"
            fi

            echo "--- helm lint ($label)"
            if ! helm lint "$chart_dir" "${values_args[@]}"; then
                echo "::error file=$chart_dir/Chart.yaml::helm lint failed for $chart_dir ($label)"
                chart_failed=true
            fi

            echo "--- helm template ($label)"
            if ! helm template lint-test "$chart_dir" "${values_args[@]}" > /dev/null; then
                echo "::error file=$chart_dir/Chart.yaml::helm template failed for $chart_dir ($label)"
                chart_failed=true
            fi
        done
    fi

    echo "::endgroup::"
    [[ "$chart_failed" == "true" ]] && failed_charts+=("$chart_dir")
done

echo "=============================================="

if [[ ${#failed_charts[@]} -gt 0 ]]; then
    echo "ERROR: The following charts failed helm lint or helm template:"
    printf '  - %s\n' "${failed_charts[@]}"
    exit 1
fi

echo "SUCCESS: All charts passed helm lint and helm template."
exit 0
