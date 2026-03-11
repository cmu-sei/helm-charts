# Migrating from Bitnami Moodle to the SEI Moodle Chart

This guide walks through the steps required to migrate an existing Moodle deployment that uses the [Bitnami Moodle Helm chart](https://artifacthub.io/packages/helm/bitnami/moodle) and [container image](https://hub.docker.com/r/bitnamilegacy/moodle) to the SEI Moodle Helm chart, which uses the lightweight [Alpine Linux based Moodle image](https://github.com/erseco/alpine-moodle).

## Why migrate?

Bitnami has archived the majority of its public container images and Helm charts to a legacy registry (`bitnamilegacy/moodle`). **Legacy artifacts remain available but are no longer updated (including security fixes) and relying on them will not be a viable option in the future.** The SEI Moodle chart provides an actively maintained alternative with additional features including automated OIDC configuration, read-only dirroot support, and multi-replica scaling.

## Assumptions

- You are running the **same Moodle version** on the Bitnami chart that the SEI chart targets (e.g. both are Moodle 5.0.x). If not, [upgrade your Bitnami Moodle first](https://docs.moodle.org/en/Upgrading).
- Moodle is using **PostgreSQL** as its database.
- You have `kubectl` and `helm` (v3+) access to the cluster.
- You have access to the SEI Helm chart repository or a local copy of the chart.

## Key differences between the charts

| Aspect                | Bitnami Chart                                              | SEI Chart                                                          |
| --------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------ |
| **Base Image**        | Debian-based (`bitnami/moodle`)                            | Alpine Linux (`erseco/alpine-moodle`)                              |
| **Moodle Code Path**  | `/bitnami/moodle` (on PVC)                                 | `/var/www/html` (from container image)                             |
| **Moodledata Path**   | `/bitnami/moodledata` (on PVC)                             | `/var/www/moodledata` (on PVC)                                     |
| **PVC Layout**        | Single PVC with two subPaths (`moodle/` and `moodledata/`) | Separate PVC for `moodledata` only; code comes from the image      |
| **Config Generation** | Bitnami bootstrap writes `config.php` to PVC               | Image generates `config.php` at runtime from environment variables |
| **Run-as User**       | UID 1 (`daemon`)                                           | UID 65534 (`nobody`)                                               |
| **OIDC Support**      | Manual post-install configuration                          | Built-in automated OIDC setup via chart values                     |

## Before migrating

### Back up the database

Identify your PostgreSQL connection details from your Bitnami Moodle values file or from the running pod's `config.php`:

```bash
MOODLE_POD=$(kubectl get pods -n <namespace> -l app.kubernetes.io/name=moodle -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n <namespace> "$MOODLE_POD" -- grep -E "dbhost|dbname|dbuser" /bitnami/moodle/config.php
```

**Database running in a pod inside the cluster:**

```bash
kubectl exec -n <namespace> <postgresql-pod> -- \
  sh -c "PGPASSWORD='<password>' pg_dump -U <user> -d <database> -F c --blobs --no-owner --no-privileges" \
  | gzip -c > moodle_db_backup.dump.gz
```

**Database located outside the cluster:**

```bash
PGPASSWORD='<password>' pg_dump -h <host> -U <user> -d <database> \
  --format=custom --blobs --no-owner --no-privileges \
  | gzip > moodle_db_backup.dump.gz
```

### Back up moodledata

```bash
MOODLE_POD=$(kubectl get pods -n <namespace> -l app.kubernetes.io/name=moodle -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n <namespace> "$MOODLE_POD" -- \
  tar -C /bitnami -cf - moodledata | gzip -c > moodle_moodledata_backup.tar.gz
```

### Back up Moodle software (optional)

If your installation includes custom plugins or code modifications:

```bash
kubectl exec -n <namespace> "$MOODLE_POD" -- \
  tar -C /bitnami -cf - moodle | gzip -c > moodle_software_backup.tar.gz
```

## Migration steps

### 1. Enable maintenance mode

Put Moodle into maintenance mode to prevent user activity during the migration. Log in as an administrator and navigate to:

`Site administration > Server > Maintenance mode`

Set **Maintenance mode** to **Enable** and save. Alternatively, use the CLI:

```bash
kubectl exec -n <namespace> "$MOODLE_POD" -- \
  php /bitnami/moodle/admin/cli/maintenance.php --enable
```

### 2. Record your current deployment details

Save your current Helm values and release information for reference:

```bash
helm get values moodle -n <namespace> > bitnami-moodle-values-backup.yaml
helm list -n <namespace> | grep moodle
```

Note the Bitnami PVC name and its associated PV:

```bash
PVC_NAME=$(kubectl get pvc -n <namespace> -l app.kubernetes.io/name=moodle -o jsonpath='{.items[0].metadata.name}')
PV_NAME=$(kubectl get pvc -n <namespace> "$PVC_NAME" -o jsonpath='{.spec.volumeName}')
echo "PVC: $PVC_NAME"
echo "PV:  $PV_NAME"
```

The PVC is typically named `<release>-moodle` (e.g. `moodle-moodle`). Record both names for later steps.

### 3. Protect the data from deletion

The Bitnami Helm chart owns the PVC, so `helm uninstall` will delete it. The PV reclaim policy ensures the underlying storage is preserved even if the PVC is removed.

```bash
# Prevent the PV from being deleted when the PVC is removed
kubectl patch pv "$PV_NAME" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

Verify the change:

```bash
kubectl get pv "$PV_NAME" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'
# Expected: Retain
```

### 4. Uninstall the Bitnami Helm release

```bash
helm uninstall moodle -n <namespace>
```

The PVC will be deleted by the uninstall, but the PV and its data are preserved because of the `Retain` reclaim policy set in step 3. Verify the PV still exists:

```bash
kubectl get pv "$PV_NAME"
# Should show STATUS: Released
```

### 5. Re-create a PVC bound to the retained PV

The PV is in `Released` state and still references the deleted PVC. Clear the old claim reference and create a new PVC that binds to it:

```bash
# Clear the old claim reference so the PV becomes Available
kubectl patch pv "$PV_NAME" --type json -p '[{"op":"remove","path":"/spec/claimRef"}]'
```

Verify the PV is now `Available`:

```bash
kubectl get pv "$PV_NAME"
# Should show STATUS: Available
```

Create a new PVC bound to the retained PV. Replace `<storage-class>` and `<size>` with the values from your original PVC (from step 2):

```bash
cat <<EOF | kubectl apply -n <namespace> -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: moodle-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: <size>  # e.g. 8Gi — must match the PV capacity
  storageClassName: <storage-class>  # e.g. standard, gp3, longhorn
  volumeName: $PV_NAME
EOF
```

Verify the new PVC is bound:

```bash
kubectl get pvc -n <namespace> moodle-data
# Should show STATUS: Bound
```

### 6. Fix file ownership and remove maintenance mode file

The Bitnami image runs as UID 1 (`daemon`) while the SEI image runs as UID 65534 (`nobody`). The file ownership on the existing PVC must be updated. Additionally, the maintenance mode marker file (`climaintenance.html`) must be removed so the SEI pod's startup probes can pass.

Run a temporary pod to fix ownership and remove the maintenance file:

```bash
kubectl run fix-permissions -n <namespace> --rm -it \
  --image=alpine:latest \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "fix-permissions",
        "image": "alpine:latest",
        "command": ["sh", "-c", "chown -R 65534:65534 /mnt/data/moodledata && rm -f /mnt/data/moodledata/climaintenance.html && echo Done"],
        "volumeMounts": [{
          "name": "moodle-data",
          "mountPath": "/mnt/data"
        }]
      }],
      "volumes": [{
        "name": "moodle-data",
        "persistentVolumeClaim": {
          "claimName": "moodle-data"
        }
      }],
      "restartPolicy": "Never"
    }
  }'
```

### 7. Update database paths

Moodle may store absolute file paths in its `mdl_config` table that reference the old Bitnami directory layout. These must be updated to match the SEI chart's paths.

Check for any values that reference the old Bitnami path:

```bash
kubectl exec -n <namespace> <postgresql-pod> -- \
  sh -c "PGPASSWORD='<password>' psql -U <user> -d <database> -t -c \
    \"SELECT name, value FROM mdl_config WHERE value LIKE '%/bitnami%';\""
```

If any rows are returned, update them:

```bash
kubectl exec -n <namespace> <postgresql-pod> -- \
  sh -c "PGPASSWORD='<password>' psql -U <user> -d <database> -c \
    \"UPDATE mdl_config SET value = REPLACE(value, '/bitnami/moodledata', '/var/www/moodledata') WHERE value LIKE '%/bitnami/moodledata%';\""
```

Verify no Bitnami references remain:

```bash
kubectl exec -n <namespace> <postgresql-pod> -- \
  sh -c "PGPASSWORD='<password>' psql -U <user> -d <database> -t -c \
    \"SELECT name, value FROM mdl_config WHERE value LIKE '%/bitnami%';\""
```

### 8. Prepare the SEI chart values file

Create a values file for the SEI Moodle chart. The key settings to configure are:

- **Database**: Point to the same PostgreSQL instance and database used by the Bitnami deployment.
- **Persistence**: Reference the new PVC created in step 5 with `subPath: moodledata` so the SEI chart mounts only the moodledata subdirectory.
- **Site URL**: Must match the original `wwwroot` from the Bitnami deployment.
- **Table prefix**: Must match the prefix used by the existing database (default is `mdl_`).

```yaml
image:
  repository: erseco/alpine-moodle
  tag: v5.0.1 # Must match your current Moodle version
  pullPolicy: IfNotPresent

moodle:
  admin:
    username: "<your-admin-username>"
    existingSecret: "<your-admin-secret>" # Or set password directly
    existingSecretKey: "admin-password"

  site:
    url: "https://your-moodle-domain.com" # Must match your current wwwroot
    name: "Your-Site-Name"

  proxy:
    sslProxy: true # Set to true if behind an SSL-terminating proxy

  database:
    type: "pgsql"
    host: "<postgresql-host>"
    port: "5432"
    name: "<database-name>"
    user: "<database-user>"
    prefix: "mdl_"
    existingSecret: "<your-db-secret>"
    existingSecretPasswordKey: "postgres-password"
    create_database: false # Database already exists

## Reuse the retained PV via the new PVC — mount only the moodledata subdirectory
persistence:
  moodledata:
    enabled: true
    type: persistentVolumeClaim
    existingClaim: "moodle-data"
    subPath: "moodledata"
    mountPath: /var/www/moodledata

## Configure ingress to match your current setup
ingress:
  enabled: true
  className: "nginx"
  hostname: "your-moodle-domain.com"
  path: /
  pathType: Prefix
  tls:
    - hosts:
        - your-moodle-domain.com
      secretName: your-tls-secret
```

> **Important:** Set `create_database: false` since the database already exists with data from the Bitnami deployment. The SEI chart's database creation job would skip it anyway (it is idempotent), but disabling it avoids running the job entirely.

### 9. Add the SEI Helm repository

If you have not already added the SEI Helm repository:

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm repo update
```

If you are using a local copy of the chart, skip this step and reference the chart directory in the install command below.

### 10. Install the SEI Moodle chart

```bash
# From the SEI Helm repository:
helm install moodle sei/moodle -n <namespace> -f sei-moodle-values.yaml

# Or from a local chart directory:
helm install moodle /path/to/charts/moodle -n <namespace> -f sei-moodle-values.yaml
```

Monitor the rollout:

```bash
kubectl get pods -n <namespace> -l app.kubernetes.io/name=moodle -w
```

The SEI image will detect the existing Moodle database tables, skip the initial installation, and generate a new `config.php` from the environment variables. Wait until the pod reaches `Running` and `1/1 Ready`.

### 11. Verify the migration

Confirm the new deployment is working correctly:

```bash
# Check pod status
kubectl get pods -n <namespace> -l app.kubernetes.io/name=moodle

# Check Moodle configuration
NEW_POD=$(kubectl get pods -n <namespace> -l app.kubernetes.io/name=moodle -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n <namespace> "$NEW_POD" -- cat /var/www/html/config.php

# Verify moodledata is accessible
kubectl exec -n <namespace> "$NEW_POD" -- ls -la /var/www/moodledata/

# Test the login page
kubectl exec -n <namespace> "$NEW_POD" -- wget -qO- http://127.0.0.1:8080/login/index.php | head -5
```

Confirm that:

- The `config.php` shows `dataroot` as `/var/www/moodledata`
- The `moodledata` directory contains your existing data (`filedir/`, `cache/`, `lang/`, etc.)
- The login page loads successfully

### 12. Purge Moodle caches

After migration, purge Moodle's caches to clear any stale references:

```bash
kubectl exec -n <namespace> "$NEW_POD" -- php /var/www/html/admin/cli/purge_caches.php
```

### 13. Clean up (optional)

The PV still contains the old Moodle application code in the `moodle/` subdirectory from the Bitnami deployment. Since the SEI chart only uses the `moodledata/` subdirectory, you can remove the old code to reclaim space:

```bash
kubectl run cleanup -n <namespace> --rm -it \
  --image=alpine:latest \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "cleanup",
        "image": "alpine:latest",
        "command": ["sh", "-c", "rm -rf /mnt/data/moodle && echo Cleaned up old Moodle code"],
        "volumeMounts": [{
          "name": "moodle-data",
          "mountPath": "/mnt/data"
        }]
      }],
      "volumes": [{
        "name": "moodle-data",
        "persistentVolumeClaim": {
          "claimName": "moodle-data"
        }
      }],
      "restartPolicy": "Never"
    }
  }'
```

## Rollback

If the migration fails and you need to restore the Bitnami deployment:

1. Uninstall the SEI release:

   ```bash
   helm uninstall moodle -n <namespace>
   ```

2. Restore file ownership for the Bitnami image (UID 1):

   ```bash
   kubectl run fix-permissions -n <namespace> --rm -it \
     --image=alpine:latest \
     --overrides='{
       "spec": {
         "containers": [{
           "name": "fix-permissions",
           "image": "alpine:latest",
           "command": ["sh", "-c", "chown -R 1:1 /mnt/data/moodledata && echo Done"],
           "volumeMounts": [{
             "name": "moodle-data",
             "mountPath": "/mnt/data"
           }]
         }],
         "volumes": [{
           "name": "moodle-data",
           "persistentVolumeClaim": {
             "claimName": "moodle-data"
           }
         }],
         "restartPolicy": "Never"
       }
     }'
   ```

3. Revert any database path updates:

   ```bash
   kubectl exec -n <namespace> <postgresql-pod> -- \
     sh -c "PGPASSWORD='<password>' psql -U <user> -d <database> -c \
       \"UPDATE mdl_config SET value = REPLACE(value, '/var/www/moodledata', '/bitnami/moodledata') WHERE value LIKE '%/var/www/moodledata%';\""
   ```

4. Reinstall the Bitnami chart with your original values, using the retained PVC:

   ```bash
   helm install moodle oci://registry-1.docker.io/bitnamicharts/moodle \
     --version <your-bitnami-chart-version> \
     -n <namespace> \
     -f bitnami-moodle-values-backup.yaml \
     --set persistence.existingClaim=moodle-data \
     --set moodleSkipInstall=true
   ```

## Restoring from backup (alternative approach)

If you prefer a clean-slate migration or if the PV reuse approach is not possible (for example, if the PV has already been deleted), you can deploy a fresh SEI Moodle instance and restore from the backups taken earlier.

### 1. Install the SEI chart with a new PVC

Modify the values file to create a new PVC instead of referencing an existing one:

```yaml
persistence:
  moodledata:
    enabled: true
    type: persistentVolumeClaim
    accessMode: ReadWriteOnce
    size: 20Gi
```

Install the chart and wait for the initial setup to complete. The image will create a fresh Moodle installation.

### 2. Restore the database

Drop the newly-created database and restore from backup.

**Database running in a pod inside the cluster:**

```bash
kubectl exec -n <namespace> <postgresql-pod> -- \
  sh -c "PGPASSWORD='<password>' dropdb -U <user> <database>"

kubectl exec -n <namespace> <postgresql-pod> -- \
  sh -c "PGPASSWORD='<password>' createdb -U <user> <database>"

gunzip -c moodle_db_backup.dump.gz | \
  kubectl exec -i -n <namespace> <postgresql-pod> -- \
  sh -c "PGPASSWORD='<password>' pg_restore -U <user> -d <database> --no-owner --no-privileges"
```

**Database located outside the cluster:**

```bash
PGPASSWORD='<password>' dropdb -h <host> -U <user> <database>

PGPASSWORD='<password>' createdb -h <host> -U <user> <database>

gunzip -c moodle_db_backup.dump.gz | \
  PGPASSWORD='<password>' pg_restore -h <host> -U <user> -d <database> --no-owner --no-privileges
```

### 3. Restore moodledata

Copy the moodledata backup into the new pod. The backup was created with `-C /bitnami`, so it extracts the `moodledata/` directory:

```bash
NEW_POD=$(kubectl get pods -n <namespace> -l app.kubernetes.io/name=moodle -o jsonpath='{.items[0].metadata.name}')

# Extract the backup — moodledata/ lands at /var/www/moodledata_restored
gunzip -c moodle_moodledata_backup.tar.gz | \
  kubectl exec -i -n <namespace> "$NEW_POD" -- tar -C /var/www -xf -

# Replace the SEI-generated moodledata with the restored data
kubectl exec -n <namespace> "$NEW_POD" -- sh -c "
  rm -rf /var/www/moodledata_old
  mv /var/www/moodledata /var/www/moodledata_old
  mv /var/www/moodledata /var/www/moodledata 2>/dev/null || true
"
```

> **Note:** If the tar extracts as `moodledata/` inside the mount, the data overwrites in place. Verify the contents after extraction:
>
> ```bash
> kubectl exec -n <namespace> "$NEW_POD" -- ls -la /var/www/moodledata/
> ```

### 4. Update database paths and purge caches

Follow step 7 from the main migration procedure above to update any `/bitnami` paths in the database, then purge caches:

```bash
kubectl exec -n <namespace> "$NEW_POD" -- php /var/www/html/admin/cli/purge_caches.php
```

### 5. Restart the pod

```bash
kubectl rollout restart deployment -n <namespace> moodle
```

## References

- [Moodle Site backup](https://docs.moodle.org/500/en/Site_backup)
- [Moodle Upgrading](https://docs.moodle.org/en/Upgrading)
- [Alpine Moodle Image](https://github.com/erseco/alpine-moodle)
- [SEI Moodle Helm Chart](https://helm.cmusei.dev/charts)
- [Bitnami Legacy Notice](https://community.broadcom.com/blogs/beltran-rueda-borrego/2025/08/18/how-to-prepare-for-the-bitnami-changes-coming-soon)
