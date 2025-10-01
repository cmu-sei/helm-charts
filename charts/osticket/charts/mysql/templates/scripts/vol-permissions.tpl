{{- define "vol-permissions" }}
#!/bin/bash

DIR="${1}"
USER_ID="${2:-1001}"
GROUP_ID="${3:-1001}"

echo "Checking and updating ownership in: $DIR for UID:GID = $USER_ID:$GROUP_ID"

if find "$DIR" \( \! -user "$USER_ID" -o \! -group "$GROUP_ID" \) -exec chown "$USER_ID:$GROUP_ID" {} +; then
    echo "Ownership check/update completed successfully."
else
    echo "Error: Failed to update file ownership."
    exit 1
fi
{{- end }}