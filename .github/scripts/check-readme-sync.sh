#!/bin/bash
# Emit a GitHub Actions warning annotation when a chart's values.yaml changed
# without its README.md. Always exits 0 — this is a soft reminder, not a gate.
#
# A "chart" here is a top-level chart directory (charts/<top>). Subchart
# values.yaml changes count toward the top-level chart since READMEs only
# live at the top level. Each changed values.yaml gets its own annotation,
# anchored to the first changed line so the ⚠ shows inline in the diff.
#
# Usage:
#   check-readme-sync.sh [base-ref]   # defaults to origin/main

set -euo pipefail

base_ref="${1:-origin/main}"

# Expose results so the workflow can post a single sticky reminder comment.
# The job step itself still succeeds, so this stays non-blocking.
emit_outputs() {
    local count="$1" charts_csv="$2"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        {
            echo "warnings=$count"
            echo "charts=$charts_csv"
        } >> "$GITHUB_OUTPUT"
    fi
}

# First changed line on the new side of a file's diff, for anchoring the
# annotation. Parses the first hunk header `@@ -a,b +c,d @@` and returns c.
# Falls back to 1 if no hunk is found.
first_changed_line() {
    local file="$1" line
    line=$(git diff --unified=0 "$base_ref"...HEAD -- "$file" 2>/dev/null \
        | grep -m1 '^@@' \
        | sed -E 's/^@@ -[0-9]+(,[0-9]+)? \+([0-9]+).*/\2/')
    if [[ "$line" =~ ^[0-9]+$ ]] && [[ "$line" -gt 0 ]]; then
        echo "$line"
    else
        echo 1
    fi
}

echo "Checking README sync against base: $base_ref"
echo "=============================================="

changed_files=$(git diff --name-only "$base_ref"...HEAD 2>/dev/null || git diff --name-only "$base_ref" HEAD)

if [[ -z "$changed_files" ]]; then
    echo "No changed files detected."
    emit_outputs 0 ""
    exit 0
fi

# Map each top-level chart to its changed values.yaml files (newline-joined),
# and track which top-level charts had their README touched.
declare -A values_files
declare -A readme_touched

while IFS= read -r file; do
    if [[ "$file" =~ ^charts/([^/]+)/.*values\.yaml$ ]]; then
        top="${BASH_REMATCH[1]}"
        values_files["$top"]+="$file"$'\n'
    fi
    if [[ "$file" =~ ^charts/([^/]+)/README\.md$ ]]; then
        readme_touched["${BASH_REMATCH[1]}"]=1
    fi
done <<< "$changed_files"

warnings=0
flagged_charts=()
for top in "${!values_files[@]}"; do
    if [[ -v readme_touched["$top"] ]]; then
        continue
    fi
    readme_path="charts/$top/README.md"
    if [[ ! -f "$readme_path" ]]; then
        # Chart intentionally has no README; nothing to keep in sync.
        continue
    fi
    flagged_charts+=("$top")
    # Anchor a warning on each changed values.yaml in this chart.
    while IFS= read -r vfile; do
        [[ -z "$vfile" ]] && continue
        line=$(first_changed_line "$vfile")
        echo "::warning file=$vfile,line=$line::$vfile changed but charts/$top/README.md was not updated. Confirm the README tables still reflect the values."
        echo "  WARN: $vfile changed without charts/$top/README.md update (line $line)"
        warnings=$((warnings + 1))
    done <<< "${values_files["$top"]}"
done

echo "=============================================="
if [[ "$warnings" -eq 0 ]]; then
    echo "SUCCESS: No README sync reminders to emit."
else
    echo "Emitted $warnings README sync reminder(s). Job exits 0 (non-blocking)."
fi

charts_csv=""
if [[ "${#flagged_charts[@]}" -gt 0 ]]; then
    # Sorted, comma-separated list of top-level charts needing a README review.
    charts_csv=$(printf '%s\n' "${flagged_charts[@]}" | sort | paste -sd,)
fi
emit_outputs "$warnings" "$charts_csv"
exit 0
