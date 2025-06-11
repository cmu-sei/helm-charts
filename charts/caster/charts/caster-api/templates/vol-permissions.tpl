{{- define "vol-permissions" }}
#!/bin/bash

if [ "${SKIP_VOL_PERMISSIONS,,}" == "true" ]; then
    exit 0
fi

if find /terraform -maxdepth 1 \! -user 1654 -o \! -group 1654 | grep -q .; then
    echo "Updating volume permissions for non-root app user"
    chown -R 1654:1654 /terraform
else
    echo "Volume permissions already correct, skipping chown."
fi
{{- end }}