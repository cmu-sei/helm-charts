#!/bin/bash
# This script checks that chart versions are incremented when chart files are modified.
# It compares the current branch against the base branch and fails if any chart has
#
# When a sub-chart is modified (e.g., charts/alloy/charts/alloy-api),
# the parent chart (charts/alloy) must also have its version incremented.

set -euo pipefail

SUBCHART_PATTERN='^charts/([^/]+)/charts/([^/]+)'

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

# Find the chart directory for a given file path
# Walks up the directory tree to find the nearest Chart.yaml
find_chart_dir() {
    local file_path="$1"
    local current_dir

    # If it's a file, start from its directory; if it's a directory, start from there
    if [[ -f "$file_path" ]]; then
        current_dir=$(dirname "$file_path")
    else
        current_dir="$file_path"
    fi

    # Walk up the directory tree looking for Chart.yaml
    while [[ "$current_dir" != "." && "$current_dir" != "/" ]]; do
        if [[ -f "$current_dir/Chart.yaml" ]]; then
            echo "$current_dir"
            return 0
        fi
        current_dir=$(dirname "$current_dir")
    done

    # No Chart.yaml found
    return 1
}

base_ref="${1:-origin/main}"

echo "Checking chart versions against base: $base_ref"
echo "=============================================="

# Get list of changed files compared to base
changed_files=$(git diff --name-only "$base_ref"...HEAD 2>/dev/null || git diff --name-only "$base_ref" HEAD)

if [[ -z "$changed_files" ]]; then
    echo "No changed files detected."
    exit 0
fi

# Find all chart directories that have modified files
declare -A modified_charts
has_charts=false

while IFS= read -r file; do
    # Only process files under charts/ directory
    if [[ "$file" =~ ^charts/ ]]; then
        if chart_dir=$(find_chart_dir "$file"); then
            modified_charts["$chart_dir"]=1
            has_charts=true
        fi
    fi
done <<< "$changed_files"

# Check if any charts were modified
if [[ "$has_charts" == "false" ]]; then
    echo "No chart files were modified."
    exit 0
fi

# Identify parent charts that need version bumps due to sub-chart changes
# Structure: charts/<parent>/charts/<sub-chart> -> parent is charts/<parent>
declare -A parent_charts
has_parents=false

for chart_dir in "${!modified_charts[@]}"; do
    if [[ "$chart_dir" =~ $SUBCHART_PATTERN ]]; then
        parent_dir="charts/${BASH_REMATCH[1]}"

        if [[ -f "$parent_dir/Chart.yaml" ]]; then
            parent_charts["$parent_dir"]="$chart_dir"
            has_parents=true
        fi
    fi
done

# Add parent charts to the list of charts requiring version check
if [[ "$has_parents" == "true" ]]; then
    for parent_dir in "${!parent_charts[@]}"; do
        if ! array_has_key "$parent_dir" modified_charts; then
            modified_charts["$parent_dir"]="parent"
        fi
    done
fi

# Check each chart for version bump
failed_charts=()

for chart_dir in "${!modified_charts[@]}"; do
    chart_yaml="$chart_dir/Chart.yaml"

    if [[ ! -f "$chart_yaml" ]]; then
        continue
    fi

    current_version=$(extract_version "$chart_yaml")

    if [[ -z "$current_version" ]]; then
        echo "Error: Could not parse version from $chart_yaml"
        failed_charts+=("$chart_dir (could not parse version)")
        continue
    fi

    base_version=$(extract_version "$base_ref:$chart_yaml")

    if [[ -z "$base_version" ]]; then
        echo "New chart (not in base branch)"
        echo "Current version: $current_version"
        echo ""
        continue
    fi

    if [[ "$base_version" == "$current_version" ]]; then

        if [[ "$has_parents" == "true" ]] && array_has_key "$chart_dir" parent_charts; then
            failed_charts+=("$chart_dir ($base_version -> $current_version) [parent of ${parent_charts[$chart_dir]}]")
        else
            failed_charts+=("$chart_dir ($base_version -> $current_version)")
        fi
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
