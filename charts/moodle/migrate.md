# Migrating Bitnami Moodle 5.0.2 to SEI Moodle 5.2.2

This guide migrates a deployment running the Bitnami Moodle 5.0.2 image to the SEI Moodle chart running `erseco/alpine-moodle:v5.2.2`. It does not apply to another source Moodle version.

## Why migrate?

Bitnami has archived the majority of its public container images and Helm charts to a legacy registry (`bitnamilegacy/moodle`). **Legacy artifacts remain available but are no longer updated (including security fixes) and relying on them will not be a viable option in the future.** The SEI Moodle chart provides an actively maintained alternative with additional features including automated OIDC configuration, read-only dirroot support, and multi-replica scaling.

## Assumptions

- The source deployment runs the Bitnami Moodle **5.0.2** image and the target SEI chart runs Moodle **5.2.2**. This guide does not cover another source Moodle version.
- Moodle uses **PostgreSQL 16 or newer**, the minimum PostgreSQL version supported by Moodle 5.2.
- You have `kubectl` and `helm` (v3+) access to the cluster.
- You have access to the SEI Helm chart repository or a local copy of the chart.
- **The Bitnami release owns its PVC and its admin secret.** If it was deployed with `persistence.existingClaim` or `existingSecret` it owns neither, and steps 2, 3, 5 and 14 do not apply: `helm uninstall` leaves the claim `Bound` and your secret untouched, so skip the reclaim-policy and re-bind work and point the new release at the claim you already have.

## Key differences between the charts

| Aspect                | Bitnami Chart                                              | SEI Chart                                                          |
| --------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------ |
| **Base Image**        | Debian-based (`bitnami/moodle`)                            | Alpine Linux (`erseco/alpine-moodle`)                              |
| **Code path** (dirroot) | `/bitnami/moodle` (on PVC)                                 | `/var/www/html` (from container image)                             |
| **Data path** (dataroot) | `/bitnami/moodledata` (on PVC)                             | `/var/www/moodledata` (on PVC)                                     |
| **PVC Layout**        | Single PVC with two subPaths (`moodle/` and `moodledata/`) | Separate PVC for `moodledata` only; code comes from the image      |
| **Config Generation** | Bitnami bootstrap writes `config.php` to PVC               | Image generates `config.php` at runtime from environment variables |
| **Run-as User**       | UID 1001, group 0, but UID 1 (`daemon`) whenever the security contexts are disabled | UID 65534 (`nobody`)                                               |
| **Third-party code**  | Anything dropped into `/bitnami/moodle` lives on the PVC    | dirroot comes from the image; extra plugins are declared in `moodle.plugins` |
| **OIDC Support**      | Manual post-install configuration                          | Built-in automated OIDC setup via chart values                     |

**⚠️ Plugin persistence changes with this migration:**

On Bitnami the code tree lives on a PVC, so a plugin installed once stays there. Here dirroot comes from the image and is rebuilt for every pod, so each `moodle.plugins` entry is downloaded again on every pod start and an unreachable source stops the pod serving. A named PVC at one replica with `updateStrategy.type: Recreate` keeps the tree between pods, in either dirroot mode: the recommended target for a single-replica Bitnami site. A plugin the directory does not publish at the version you need is declared with a `url` pointing at a zip, plus its `version`.

## Migrating onto a read-only dirroot

`readOnlyDirroot.enabled: true` is Moodle's recommendation for a cluster and is where most migrations should land. It does not change this procedure. The database, the `moodledata` hand-over, the path rewrite and the values file are all the same, but it hardens two assumptions into rules:

- **dirroot comes from the image, not from `/bitnami/moodle`, and is mounted read-only.** With the default `emptyDir` it is rebuilt on every pod start; on a named PVC it is reused when the version matches. Nothing can be added by hand afterwards. Everything the site needs must be declared before you install, and a missed plugin fails quietly: it goes *missing from disk* and its URLs 404 while every other page still answers 200
- **`config.php` is written by the chart** at mode `0444`, and always sets `directorypermissions`, `preventexecpath` and `enableanalytics: false`. These win over the database, so a site using Moodle Analytics loses it when you switch over. To keep other settings, supply the whole file through `readOnlyDirroot.secret.name`. There is no partial override

Two consequences before you commit:

- With the default `emptyDir` code volume a declared plugin is fetched on every pod start; a named PVC keeps it. Pin `version` regardless, so pods started at different moments cannot get different code
- Clear the Bitnami-era `localcache/` while the volume is detached in step 6. At one pod Moodle will use what is there; above one pod a per-pod `emptyDir` hides rather than removes it

Migrating with `readOnlyDirroot.enabled: false` and turning it on afterwards is also supported: the switch moves no data, it replaces the pod.

## Before migrating

**Enable maintenance mode first** (step 1 below), then take the backups. A database dump and a
`moodledata` tar taken while users are still writing describe two different moments, and the pair
cannot be restored consistently.

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

Keep this archive: it is where plugin versions the Moodle plugins directory does not publish have to come from.

### Inventory your third-party code

This chart does not carry `/bitnami/moodle` across, so every plugin you added by hand must be re-declared in `moodle.plugins` or the database will refer to code that is no longer on disk. List them before you uninstall anything:

**Important:** `kubectl exec` runs as root, and any Moodle CLI bootstraps caches as it starts. On a still-live Bitnami site that leaves root-owned directories the web user cannot write, and the site answers *"Invalid permissions detected when trying to create a directory"*. Run CLI on the Bitnami pod as the web user, or chown `moodledata` back afterwards.

```bash
kubectl exec -n <namespace> "$MOODLE_POD" -- \
  php /bitnami/moodle/admin/cli/uninstall_plugins.php --show-contrib
```

Each plugin it prints needs an entry in `moodle.plugins` in step 8. Treat the reported version as the database floor, then select a release that supports Moodle 5.2. Run the same command against the migrated site in step 11 to confirm nothing was left behind.

**Important:**

- Subplugins shipped inside a parent plugin's archive appear in the list but must not be declared separately; declaring the parent brings them
- Nothing resolves dependencies, so declare every plugin that a declared plugin requires
- Select a release of every plugin that supports Moodle 5.2 and is not older than the version recorded in the source database. If the Moodle plugins directory does not publish that release, provide a compatible archive with `url` and `version`; older code fails with `cannotdowngrade`
- Anything that is not a plugin (a patched core file, an edited theme) has no `moodle.plugins` entry. Place it with an `initContainers` entry writing into the code volume, or carry it in your own image built `FROM` the Moodle one

## Migration steps

### 1. Enable maintenance mode

Put Moodle into maintenance mode to prevent user activity during the migration. Log in as an administrator and navigate to:

`Site administration > Server > Maintenance mode`

Set **Maintenance mode** to **Enable** and save. Alternatively, use the CLI:

```bash
kubectl exec -n <namespace> "$MOODLE_POD" -- \
  php /bitnami/moodle/admin/cli/maintenance.php --enable
```

> **Maintenance mode does not carry across.** The image runs `maintenance.php --disable` on
> every boot, so the migrated site is open the moment the pod is Ready, before you verify anything
> in step 11. Do not try to hold it through `moodle.postConfigureCommands`: a site in maintenance
> mode answers 503, the startup probe wants 200, and the rollout never completes.
>
> Keep users out from outside Moodle instead: install with `ingress.enabled: false`, verify through
> the Service, then `helm upgrade` with the ingress on as the switch-over.

### 2. Record your current deployment details

Save your current Helm values and release information for reference:

```bash
helm get values moodle -n <namespace> -o yaml > bitnami-moodle-values-backup.yaml
helm list -n <namespace> | grep moodle
```

`helm uninstall` in step 4 also deletes the Bitnami-generated `<release>` secret holding the admin
password. Copy it out now, step 8 needs it, and the account it belongs to is your only way back in:

```bash
kubectl get secret -n <namespace> moodle -o jsonpath='{.data.moodle-password}' | base64 -d > /dev/shm/moodle-admin-password
kubectl create secret generic moodle-admin -n <namespace> \
  --from-file=admin-password=/dev/shm/moodle-admin-password
shred -u /dev/shm/moodle-admin-password
```

Note the Bitnami PVC name and its associated PV:

```bash
PVC_NAME=$(kubectl get pvc -n <namespace> -l app.kubernetes.io/name=moodle -o jsonpath='{.items[0].metadata.name}')
PV_NAME=$(kubectl get pvc -n <namespace> "$PVC_NAME" -o jsonpath='{.spec.volumeName}')
PVC_SIZE=$(kubectl get pvc -n <namespace> "$PVC_NAME" -o jsonpath='{.status.capacity.storage}')
PVC_CLASS=$(kubectl get pvc -n <namespace> "$PVC_NAME" -o jsonpath='{.spec.storageClassName}')
PVC_MODES=$(kubectl get pvc -n <namespace> "$PVC_NAME" -o jsonpath='{range .spec.accessModes[*]}    - {@}{"\n"}{end}')
echo "PVC:   $PVC_NAME"
echo "PV:    $PV_NAME"
echo "size:  $PVC_SIZE  class: $PVC_CLASS"
echo "modes:"; echo "$PVC_MODES"
```

The PVC is typically named `<release>-moodle` (e.g. `moodle-moodle`). Record all five: step 5 rebuilds the claim from the size, the class and the access modes, `helm uninstall` in step 4 deletes the original, and a claim rebuilt with the wrong access mode still binds.

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

> **Important:** `Retain` outlives the namespace. A PV left this way is never reclaimed, not when
> the PVC is deleted, not when the namespace is deleted, and the storage behind it is billed until
> somebody notices. Step 14 puts the policy back once the migration has been accepted.

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

Create a new PVC bound to the retained PV, from the size, class and access modes recorded in step 2. A `ReadWriteMany` claim rebuilt as `ReadWriteOnce` binds to the same volume and reports `Bound`, and the downgrade surfaces only later, as a site that cannot be scaled past one pod:

```bash
cat <<EOF | kubectl apply -n <namespace> -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: moodle-data
spec:
  accessModes:
$PVC_MODES
  resources:
    requests:
      storage: $PVC_SIZE
  storageClassName: $PVC_CLASS
  volumeName: $PV_NAME
EOF
```

Verify the new PVC is bound:

```bash
kubectl get pvc -n <namespace> moodle-data
# Should show STATUS: Bound
```

### 6. Fix file ownership and remove maintenance mode file

The two images run as different users, so the SEI pod cannot write a `moodledata` it does not own. Read the ownership off the volume rather than trusting a number: chart 27.x runs as UID 1001, but a values file that disables the security contexts leaves Bitnami's Apache serving as UID 1 (`daemon`).

```bash
kubectl exec -n <namespace> "$MOODLE_POD" -- ls -n /bitnami/moodledata | head -3
```

The maintenance marker `climaintenance.html` lives on `moodledata`, so it survives the migration and would keep the new site returning 503. Remove it in the same pass.

Run a temporary pod to fix ownership and remove the marker. Nothing else may hold the volume, so do this after step 4 and before step 10:

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

**Important:**

- Chown every subPath the new pod will mount, not just `moodledata`; anything you re-mount through `extraVolumeMounts` keeps its Bitnami-era owner
- Make this the last thing that touches the volume. Running Moodle CLI as root re-creates `moodledata` directories owned by root, and the web user can no longer write them

### 7. Update database paths

Moodle stores absolute file paths in its settings, and they point into a filesystem the new image does not have. Sweep the whole database rather than one table, because a plugin may have written its own:

```bash
cat <<'SQL' | kubectl exec -i -n <namespace> <postgresql-pod> -- \
  sh -c "PGPASSWORD='<password>' psql -U <user> -d <database> -f -"
DO $$
DECLARE r record; n bigint;
BEGIN
  FOR r IN
    SELECT c.table_name, c.column_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_name = c.table_name AND t.table_schema = c.table_schema
    WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE'
      AND c.data_type IN ('character varying', 'text', 'character')
  LOOP
    EXECUTE format('SELECT count(*) FROM %I WHERE %I LIKE ''%%/bitnami%%''',
                   r.table_name, r.column_name) INTO n;
    IF n > 0 THEN RAISE NOTICE 'HIT %.% : % rows', r.table_name, r.column_name, n; END IF;
  END LOOP;
END $$;
SQL
```

Expect hits in `mdl_config.value`, `mdl_config_log.value` and `mdl_task_log.output`. The last two are history and must be left alone; only the live setting tables are rewritten. Read each hit before rewriting it.

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

A rewritten path is not a working one. Bitnami shipped helper binaries the Alpine image does not, so settings like `pathtogs` and `pathtounoconv` survive pointing at nothing. Check them after step 10 and clear any that no longer resolve; the feature that used the binary stops working.

Clear them from the command line, not the settings page: the chart's `config.php` sets `$CFG->preventexecpath = true`, which makes those settings read-only in the admin UI.

```bash
NEW_POD=$(kubectl get pods -n <namespace> -l app.kubernetes.io/name=moodle -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n <namespace> "$NEW_POD" -- php -r 'define("CLI_SCRIPT",true); require("/var/www/html/config.php");
  foreach (["pathtogs","pathtounoconv","pathtodot","pathtodu","pathtophp","pathtopython","pathtosassc",
            "pathtopdftoppm","pathtoffmpeg","aspellpath","geoip2file"] as $k) {
    $v = get_config(null, $k);
    if ($v !== false && $v !== "") { printf("%-14s %-28s exists=%s\n", $k, $v, var_export(file_exists($v), true)); }
  }'
```
### 8. Prepare the SEI chart values file

Create a values file for the SEI Moodle chart. The key settings to configure are:

- **Database**: Point to the same PostgreSQL instance and database used by the Bitnami deployment.
- **Persistence**: Reference the new PVC created in step 5 with `subPath: moodledata` so the SEI chart mounts only the moodledata subdirectory.
- **Site URL**: Must match the original `wwwroot` from the Bitnami deployment. Do not take it out of
  the old `config.php` without reading what is there. With `MOODLE_HOST` unset Bitnami writes
  `$CFG->wwwroot = 'https://' . $_SERVER['HTTP_HOST'];`, so the old site answered on *every*
  hostname that reached it and the file tells you nothing; with `MOODLE_HOST` set it writes that one
  name as a literal, which tells you only the name somebody configured. `get_config()` will not help either;
  from the CLI it resolves to Bitnami's own `127.0.0.1:8080` fallback. Take the hostname from the
  Bitnami `Ingress` (`kubectl get ingress -n <namespace>`), and take **all** of them: the SEI chart
  pins one `wwwroot`, and every other name the site used starts 303-ing to it the moment you cut
  over. Anything that still needs to answer on a second name needs `ingress.extraHosts` and a
  redirect you have decided on deliberately.
- **Table prefix**: Must match the prefix used by the existing database (default is `mdl_`).
- **Admin identity**: `username`, `email` and the password behind `existingSecret` must all be the
  ones your existing primary site admin already has. See the warning below.
- **Plugins**: one entry per component listed by the inventory in *Before migrating*.
- **Update strategy**: `Recreate`, because the claim inherited from Bitnami is `ReadWriteOnce`.
- **Access mode**: `persistence.moodledata.accessMode`, set to the mode of the claim you rebuilt in step 5. Helm cannot read it off the cluster, and it is the only thing that makes a later `replicaCount: 2` fail at render time instead of scheduling a second pod against a volume that cannot carry it.
- **Read-only dirroot**: `readOnlyDirroot.enabled: true`, the mode most migrations should land on and the mode the values below set. Everything under the heading `Migrating onto a read-only dirroot` applies from here on, and leaving the key out lands the site on the container layer instead.

```yaml
image:
  repository: erseco/alpine-moodle
  tag: v5.2.2 # First boot upgrades the existing Moodle 5.0.2 database
  pullPolicy: IfNotPresent

## The inherited claim is ReadWriteOnce: never run two pods against it
updateStrategy:
  type: Recreate

## The chart owns dirroot and the web process never writes to it
readOnlyDirroot:
  enabled: true
  volume: {}

moodle:
  ## Keep scheduled tasks off until the upgraded site has been verified.
  cron:
    enabled: false

  ## Run admin/cli/upgrade.php so the database follows image.tag.
  autoUpdateMoodle: true

  admin:
    ## All three are written over the existing admin account on every boot. See below
    username: "<your-admin-username>"
    email: "<your-admin-email>"
    existingSecret: "moodle-admin" # the secret copied out in step 2
    existingSecretKey: "admin-password"

  site:
    url: "https://your-moodle-domain.com" # Must match your current wwwroot
    ## Ignored on a migrated site. The chart refuses whitespace here only while
    ## readOnlyDirroot.enabled is false, so with a read-only dirroot a space renders and still changes nothing.
    ## Set the site name with a site admin preset: see moodle.preset in the README.
    name: "Moodle"

  proxy:
    sslProxy: true # Set to true if behind an SSL-terminating proxy

  ## One Moodle 5.2-compatible release per non-standard component from the inventory.
  ## A migrated database already carries the plugin's rows, settings and installed
  ## version; this restores compatible code to disk. Every entry is fetched again
  ## on every pod start, and a pod that cannot reach the source does not serve.
  plugins:
    - name: mod_customcert
      version: <moodle-5.2-compatible-version>
    - name: local_yourplugin
      url: https://plugins.example.org/local_yourplugin_<version>.zip
      version: <moodle-5.2-compatible-version>

  ## The image rewrites the mail settings, enableblogs, debug and the exec paths on every
  ## boot from its own environment defaults. Add the moodle.smtp, moodle.mail and
  ## moodle.config blocks set out after this file, or the first boot replaces your values.

  database:
    type: "pgsql"
    host: "<postgresql-host>"
    port: "5432"
    name: "<database-name>"
    user: "<database-user>"
    prefix: "mdl_"
    existingSecret: "<your-db-secret>"
    ## The key inside the secret, whatever it is called. A Bitnami externalDatabase secret
    ## holds the PostgreSQL password under `mariadb-password`, for historical reasons.
    existingSecretPasswordKey: "postgres-password"
    create_database: false # Database already exists

## Reuse the retained PV via the new PVC — mount only the moodledata subdirectory
persistence:
  moodledata:
    enabled: true
    type: persistentVolumeClaim
    existingClaim: "moodle-data"
    accessMode: ReadWriteOnce
    subPath: "moodledata"
    mountPath: /var/www/moodledata

## Any other subPath of the same claim the old deployment mounted. The volume is already
## there under the name of its persistence key, so re-mount it rather than declaring a
## second one. Chown these in step 6 as well.
# extraVolumeMounts:
#   - name: moodledata
#     mountPath: /opt/your-org/custom-scripts
#     subPath: "your-scripts-dir"

## Configure ingress to match your current setup, but keep it disabled until step 11 passes

ingress:
  enabled: false
  className: "nginx"
  hostname: "your-moodle-domain.com"
  path: /
  pathType: Prefix
  tls:
    - hosts:
        - your-moodle-domain.com
      secretName: your-tls-secret
```

**Important:**

- Set `create_database: false`; the database already exists with data from the Bitnami deployment
- Set either `moodle.database.password` or `moodle.database.existingSecret`; neither has a default and the chart refuses to render without one
- The chart names its generated admin secret `<fullname>-admin`, which on a release called `moodle` is the name Bitnami's own secret often holds. Helm refuses to adopt a secret it does not own, so point the chart at the existing one and set its key (Bitnami uses `moodle-password`, this chart defaults to `admin-password`)
- The admin values overwrite the existing account rather than describing it. On every boot the image rewrites the first `$CFG->siteadmins` account's username, email and password in place, so a wrong username renames your administrator
- The image also rewrites `pathtophp`, `pathtodu`, `enableblogs`, the `smtp*` settings, `noreplyaddress` and `emailsubjectprefix` on every boot from its own defaults. Read them off the Bitnami site first and restate them through `moodle.config` and `moodle.mail`, which the chart applies afterwards

```yaml
moodle:
  admin:
    existingSecret: "moodle-admin"
    existingSecretKey: "moodle-password"
```

### 9. Add the SEI Helm repository

If you have not already added the SEI Helm repository:

```bash
helm repo add sei https://cmu-sei.github.io/helm-charts
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

The SEI image will detect the existing Moodle database tables, skip the initial installation, generate a new `config.php`, and run `admin/cli/upgrade.php` to upgrade the schema from Moodle 5.0.2 to 5.2.2. Wait until the pod reaches `Running` and `1/1 Ready`. Once this upgrade starts, rollback requires restoring the pre-migration database backup; Moodle does not support schema downgrades.

> **If this CrashLoops, look for a stranded maintenance file before you retry.** The image's
> If an upgrade aborts partway, `climaintenance.html` is left on the shared `moodledata` and every
> later pod serves 503 to every visitor. Remove it as in step 6:
> `rm -f /var/www/moodledata/climaintenance.html`, from inside the pod once it boots or from a
> helper pod mounting the claim. A run that succeeds clears it itself.

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

# Every third-party plugin is back on disk. Compare against the inventory you took
# in "Before migrating"; --show-missing must print nothing.
kubectl exec -n <namespace> "$NEW_POD" -- \
  php /var/www/html/admin/cli/uninstall_plugins.php --show-contrib
kubectl exec -n <namespace> "$NEW_POD" -- \
  php /var/www/html/admin/cli/uninstall_plugins.php --show-missing

# The schema survived the version jump
kubectl exec -n <namespace> "$NEW_POD" -- \
  php /var/www/html/admin/cli/check_database_schema.php
```

Confirm that:

- The `config.php` shows `dataroot` as `/var/www/moodledata`
- The `moodledata` directory contains your existing data (`filedir/`, `cache/`, `lang/`, etc.)
- Every component from the inventory prints a `rootdir` and `versiondisk == versiondb`. A component
  that prints `MISSING FROM DISK` is installed in the database with no code behind it: add it to
  `moodle.plugins` and upgrade the release before you let anybody in. Diff this output against the
  file you saved before migrating rather than reading it, because the two are often
  identical across all 46 components, subplugins included, and a diff says so in one line.

Because this migration crosses from Moodle 5.0.2 to 5.2.2, confirm that the database upgrade landed cleanly:

```bash
kubectl exec -n <namespace> "$NEW_POD" -- \
  php /var/www/html/admin/cli/check_database_schema.php
# Expected: Database structure is ok.
```

Anything else is a schema the target version does not recognise. Restore the database backup before retrying; do not start Moodle 5.0.2 against a partly upgraded database.

Then measure the site rather than the kubelet. A probe that reaches the pod by IP proves nothing:
Moodle answers it with a 303 to `$CFG->wwwroot`, and `wget -q` prints an empty body either way, so
a broken site and a healthy one look identical. Ask for a real page with the real `Host`:

```bash
kubectl run curl --rm -it -n <namespace> --image=curlimages/curl --restart=Never -- \
  -s -o /dev/null -w '%{http_code}\n' -H "Host: your-moodle-domain.com" \
  http://moodle:8080/login/index.php
# Expected: 200
```

With `readOnlyDirroot.enabled: true`, also confirm the tree really is read-only rather than merely
owned by somebody else: a permission error is not the same thing, and can be undone by a `chmod`:

```bash
kubectl exec -n <namespace> "$NEW_POD" -- sh -c "grep ' /var/www/html ' /proc/mounts"
# Expected: ... /var/www/html ext4 ro,...
kubectl exec -n <namespace> "$NEW_POD" -- sh -c "touch /var/www/html/probe"
# Expected: Read-only file system
```

After these checks pass, enable ingress and scheduled tasks in `sei-moodle-values.yaml`:

```yaml
moodle:
  cron:
    enabled: true

ingress:
  enabled: true
```

Apply the updated file:

```bash
helm upgrade moodle sei/moodle -n <namespace> -f sei-moodle-values.yaml
```

Finish by logging in as a real, non-admin user from your old site and opening a course with an
uploaded file in it. That single click exercises the database, `filedir` under the new `dataroot`,
the file permissions from step 6 and the ingress at once. It is usually the
check that would have caught every failure listed in this guide.

### 12. Purge Moodle caches

After migration, purge Moodle's caches to clear any stale references:

```bash
kubectl exec -n <namespace> "$NEW_POD" -- php /var/www/html/admin/cli/purge_caches.php
```

### 13. Clean up (optional, after step 11 passes)

The PV still holds the old Moodle code in the `moodle/` subdirectory, which the SEI chart does not use. Clear the Bitnami-era `localcache/` here too: at one pod the chart leaves it in place and Moodle will use it, and above one pod a per-pod `emptyDir` hides rather than removes it:

```bash
kubectl run cleanup -n <namespace> --rm -it \
  --image=alpine:latest \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "cleanup",
        "image": "alpine:latest",
        "command": ["sh", "-c", "rm -rf /mnt/data/moodle /mnt/data/moodledata/localcache/* && echo Cleaned up old Moodle code"],
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

> **This step closes the rollback door.** The procedure below re-installs Bitnami with
> `moodleSkipInstall=true`, which means the image will not re-populate `/bitnami/moodle`, it
> expects to find the code you have just deleted. Do not run step 13 until you are prepared to roll
> back by restoring from the backups instead.

### 14. Return the PV reclaim policy

Once the migration has been accepted and the rollback window has closed, undo step 3. A PV left on
`Retain` is never reclaimed by anything, so deleting the PVC, or the whole namespace, silently
strands the volume and the storage behind it.

```bash
kubectl patch pv "$PV_NAME" -p '{"spec":{"persistentVolumeReclaimPolicy":"Delete"}}'
kubectl get pv "$PV_NAME" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}{"\n"}'
# Expected: Delete
```

## Rollback

This path only exists while `moodle/` is still on the PVC, i.e. before step 13. Once that directory
is gone, `moodleSkipInstall=true` leaves Bitnami with an empty dirroot and the only way back is
*Restoring from backup* below.

If the migration fails and you need to restore the Bitnami deployment, restore the pre-migration database before starting Moodle 5.0.2. Reinstalling the old image against a Moodle 5.2 database is not a rollback.

1. Uninstall the SEI release:

   ```bash
   helm uninstall moodle -n <namespace>
   ```

2. Restore file ownership for the Bitnami image. Use the uid and gid you read off the volume in
   step 6, `1001:0` on chart 27.x, `1:1` on charts old enough to have run as `daemon`, not a
   number copied from here:

   ```bash
   kubectl run fix-permissions -n <namespace> --rm -it \
     --image=alpine:latest \
     --overrides='{
       "spec": {
         "containers": [{
           "name": "fix-permissions",
           "image": "alpine:latest",
           "command": ["sh", "-c", "chown -R 1001:0 /mnt/data/moodledata && echo Done"],
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

3. Restore `moodle_db_backup.dump.gz` using step 2 under *Restoring from backup* below. This restores both the Moodle 5.0.2 schema and the original `/bitnami/moodledata` path settings.

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

The backup's members are `moodledata/...`, and `/var/www/moodledata` is a mount point, it cannot be
renamed or replaced from inside the pod. Extract *through* it instead, stripping the leading
directory so the members land inside the mount:

```bash
NEW_POD=$(kubectl get pods -n <namespace> -l app.kubernetes.io/name=moodle -o jsonpath='{.items[0].metadata.name}')

gunzip -c moodle_moodledata_backup.tar.gz | \
  kubectl exec -i -n <namespace> "$NEW_POD" -- \
  tar -C /var/www/moodledata --strip-components=1 -xf -
```

The extraction merges over what the fresh install created; it does not empty the directory first, so
anything the backup no longer contains stays behind. Verify what arrived, and check that the
maintenance marker did not come with it:

```bash
kubectl exec -n <namespace> "$NEW_POD" -- ls -la /var/www/moodledata/
kubectl exec -n <namespace> "$NEW_POD" -- rm -f /var/www/moodledata/climaintenance.html
```

Files land owned by the pod's own uid, so no `chown` step is needed on this path: the ownership
problem in step 6 only exists when the volume is carried across, not when the bytes are.

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
- [SEI Moodle Helm Chart](https://cmu-sei.github.io/helm-charts)
- [Bitnami Legacy Notice](https://community.broadcom.com/blogs/beltran-rueda-borrego/2025/08/18/how-to-prepare-for-the-bitnami-changes-coming-soon)
- [Moodle 5.2 release requirements](https://moodledev.io/general/releases/5.2)
