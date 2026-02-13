#!/bin/bash

# Update all cemusei repository dependencies to their latest versions
# Updates the Chart.yaml with the latest versions from https://helm.cmusei.dev/charts

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR/../../charts/crucible"
CHART_FILE="$CHART_DIR/Chart.yaml"
CEMUSEI_REPO="https://helm.cmusei.dev/charts"
REPO_NAME="cemusei"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Updating cemusei chart dependencies"
echo "=========================================="

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo -e "${RED}Error: helm is not installed${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    exit 1
fi

# Run helm repo update
echo -e "${YELLOW}Running helm repo update...${NC}"
helm repo update 2>&1 | grep -v "^Hang"

echo ""
echo "=========================================="
echo "Fetching latest versions..."
echo "=========================================="

# Extract cemusei dependencies from Chart.yaml
declare -a charts_to_update
while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.+)$ ]]; then
        current_chart="${BASH_REMATCH[1]}"
    elif [[ $line =~ ^[[:space:]]*repository:[[:space:]]*(.+)$ ]]; then
        repo="${BASH_REMATCH[1]}"
        if [[ "$repo" == "$CEMUSEI_REPO" ]]; then
            charts_to_update+=("$current_chart")
        fi
    fi
done < "$CHART_FILE"

if [ ${#charts_to_update[@]} -eq 0 ]; then
    echo -e "${RED}No cemusei dependencies found in Chart.yaml${NC}"
    exit 0
fi

# Store version updates
declare -A VERSION_MAP
declare -a UPDATE_LOG
UPDATED=0
FAILED=0

# Fetch latest versions for all charts
for chart_name in "${charts_to_update[@]}"; do
    # echo ""
    # echo "Processing: $chart_name"
    # echo "----------------------------------------"

    # Get current version from Chart.yaml
    current_version=$(grep -A 3 "name: $chart_name" "$CHART_FILE" | grep "version:" | head -1 | sed 's/.*version:[[:space:]]*//')
    # echo "  Current version: $current_version"

    # Get latest version from helm repo
    latest_version=$(helm search repo "$REPO_NAME/$chart_name" --output json 2>/dev/null | jq -r '.[0].version')

    if [ -z "$latest_version" ] || [ "$latest_version" = "null" ]; then
        echo -e "  ${RED}Failed to fetch latest version${NC}"
        UPDATE_LOG+=("$chart_name: FAILED")
        ((FAILED++))
        continue
    fi

    # echo "  Latest version:  $latest_version"

    if [ "$current_version" = "$latest_version" ]; then
        # echo -e "  ${GREEN}Already up to date${NC}"
        UPDATE_LOG+=("$chart_name: $current_version (no change)")
    else
        # echo -e "  ${YELLOW}Will update to $latest_version${NC}"
        VERSION_MAP["$chart_name"]="$latest_version"
        UPDATE_LOG+=("$chart_name: $current_version → $latest_version")
        ((UPDATED++))
    fi
done

# Apply all updates in a single pass if there are any
if [ $UPDATED -gt 0 ]; then
    echo ""
    echo "=========================================="
    echo "Applying updates to Chart.yaml..."
    echo "=========================================="

    # Create backup
    cp "$CHART_FILE" "$CHART_FILE.backup"

    # Build awk script to update all versions at once
    AWK_SCRIPT='BEGIN { in_chart=0; chart_name="" }'

    # Add pattern matching for each chart
    for chart_name in "${!VERSION_MAP[@]}"; do
        new_version="${VERSION_MAP[$chart_name]}"
        AWK_SCRIPT+='
/^[[:space:]]*-[[:space:]]*name:[[:space:]]*'"$chart_name"'[[:space:]]*$/ {
    in_chart=1
    chart_name="'"$chart_name"'"
    print
    next
}'
    done

    # Add version replacement logic
    AWK_SCRIPT+='
/^[[:space:]]*version:[[:space:]]*/ {
    if (in_chart && chart_name != "") {
        new_ver=""'

    for chart_name in "${!VERSION_MAP[@]}"; do
        new_version="${VERSION_MAP[$chart_name]}"
        AWK_SCRIPT+='
        if (chart_name == "'"$chart_name"'") new_ver="'"$new_version"'"'
    done

    AWK_SCRIPT+='
        if (new_ver != "") {
            sub(/version:[[:space:]]*[^[:space:]]*/, "version: " new_ver)
        }
        in_chart=0
        chart_name=""
    }
}
{ print }'

    # Apply all updates
    temp_file=$(mktemp)
    if awk "$AWK_SCRIPT" "$CHART_FILE" > "$temp_file"; then
        mv "$temp_file" "$CHART_FILE"
        echo -e "${GREEN}Successfully updated Chart.yaml${NC}"
        rm -f "$CHART_FILE.backup"

        # Run helm dependency update
        echo ""
        echo -e "${YELLOW}Running helm dependency update...${NC}"
        if helm dependency update "$CHART_DIR"; then
            echo -e "${GREEN}Successfully updated chart dependencies${NC}"
        else
            echo -e "${RED}Failed to update chart dependencies${NC}"
            exit 1
        fi
    else
        echo -e "${RED}Failed to update Chart.yaml, restoring backup${NC}"
        mv "$CHART_FILE.backup" "$CHART_FILE"
        rm -f "$temp_file"
        exit 1
    fi
fi

echo ""
echo "=========================================="
echo "Update Summary"
echo "=========================================="

# Print detailed log
for log_entry in "${UPDATE_LOG[@]}"; do
    if [[ $log_entry == *"→"* ]]; then
        echo -e "${BLUE}✓${NC} $log_entry"
    elif [[ $log_entry == *"FAILED"* ]]; then
        echo -e "${RED}✗${NC} $log_entry"
    else
        echo -e "${GREEN}•${NC} $log_entry"
    fi
done

echo ""
echo -e "Charts updated: ${GREEN}$UPDATED${NC}"
echo -e "Charts failed:  ${RED}$FAILED${NC}"
echo ""

if [ $UPDATED -gt 0 ]; then
    echo -e "${GREEN}All chart dependencies have been updated successfully!${NC}"
else
    echo "All charts are already up to date."
fi

echo "=========================================="
