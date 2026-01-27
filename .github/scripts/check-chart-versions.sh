#!/bin/bash
# This script checks that chart versions are incremented when chart files are modified.
# It compares the current branch against the base branch and fails if any chart has
# changes to values.yaml or Chart.yaml without a corresponding version bump.
#
# When a sub-chart is modified (e.g., charts/alloy/charts/alloy-api),
# the parent chart (charts/alloy) must also have its version incremented.

set -euo pipefail

CHART_FILES_PATTERN='^charts/.*/(values\.yaml|Chart\.yaml)$'
SUBCHART_PATTERN='^charts/([^/]+)/charts/([^/]+)$'

# Extract version from a Chart.yaml file
extract_version() {
    local source="$1"

    if [[ "$source" == *:* ]]; then
        # Git reference format: "ref:path"
        git show "$source" 2>/dev/null | grep -E '^version:' | head -1 | awk '{print $2}' | tr -d "\"'" || echo ""
    else
        # Local file path
        grep -E '^version:' "$source" 2>/dev/null | head -1 | awk '{print $2}' | tr -d "\"'" || echo ""
    fi
}

array_has_key() {
    local key="$1"
    local -n arr="$2"
    [[ -v arr["$key"] ]]
}

local base_ref="${1:-origin/main}"

echo "Checking chart versions against base: $base_ref"
echo "=============================================="

# Get list of changed files compared to base
local changed_files
changed_files=$(git diff --name-only "$base_ref"...HEAD 2>/dev/null || git diff --name-only "$base_ref" HEAD)

if [[ -z "$changed_files" ]]; then
    echo "No changed files detected."
    exit 0
fi

# Find all chart directories that have modified chart files
declare -A modified_charts

while IFS= read -r file; do
    if [[ "$file" =~ $CHART_FILES_PATTERN ]]; then
        local chart_dir
        chart_dir=$(dirname "$file")

        # Include if Chart.yaml exists or this file IS the Chart.yaml
        if [[ -f "$chart_dir/Chart.yaml" || "$file" == */Chart.yaml ]]; then
            modified_charts["$chart_dir"]=1
        fi
    fi
done <<< "$changed_files"

if [[ ${#modified_charts[@]} -eq 0 ]]; then
    echo "No chart files (values.yaml or Chart.yaml) were modified."
    exit 0
fi

# Identify parent charts that need version bumps due to sub-chart changes
# Structure: charts/<parent>/charts/<sub-chart> -> parent is charts/<parent>
declare -A parent_charts

for chart_dir in "${!modified_charts[@]}"; do
    if [[ "$chart_dir" =~ $SUBCHART_PATTERN ]]; then
        local parent_dir="charts/${BASH_REMATCH[1]}"

        if [[ -f "$parent_dir/Chart.yaml" ]]; then
            parent_charts["$parent_dir"]="$chart_dir"
        fi
    fi
done

# Add parent charts to the list of charts requiring version check
for parent_dir in "${!parent_charts[@]}"; do
    if ! array_has_key "$parent_dir" modified_charts; then
        modified_charts["$parent_dir"]="parent"
    fi
done

# Print summary of charts to check
echo "Found ${#modified_charts[@]} chart(s) requiring version check:"
printf '  - %s\n' "${!modified_charts[@]}"

if [[ ${#parent_charts[@]} -gt 0 ]]; then
    echo ""
    echo "Parent charts requiring update due to sub-chart changes:"
    for parent_dir in "${!parent_charts[@]}"; do
        echo "  - $parent_dir (sub-chart: ${parent_charts[$parent_dir]})"
    done
fi
echo ""

# Check each chart for version bump
local failed_charts=()

for chart_dir in "${!modified_charts[@]}"; do
    local chart_yaml="$chart_dir/Chart.yaml"

    echo "Checking: $chart_dir"

    if [[ ! -f "$chart_yaml" ]]; then
        echo "  Warning: Chart.yaml not found, skipping..."
        continue
    fi

    local current_version
    current_version=$(extract_version "$chart_yaml")

    if [[ -z "$current_version" ]]; then
        echo "  Error: Could not parse version from Chart.yaml"
        failed_charts+=("$chart_dir (could not parse version)")
        continue
    fi

    local base_version
    base_version=$(extract_version "$base_ref:$chart_yaml")

    if [[ -z "$base_version" ]]; then
        echo "  New chart (not in base branch)"
        echo "  Current version: $current_version"
        echo ""
        continue
    fi

    echo "  Base version:    $base_version"
    echo "  Current version: $current_version"

    if [[ "$base_version" == "$current_version" ]]; then
        echo "  FAILED: Version was not incremented!"

        if array_has_key "$chart_dir" parent_charts; then
            failed_charts+=("$chart_dir ($base_version -> $current_version) [parent of ${parent_charts[$chart_dir]}]")
        else
            failed_charts+=("$chart_dir ($base_version -> $current_version)")
        fi
    else
        echo "  OK: Version was updated"
    fi
    echo ""
done

# Print final results
echo "=============================================="

if [[ ${#failed_charts[@]} -gt 0 ]]; then
    echo "ERROR: The following charts have changes without version bumps:"
    printf '  - %s\n' "${failed_charts[@]}"
    echo ""
    echo "Please increment the 'version' field in Chart.yaml for each chart listed above."
    echo "Note: When a sub-chart is modified, its parent chart must also be versioned."
    exit 1
fi

echo "SUCCESS: All modified charts have updated versions."
exit 0
