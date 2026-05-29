#!/bin/bash
# Emit a GitHub Actions warning annotation when a chart's values.yaml changed
# without its README.md. Always exits 0 — this is a soft reminder, not a gate.
#
# A "chart" here is a top-level chart directory (charts/<top>). Subchart
# values.yaml changes count toward the top-level chart since READMEs only
# live at the top level.
#
# Usage:
#   check-readme-sync.sh [base-ref]   # defaults to origin/main

set -euo pipefail

base_ref="${1:-origin/main}"

echo "Checking README sync against base: $base_ref"
echo "=============================================="

changed_files=$(git diff --name-only "$base_ref"...HEAD 2>/dev/null || git diff --name-only "$base_ref" HEAD)

if [[ -z "$changed_files" ]]; then
    echo "No changed files detected."
    exit 0
fi

declare -A values_touched
declare -A readme_touched

while IFS= read -r file; do
    if [[ "$file" =~ ^charts/([^/]+)/.*values\.yaml$ ]]; then
        values_touched["${BASH_REMATCH[1]}"]=1
    fi
    if [[ "$file" =~ ^charts/([^/]+)/README\.md$ ]]; then
        readme_touched["${BASH_REMATCH[1]}"]=1
    fi
done <<< "$changed_files"

warnings=0
for top in "${!values_touched[@]}"; do
    if [[ -v readme_touched["$top"] ]]; then
        continue
    fi
    readme_path="charts/$top/README.md"
    if [[ ! -f "$readme_path" ]]; then
        # Chart intentionally has no README; nothing to keep in sync.
        continue
    fi
    echo "::warning file=charts/$top/values.yaml::values.yaml changed but README.md was not updated. Confirm the README tables still reflect the values."
    echo "  WARN: charts/$top — values.yaml changed without README.md update"
    warnings=$((warnings + 1))
done

echo "=============================================="
if [[ "$warnings" -eq 0 ]]; then
    echo "SUCCESS: No README sync reminders to emit."
else
    echo "Emitted $warnings README sync reminder(s). Job exits 0 (non-blocking)."
fi
exit 0
