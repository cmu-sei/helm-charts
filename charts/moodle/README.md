# Moodle Helm Chart

[Moodle](https://moodle.org/) is a learning platform designed to provide educators, administrators and learners with a single robust, secure and integrated system to create personalized learning environments.

This Helm chart deploys Moodle using the lightweight [Alpine Linux based Moodle image](https://github.com/erseco/alpine-moodle).

## Migrating from Bitnami Moodle

If you are currently using the Bitnami Moodle Helm chart and want to migrate to this chart, see [migrate.md](migrate.md) for a step-by-step guide. The migration reuses your existing database and moodledata storage with minimal downtime.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL or MariaDB/MySQL database (Moodle 5.2 requires PostgreSQL 16+)
- Persistent storage (recommended for production deployments)

## Installation

```bash
helm repo add sei https://cmu-sei.github.io/helm-charts
helm install moodle sei/moodle -f values.yaml
```

## Deployment Topologies

The chart runs as either a single instance or a highly available multi-replica deployment, and **defaults to a single instance** (`replicaCount: 1`).

**Single instance** — the defaults are sufficient. Provide a database and a site URL and you are done:

```yaml
replicaCount: 1
moodle:
  site:
    url: "https://moodle.example.com" # https, or terminate TLS in front and set proxy.sslProxy
  database:
    existingSecret: "moodle-db" # or moodle.database.password for dev
```

`moodle.redis.host` may stay empty (file-based sessions are fine on one pod), `persistence.moodledata` may stay `emptyDir` (or use a `ReadWriteOnce` PVC to keep uploads), and `readOnlyDirroot` may stay disabled.

**High availability** — set `replicaCount > 1` (or enable `autoscaling`), then satisfy the shared-state requirements: a `moodle.redis.host`, a `ReadWriteMany` `moodledata` volume, and a per-pod code tree (the default already is per-pod). See [Scaling Configuration](#scaling-configuration). The chart's validation refuses a multi-replica release that is missing any of these rather than letting it come up broken.

Both topologies use the same defaults elsewhere (`updateStrategy: Recreate`, in-pod `cron`, `autoUpdateMoodle`); the [values.yaml](values.yaml) comments note where a setting behaves differently at one pod versus many.

## Moodle Configuration

The following settings configure the Moodle application via environment variables. Most settings correspond to the [alpine-moodle image configuration](https://github.com/erseco/alpine-moodle#configuration).

### Administrator Account

| Setting                          | Description                                    | Default                  |
| -------------------------------- | ---------------------------------------------- | ------------------------ |
| `moodle.admin.username`          | Initial admin username                         | `moodle-local-admin`             |
| `moodle.admin.email`             | Admin email address                            | `moodle-local-admin@example.com` |
| `moodle.admin.password`          | Admin password (leave empty to auto-generate)  | `""` (auto-generated)            |
| `moodle.admin.existingSecret`    | Use existing secret for admin password         | `""` (auto-generated)            |
| `moodle.admin.existingSecretKey` | Key in existing secret containing the password | `admin-password`                 |

**Important:**

- If `moodle.admin.password` is empty (default) and no `existingSecret` is provided, a random password is generated into a Secret named `<release>-moodle-admin`
- These settings are a write, not a description. On every boot the image overwrites the first `$CFG->siteadmins` account's username, password and email in place, and creates nothing
- Point `moodle.admin.username` at the account that already exists before using a database the chart did not create, or that account is renamed in place
- Changes made in the Moodle interface revert on the next pod restart
- For production, create the secret manually before deployment or leave the default configuration to auto-generate credentials

### Site Configuration

| Setting                | Description                            | Example                      |
| ---------------------- | -------------------------------------- | ---------------------------- |
| `moodle.site.url`      | Full URL where Moodle will be accessed | `https://moodle.example.com` |
| `moodle.site.name`     | Site name displayed in Moodle          | `Moodle` (default)           |
| `moodle.site.language` | Default site language                  | `en` (default)               |

**Important:**

- `moodle.site.url` must match your actual domain or ingress hostname. Moodle uses this for generating links and redirects.

### Proxy Configuration

Configure proxy settings when Moodle is behind a reverse proxy or load balancer.

| Setting                     | Description                  | Example           |
| --------------------------- | ---------------------------- | ----------------- |
| `moodle.proxy.reverseProxy` | Enable reverse proxy support | `false` (default) |
| `moodle.proxy.sslProxy`     | Trust SSL headers from proxy | `true` (default)  |

**Note:** Enable `sslProxy` if SSL/TLS is terminated at the load balancer or ingress controller.

**Important:** `sslProxy: true` with an `http://` `moodle.site.url` is refused at render time.

### Database Configuration

Configure an external database. This chart will not deploy a database server, one must already exist.

| Setting                             | Description                                                                  | Default                  |
| ----------------------------------- | ---------------------------------------------------------------------------- | ------------------------ |
| `moodle.database.type`              | Database type (`pgsql`, `mysqli`, or `mariadb`)                              | `pgsql`                  |
| `moodle.database.host`              | Database hostname                                                            | `pg-postgresql`          |
| `moodle.database.port`              | Database port                                                                | `5432`                   |
| `moodle.database.name`              | Database name                                                                | `moodledb`               |
| `moodle.database.user`              | Database username                                                            | `moodle`                 |
| `moodle.database.prefix`            | Table prefix (do not use numeric values)                                     | `mdl_`                   |
| `moodle.database.password`          | Database password (leave empty if using existingSecret)                      | `""`                     |
| `moodle.database.existingSecret`            | Secret containing database credentials                                       | `""`                     |
| `moodle.database.existingSecretUserKey`     | Key in that secret containing the username                                   | `""` (uses `user`)       |
| `moodle.database.existingSecretPasswordKey` | Key in that secret containing the password                                   | `postgres-password`      |
| `moodle.database.create_database`   | Automatically create database if it doesn't exist (runs as a Kubernetes Job) | `true`                   |

**Important:**

- Set either `moodle.database.password` or `moodle.database.existingSecret`; neither has a default, and the chart refuses to render without one
- There is no `existingSecretKey` here; the two keys are `existingSecretUserKey` and `existingSecretPasswordKey`, and naming a key the secret does not carry leaves the pod in `CreateContainerConfigError`
- `moodle.database.existingSecretUserKey` is optional. Left empty, the username comes from `moodle.database.user`
- The chart never writes `sslmode`. Set `DB_SSLMODE` through `extraEnvVars` to reach `$CFG->dboptions['ssl']`, which works only with `readOnlyDirroot.enabled: true`, where the chart owns `config.php`. With the switch off the image owns `config.php` and there is no route to it at all
- The `create_database` Job runs `postgres:16-alpine` from Docker Hub and honours `imagePullSecrets`, but not `image.registry`
- Database credentials must be provided via `existingSecret` or `password` field (required for deployment)
- When `moodle.database.create_database` is `true` (default), the chart deploys a Kubernetes Job that:
  - Waits for PostgreSQL to be ready using `pg_isready`
  - Creates the database only if it doesn't exist (idempotent)
- If `moodle.database.create_database` is `false`, you must manually create the database before deploying
- Ensure database character set is UTF-8

**Example PostgreSQL Database Setup:**

If using the option `moodle.database.create_database`, the Moodle database will be created automatically if it does not already exist. If you choose, you can manually configure the Moodle database before deploying Moodle.

```sql
CREATE DATABASE moodledb WITH ENCODING 'UTF8';
CREATE USER moodle WITH PASSWORD 'your-password';
GRANT ALL PRIVILEGES ON DATABASE moodledb TO moodle;
```

### PHP and Upload Configuration

| Setting                        | Description                  | Default |
| ------------------------------ | ---------------------------- | ------- |
| `moodle.php.postMaxSize`       | Maximum POST data size       | `50M`   |
| `moodle.php.uploadMaxFilesize` | Maximum file upload size     | `50M`   |
| `moodle.php.clientMaxBodySize` | Nginx client body size limit | `50M`   |
| `moodle.php.maxInputVars`      | Maximum input variables      | `5000`  |

**Note:** Increase these values if users need to upload large course files or assignments. The defaults are suitable for most standard Moodle deployments.

### SMTP Configuration (Optional)

Configure email sending via SMTP. `moodle.smtp.host` is required if any other SMTP setting is set; `moodle.smtp.user` is required if a password is set.

| Setting                         | Description                                         | Default               | Recommended Value           |
| ------------------------------- | --------------------------------------------------- | --------------------- | --------------------------- |
| `moodle.smtp.host`              | SMTP server hostname                                | `""` (not configured) | e.g., `smtp.gmail.com`      |
| `moodle.smtp.port`              | SMTP port                                           | `""` (not configured) | `587` (TLS standard)        |
| `moodle.smtp.user`              | SMTP username                                       | `""` (not configured) | Your SMTP username          |
| `moodle.smtp.password`          | SMTP password (leave empty if using existingSecret) | `""`                  | -                           |
| `moodle.smtp.existingSecret`    | Secret containing SMTP password                     | `""` (not configured) | `crucible-moodle-secret`    |
| `moodle.smtp.existingSecretKey` | Key in secret                                       | `password`            | -                           |
| `moodle.smtp.protocol`          | SMTP protocol (`tls` or `ssl`)                      | `""` (not configured) | `tls`                       |
| `moodle.mail.noreplyAddress`    | No-reply email address                              | `""` (not configured) | e.g., `noreply@example.com` |
| `moodle.mail.prefix`            | Email subject prefix                                | `""` (not configured) | -                           |

**Important Notes:**

- SMTP is **disabled by default**. Email functionality will only work once a relay is configured
- Setting any SMTP value requires `host`; setting `password` or `existingSecret` also requires `user`
- The image rewrites `smtphosts`, `smtpuser`, `smtppass`, `smtpsecure`, `noreplyaddress` and `emailsubjectprefix` on every boot from these values, blanking whatever the database held. A migrated site must restate its mail settings here or lose them
- Recommended: Use `existingSecret` for the SMTP password in production instead of `password`
- Standard SMTP configuration uses TLS on port 587

### Redis Configuration (Optional)

Configure Redis for session storage. Required for multi-replica deployments.

| Setting             | Description           | Default               | Recommended Value           |
| ------------------- | --------------------- | --------------------- | --------------------------- |
| `moodle.redis.host` | Redis server hostname | `""` (not configured) | Your Redis service hostname |
| `moodle.redis.port` | Redis port            | `""` (not configured) | `6379` (standard)           |

**Important:**

- Redis is **disabled by default** and only required for multi-replica deployments to share sessions across pods
- If `moodle.redis.host` is not configured, Redis session storage will be disabled
- Standard Redis port is 6379

### OAuth2/OIDC Configuration (Optional)

Configure Moodle to use an OIDC-compliant identity provider (IdP) for OAuth2 authentication. Token and userinfo endpoints are automatically discovered from the provider's `.well-known/openid-configuration` document.

#### Settings

| Setting                                       | Description                                                                                     | Default                               |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------- |
| `moodle.oidc.enabled`                         | Enable OAuth2/OIDC authentication                                                               | `false`                               |
| `moodle.oidc.discoveryUrl`                    | OIDC discovery document URL (`.well-known/openid-configuration`)                                | `""`                                  |
| `moodle.oidc.clientId`                        | OAuth2 client ID registered with the provider                                                   | `""`                                  |
| `moodle.oidc.clientSecret`                    | Client secret (use `existingSecret` in production)                                              | `""`                                  |
| `moodle.oidc.existingSecret`                  | Kubernetes secret containing the client secret                                                  | `""`                                  |
| `moodle.oidc.existingSecretKey`               | Key in the secret                                                                               | `client-secret`                       |
| `moodle.oidc.name`                            | Provider display name on the Moodle login page                                                  | `""`                                  |
| `moodle.oidc.loginScopes`                     | OAuth2 scopes requested during login                                                            | `openid profile email`                |
| `moodle.oidc.loginScopesOffline`              | OAuth2 scopes requested for offline/refresh tokens                                              | `openid profile email offline_access` |
| `moodle.oidc.requireConfirmation`             | Require email confirmation before linking new OIDC accounts                                     | `false`                               |
| `moodle.oidc.showOnLoginPage`                 | Show provider button on the login page                                                          | `true`                                |
| `moodle.oidc.iconUrl`                         | URL for the provider logo shown on the login page (defaults to `<moodle-site-url>/pix/key.svg`, which is included in this chart) | `""`                                  |
| `moodle.oidc.userFieldMappings`               | Map OAuth2 claims to Moodle user fields (`"external:internal"`)                                 | `["sub:idnumber"]`                    |
| `moodle.oidc.disableCurlSecurityBlockedHosts` | Disable Moodle CURL security for internal provider communication                                | `true`                                |
| `moodle.oidc.waitTimeout`                     | Total time to wait for discovery endpoint (seconds)                                             | `300`                                 |
| `moodle.oidc.waitInterval`                    | Delay between readiness checks (seconds)                                                        | `5`                                   |
| `moodle.oidc.caCert.existingSecret`           | Secret containing a custom CA certificate                                                       | `""`                                  |
| `moodle.oidc.caCert.existingConfigMap`        | ConfigMap containing a custom CA certificate                                                    | `""`                                  |
| `moodle.oidc.caCert.key`                      | Key in the secret/configmap for the CA certificate                                              | `ca.crt`                              |
| `moodle.oidc.caCert.path`                     | Mount path inside the container for the CA certificate                                          | `/opt/sei/certs/oidc-ca.crt`          |

#### Example: Keycloak

```yaml
moodle:
  oidc:
    enabled: true
    discoveryUrl: "https://keycloak.example.com/realms/my-realm/.well-known/openid-configuration"
    clientId: "moodle-client"
    existingSecret: "moodle-oidc-secret"
    name: "Keycloak"
```

**Important:** the provider's discovery document must advertise `https` endpoints, or Moodle refuses the issuer. An in-cluster `http` discovery URL is fine (on Keycloak, set `KC_HOSTNAME`).

#### Storing the Client Secret

```bash
kubectl create secret generic moodle-oidc-secret \
  --from-literal=client-secret='your-client-secret-here'
```

Then reference it in values:

```yaml
moodle:
  oidc:
    existingSecret: "moodle-oidc-secret"
    existingSecretKey: "client-secret"
```

#### Mapping Claims to User Fields

`userFieldMappings` maps a claim from the provider to a Moodle user field, written `"claim:field"`. Moodle validates the target and rejects the mapping if the field does not exist.

These core fields are always available:

`firstname` `lastname` `email` `city` `country` `lang` `description` `idnumber` `institution` `department` `phone1` `phone2` `address` `firstnamephonetic` `lastnamephonetic` `middlename` `alternatename` `picture` `username`

Creating the provider also creates a default mapping for each standard OIDC claim the field list covers, so `given_name`, `family_name`, `email` and the rest are mapped without being declared. Declare a mapping only to add one, such as the default `sub:idnumber`.


#### Mapping Claims to Custom Profile Fields

A claim with no core field to map to needs a custom profile field, written `profile_field_<shortname>`:

```yaml
moodle:
  oidc:
    userFieldMappings:
      - "sub:idnumber"
      - "organization:profile_field_ssoorg"
```

**Important:** the field must exist before the mapping is applied. Moodle validates the mapping target against the fields that exist, so a mapping to a missing field is refused and the OIDC step fails.

Create it from `moodle.postConfigureCommands`, which runs after the provider is created and before the mappings are applied. Moodle ships no CLI for profile fields, so call `profile_save_field()` from `user/profile/definelib.php`.

#### Configuring a Keycloak Client

If using Keycloak as the provider, create a client in your Keycloak realm with the following settings:

**Basic Settings:**

- **Client ID**: must match `moodle.oidc.clientId`
- **Client type**: `openid-connect`
- **Enabled**: `true`

**Capability config:**

- **Client authentication**: `On` (confidential client)
- **Standard flow**: `On` (authorization code flow)
- **Service accounts**: `On`

**Access settings:**

- **Valid redirect URIs**: `https://your-moodle-domain.com/admin/oauth2callback.php`
- **Web origins**: `https://your-moodle-domain.com`

**Required Default Client Scopes:** `openid`, `profile`, `email`, `roles`

**Example Keycloak client export:**

```json
{
  "clientId": "moodle-client",
  "name": "Moodle",
  "enabled": true,
  "clientAuthenticatorType": "client-secret",
  "secret": "super-safe-secret",
  "redirectUris": ["https://crucible/admin/oauth2callback.php"],
  "webOrigins": ["https://crucible"],
  "standardFlowEnabled": true,
  "directAccessGrantsEnabled": true,
  "serviceAccountsEnabled": true,
  "publicClient": false,
  "protocol": "openid-connect",
  "defaultClientScopes": ["web-origins", "acr", "profile", "roles", "email"],
  "optionalClientScopes": [
    "address",
    "phone",
    "offline_access",
    "microprofile-jwt"
  ]
}
```

#### Verify Configuration

After deploying with OIDC integration enabled:

1. Navigate to your Moodle login page
2. You should see a "Log in with \<provider name\>" button
3. Click the button to test OAuth2 authentication
4. You should be redirected to the provider, then back to Moodle after successful authentication

**Troubleshooting:**

- If the OAuth2 button doesn't appear, check that `moodle.oidc.showOnLoginPage` is `true`
- If authentication fails, verify:
  - The discovery URL is reachable from Moodle pods (check `waitTimeout` if it times out)
  - The redirect URI matches exactly what is registered with the provider
  - The client secret is correct
  - The provider domain is accessible from both Moodle pods and user browsers
  - Moodle trusts the TLS certificate used by the provider (use `caCert` for custom CAs)

### Plugins and Site Settings

These are the keys through which a real deployment is expressed: the plugin trees it carries, the plugins it turns on, the settings it sets, and the two shell hooks around the image's own boot.

| Setting                         | Description                                                                       | Default |
| ------------------------------- | --------------------------------------------------------------------------------- | ------- |
| `moodle.plugins`                | Plugin source trees placed into dirroot before Moodle registers them               | `[]`    |
| `moodle.allowWebPluginInstall`  | Returns Moodle's plugin installer to Site administration; one pod, writable tree   | `false` |
| `moodle.enabledPlugins`         | Map of component to boolean, applied with each plugin type's own `enable_plugin()` | `{}`    |
| `moodle.preset.name`            | Site admin preset already on the site to apply: `starter`, `full`                  | `""`    |
| `moodle.preset.xml`             | Site admin preset XML itself, shipped in the release                               | `""`    |
| `moodle.preset.existingConfigMap` | ConfigMap you create holding that XML instead                                      | `""`  |
| `moodle.preset.key`             | Key within `moodle.preset.existingConfigMap`                                       | `preset.xml` |
| `moodle.config`                 | Map of component to settings, applied with `set_config()`; `core` is core          | `{}`    |
| `moodle.config.<c>.<s>`         | A value may be `{existingSecret, key}` instead of a literal, for a sensitive value | —       |
| `moodle.preConfigureCommands`   | Shell commands run before Moodle installation and upgrade                          | `""`    |
| `moodle.postConfigureCommands`  | Shell commands run after Moodle installation and upgrade                           | `""`    |
| `caBundle.existingConfigMap`    | ConfigMap mounted over `/etc/ssl/certs/ca-certificates.crt`; empty mounts nothing   | `""`    |
| `caBundle.existingSecret`       | Secret mounted over the same path                                                  | `""`    |
| `caBundle.key`                  | Key in that ConfigMap or Secret                                                    | `ca-certificates.crt` |

**Example:**

```yaml
moodle:
  plugins:
    - { name: mod_customcert, version: "2026042006" }
    - name: qtype_mojomatch
      url: https://example.org/moodle-plugins/qtype_mojomatch_2026060800.zip
      version: "2026060800"
  enabledPlugins:
    logstore_xapi: true
  config:
    core: { theme: boost_union, forcelogin: 1 }
    logstore_xapi:
      endpoint: "https://lrs.example.com/xapi"
      password: { existingSecret: lrs-creds, key: password }
```

A `moodle.config` value that is a map names a Secret rather than holding the value: the chart passes it to the container from that Secret, so it never appears in `values.yaml` or in any rendered manifest. Use it for an API key, token, password or any other sensitive value. It must carry exactly `existingSecret` and `key`.

| Field     | Effect                                                                      |
| --------- | --------------------------------------------------------------------------- |
| `name`    | Floats; resolved from the Moodle plugins directory at every pod start        |
| `url`     | Fetches from a URL you give instead of the Moodle plugins directory          |
| `version` | Pins the version and acts as a cache key; a tree already at it is left alone |

**Important:**

- `url` and `version` are not substitutes, so declare both when you set `url`; changing either re-fetches the plugin
- Plugins are re-fetched on every pod start unless the code tree is on a volume that outlives the pod: a named PVC at one replica, in either dirroot mode
- A version pin binds the parent plugin, never its subplugins
- `moodle.plugins` resolves no dependencies and never removes, so declare every plugin a declared plugin requires
- Removing an entry drops the code and leaves the database rows; finish with `uninstall_plugins.php`, never `--purge-missing`
- Both hooks run in the main container; under `readOnlyDirroot.enabled: true` they must not write to dirroot

**Plugin installation from the web interface is off by default:** the chart sets `$CFG->disableupdateautodeploy` and `$CFG->uninstallclionly`, so Site administration offers neither the plugin installer nor an uninstall button. Declare plugins in `moodle.plugins`, and uninstall with `php admin/cli/uninstall_plugins.php --plugins=<component> --run`.

`moodle.allowWebPluginInstall: true` returns the installer. It requires one pod and `readOnlyDirroot.enabled: false`, and the chart refuses both of the others: a read-only tree fails the install after the database rows are written, and a second pod leaves the other replicas reporting a plugin they have no code for. Uninstall stays CLI-only regardless, because it removes code and rows together and would contradict `moodle.plugins`. Unless a volume that outlives the pod is mounted at `/var/www/html`, a plugin installed this way is gone at the next pod start and its database rows remain.

**Site admin presets:** `moodle.preset` applies one of Moodle's own preset documents with `\core_adminpresets\helper::change_default_preset()`, the call Moodle's installer makes. Export one from Site administration > Site admin presets, or name a preset the site already carries. Set exactly one of `name`, `xml` or `existingConfigMap`.

A preset the site already holds, either one Moodle ships or one an admin saved from the interface:

```yaml
moodle:
  preset:
    name: starter
  config:
    core: { forcelogin: 1 }
```

An exported preset carried in the release, either written out in full:

```yaml
moodle:
  preset:
    xml: |
      <?xml version="1.0" encoding="UTF-8"?>
      <PRESET>...</PRESET>
```

or read from the exported file at install time:

```console
helm install moodle ./moodle --set-file moodle.preset.xml=./my-site.xml
```

or, for a file shipped inside the chart itself, from the values file alone:

```yaml
moodle:
  preset:
    xml: '{{ .Files.Get "files/site-preset.xml" }}'
```

A ConfigMap you create and keep outside the release, which the chart mounts and reads:

```console
kubectl create configmap my-site-preset --from-file=preset.xml=./my-site.xml
```

```yaml
moodle:
  preset:
    existingConfigMap: my-site-preset
    key: preset.xml
```

- The preset is the baseline: it runs before `moodle.enabledPlugins` and `moodle.config`, and both override it wherever they name the same setting
- It applies differentially, so a setting the preset never names is left alone, and re-applying changes nothing
- A setting whose plugin is not installed is discarded when the preset is read, so declare that plugin in `moodle.plugins`; the chart logs a warning naming each setting it had to ignore
- Presets carry plugin enablement as well as settings, in either direction
- `xml` travels in the release and goes with it; `existingConfigMap` is yours to create, outlives the release, and reaches the site on the next pod start when you change it
- `.Files.Get` reads only inside the chart directory and returns empty for any path outside it, which surfaces as `Preset file is not valid XML` at pod start; `--set-file` takes a path anywhere
- Export excludes passwords and keys by default, so a preset is never a complete site configuration
- Dropping a setting from the preset does not restore its default, exactly as with `moodle.config`

**Site content and other long scripts:** hold the script in a `configMaps` entry, mount it with `extraVolumes`/`extraVolumeMounts`, and run it from a one-line `moodle.postConfigureCommands`. Make it idempotent, because it runs on every boot.

### Advanced Settings

| Setting                   | Description                            | Example           |
| ------------------------- | -------------------------------------- | ----------------- |
| `moodle.autoUpdateMoodle` | Run `admin/cli/upgrade.php` at startup so the database follows `image.tag` | `true` (default) |
| `moodle.debug`            | Enable debug mode                      | `false` (default) |

**Important:**

- The image writes `pathtophp`, `pathtodu`, `enableblogs`, the `smtp*` settings, `noreplyaddress` and `emailsubjectprefix` on every boot, from its own defaults when you set nothing, so `smtphosts` becomes `smtp.gmail.com:587`. Set `moodle.smtp` or `moodle.config`, which the chart applies afterwards
- Every pod start with N declared plugins is N network fetches with no cache

**Important:** a failed upgrade leaves `climaintenance.html` in `moodledata`, and every pod then serves 503 while looking healthy. Delete the file to recover.

### Upgrading Moodle

An upgrade is a change to `image.tag`. The replacement pod starts on the new code tree and, with `moodle.autoUpdateMoodle` left on, runs `admin/cli/upgrade.php` against the existing database on its first boot.

**Important:**

- Moodle 5.1 moved the web root under `public/`; the chart reads that split from `image.tag`, so a direct 5.0 to 5.2 hop upgrades in one pass
- Above one replica the chart elects one pod to upgrade; the others join without touching the schema
- The default `updateStrategy.type` is `Recreate`, which stops the site for one pod start plus the schema upgrade
- `RollingUpdate` replaces that outage with an error window at every replica count, so take the site out of rotation yourself first
- Rolling `image.tag` backwards does not roll the database back. The chart refuses to boot a pod whose code is older than the version recorded in `moodledata`. Roll forward, or restore the database and start from an empty dirroot

## Helm Deployment Configuration

The following settings are specific to the Helm chart deployment and Kubernetes resources.

### Persistence Configuration

Configure storage for Moodle data directory (user uploads, course files, etc.).

**Note:** Moodle's node-local cache lives inside `moodledata` by default, which is Moodle's own default. Above one pod the chart mounts a per-pod `emptyDir` over it, because a shared local cache corrupts across pods. Set `persistence.localcache` to give it its own volume or change that volume's size.

#### Using EmptyDir (Testing Only)

**Important:** `emptyDir` is the shipped default, and it keeps nothing. Every uploaded file, course backup and cached asset is discarded when the pod is replaced, while the site stays `200` and `1/1 Ready` throughout. Any deployment that holds real data must set `type: persistentVolumeClaim`.

**Default Configuration:**

```yaml
persistence:
  moodledata:
    enabled: true
    type: emptyDir
    sizeLimit: "5Gi"
```

**Warning:** Data is lost when pod is deleted or restarted.

#### Using PersistentVolumeClaim (Recommended)

```yaml
persistence:
  moodledata:
    enabled: true
    type: persistentVolumeClaim
    existingClaim: "" # Leave empty or omit to create new PVC
    accessMode: ReadWriteMany # Required for multi-replica
    size: 20Gi
    storageClass: "efs-sc" # EFS, NFS, Azure Files, etc.
    retain: true # Keep PVC on helm uninstall
```

**Note:** Multi-replica deployments require `ReadWriteMany` access mode (EFS, NFS, Azure Files, etc.). You can either leave `existingClaim` as an empty string or omit it entirely to create a new PVC dynamically.

#### Using Existing PVC

```yaml
persistence:
  moodledata:
    enabled: true
    type: persistentVolumeClaim
    existingClaim: "my-moodle-data-pvc"
```

### Read-Only Dirroot Configuration

Enable read-only Moodle code directory for security and multi-replica support.

| Setting                       | Description                                                         | Default               |
| ----------------------------- | ------------------------------------------------------------------- | --------------------- |
| `readOnlyDirroot.enabled`     | The chart owns the code tree and the web process never writes to it  | `false`               |
| `readOnlyDirroot.volume`      | Kubernetes volume for the code tree; empty renders `emptyDir: {}`    | `{}`                  |
| `readOnlyDirroot.secret.name` | Secret containing config.php; empty auto-generates one holding no credentials | `""` (auto-generated) |
| `readOnlyDirroot.secret.key`  | Key in that secret                                                   | `config.php`          |

**Why enable read-only dirroot:**

1. **Security hardening**: the web process cannot modify application code at runtime
2. **Multi-replica safety**: every pod runs identical code, so nodes cannot drift out of sync
3. **Immutable infrastructure**: the tree comes from the image, making deployments predictable

Moodle recommends it, because built-in plugin installation otherwise takes cluster nodes out of sync. It is opt-in, and `false` is fully supported: the image then owns startup end to end, and the chart still places plugin trees and lets Moodle register them.

When enabled, an init container seeds the code volume from the image before the main container mounts it read-only. `config.php` is authored by the chart and seeded at mode 0444, so it is read-only too.

**Important:** `moodledata` must be shared and `dirroot` must not be, but only one of those is Moodle's rule:

- **Moodle's rule:** dataroot *"MUST be a shared directory where each cluster node is accessing the files directly"*. With more than one pod it must be `ReadWriteMany`.
- **The chart's rule:** dirroot is per pod. Moodle only *recommends* a local dirroot and permits a shared one, but the chart refuses every shape that would share it, because each pod seeds its own tree: three pods seeding one volume race on the same files and none of them ever start.

**Note:**

- `moodle.plugins` resolves no dependencies, so declare every plugin a declared plugin requires, and theirs in turn
- Removing an entry removes the code from the next fresh dirroot and leaves every database row in place
- Finish a removal with `admin/cli/uninstall_plugins.php --plugins=<component> --run`, never with `--purge-missing`

**⚠️ The two PVC options do not behave the same:**

- `ephemeral.volumeClaimTemplate` creates a claim **owned by the pod**. Kubernetes deletes it when the pod goes, so the code tree is rebuilt every time and every declared plugin is downloaded again.
- `persistentVolumeClaim` names a claim that **outlives pods**, so the tree survives a restart. It is a single volume, so the chart accepts it only with one pod and `updateStrategy.type: Recreate`.

**Example with EmptyDir:**

```yaml
readOnlyDirroot:
  enabled: true
  volume: {} # renders emptyDir: {}
```

**Example with a per-pod PVC:**

```yaml
readOnlyDirroot:
  enabled: true
  volume:
    ephemeral:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          storageClassName: gp3
          resources:
            requests:
              storage: 4Gi
```

**Example with a named PVC:** a named claim is a single volume, so the chart accepts it only with exactly one pod and `updateStrategy.type: Recreate`. Anything else would let a surge pod re-seed the tree the live pod is serving from.

```yaml
replicaCount: 1
updateStrategy:
  type: Recreate
readOnlyDirroot:
  enabled: true
  volume:
    persistentVolumeClaim:
      claimName: "moodle-code-pvc"
  secret:
    name: "moodle-config"
    key: "config.php"
```

**Custom code in a read-only code tree:**

With `readOnlyDirroot.enabled: true` the chart refuses `extraVolumeMounts` and `persistence.<name>` under `/var/www/html`, because a mount there hides every file the image ships beneath it. Three routes put your own code into the tree instead, each landing before it is mounted read-only:

1. **`moodle.plugins` with an explicit `url`**: the field accepts any URL, so an in-house zip is placed like any other declared plugin
2. **A custom image** built `FROM` the Moodle image, with your code copied into `/usr/src/moodle`
3. **An `initContainers` entry** mounting the `dirroot` volume at `/seed`; yours render after `seed-dirroot`

```yaml
moodle:
  plugins:
    - name: local_inhouse
      url: https://artefacts.internal.example.com/moodle/local_inhouse_2026042006.zip
      version: "2026042006"
```

**A code volume needs `volumePermissions`:**

Storage backends hand out a volume root owned by `root`, and `fsGroup` sets only the group. The chart's `volumePermissions` init container chowns it first, so this is handled by default whenever a volume is mounted over the code tree.

- Applies to block storage (EBS, PD) as much as to NFS
- Set `volumePermissions.enabled: false` only if the container already runs as root, or your storage presents a root owned by the container user

### Ingress Configuration

```yaml
ingress:
  enabled: true # Default
  className: "nginx"
  hostname: "moodle.example.com"
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "512m" # Default - match or exceed clientMaxBodySize
    # Optional: Add cert-manager annotation if using TLS with cert-manager
    # cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    - secretName: moodle-tls
      hosts:
        - moodle.example.com
```

**Important:**

- Set `proxy-body-size` to match or exceed `moodle.php.clientMaxBodySize` for large file uploads (default: 512m)
  - **Automatic Validation**: The chart will fail installation if `proxy-body-size` is smaller than `clientMaxBodySize`, preventing upload failures
- TLS/SSL configuration is optional - add cert-manager annotations only if you're using cert-manager for TLS certificates

### Resource Configuration

Configure resource requests and limits using presets or custom values.

**Default Configuration:**

The chart uses the `small` preset by default, which allocates:

- CPU Request: 250m, Limit: 500m
- Memory Request: 256Mi, Limit: 512Mi

This is suitable for development and small production deployments. Adjust based on your workload.

**Using Presets:**

```yaml
resourcesPreset: "small" # Default - Options: nano, micro, small, medium, large, xlarge, 2xlarge
```

| Preset    | CPU Request | Memory Request | CPU Limit | Memory Limit |
| --------- | ----------- | -------------- | --------- | ------------ |
| `nano`    | 50m         | 64Mi           | 100m      | 128Mi        |
| `micro`   | 100m        | 128Mi          | 200m      | 256Mi        |
| `small`   | 250m        | 256Mi          | 500m      | 512Mi        |
| `medium`  | 500m        | 512Mi          | 1000m     | 1Gi          |
| `large`   | 1000m       | 1Gi            | 2000m     | 2Gi          |
| `xlarge`  | 2000m       | 2Gi            | 4000m     | 4Gi          |
| `2xlarge` | 4000m       | 4Gi            | 8000m     | 8Gi          |

**Custom Resources:**

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
```

### Probes Configuration

Health check probes are enabled by default with sensible values.

| Setting                              | Default | Description                       |
| ------------------------------------ | ------- | --------------------------------- |
| `startupProbe.enabled`               | `true`  | Enable startup probe              |
| `startupProbe.failureThreshold`      | `120`   | Number of failures before restart |
| `livenessProbe.enabled`              | `true`  | Enable liveness probe             |
| `livenessProbe.initialDelaySeconds`  | `120`   | Delay before first check          |
| `readinessProbe.enabled`             | `true`  | Enable readiness probe            |
| `readinessProbe.initialDelaySeconds` | `30`    | Delay before first check          |

All probes use `/login/index.php` as the health check endpoint.

### Scaling Configuration

#### Horizontal Pod Autoscaling

Autoscaling is **disabled by default** since the default deployment uses a single replica.

```yaml
autoscaling:
  enabled: false # Default - set to true to enable
  minReplicas: 1
  maxReplicas: 10
  targetCPU: 80
  targetMemory: 80
```

**Important:** Multi-replica deployments require:

- Redis for session storage
- ReadWriteMany storage for moodledata
- A per-pod code tree. `readOnlyDirroot.enabled` is `false` by default, in which case each pod's
  dirroot is its own container layer and is already per-pod. Turning it on gives the same property
  through an explicit volume, mounted read only. Either way the chart refuses a code volume that
  more than one pod would share.

#### Pod Disruption Budget

Pod Disruption Budget is **disabled by default** since single-replica deployments don't benefit from PDB protection.

```yaml
pdb:
  create: false # Default - set to true for multi-replica deployments
  minAvailable: 1
```

**Note:** Enable PDB only when running 2 or more replicas to ensure availability during voluntary disruptions (node drains, cluster upgrades, etc.).

### Security Context

Configure pod and container security contexts. The chart uses secure defaults following Kubernetes security best practices.

**Default Configuration:**

```yaml
podSecurityContext:
  enabled: true
  fsGroupChangePolicy: Always
  sysctls: []
  supplementalGroups: []
  fsGroup: 65534 # nobody/nogroup
  runAsUser: 65534 # nobody user
  runAsGroup: 65534 # nogroup
  runAsNonRoot: true # runs as non-root user

containerSecurityContext:
  enabled: true
  seLinuxOptions: {}
  runAsUser: 65534 # nobody user
  runAsGroup: 65534 # nogroup
  runAsNonRoot: true # runs as non-root user
  privileged: false # no privileged mode
  readOnlyRootFilesystem: false # writable filesystem needed for Moodle
  allowPrivilegeEscalation: false # prevents privilege escalation
  capabilities:
    drop: ["ALL"] # drops all Linux capabilities
  seccompProfile:
    type: RuntimeDefault # uses runtime default seccomp profile
```

**Security Best Practices:**

- Runs as non-root user (UID 65534 - nobody) by default
- Uses dedicated group (GID 65534 - nogroup)
- Drops all Linux capabilities
- Prevents privilege escalation
- Uses seccomp runtime default profile
- Compatible with restricted Pod Security Standards
- FSGroup ownership changes applied to volumes

### Network Policy

Network policies provide network-level security by controlling pod-to-pod and external communication.

**Default Configuration:**

```yaml
networkPolicy:
  enabled: false # Disabled by default
  policyTypes:
    - Ingress
    - Egress
  allowExternal: true # Allow external ingress traffic
  allowExternalEgress: true # Allow all egress traffic
  databaseSelector: {} # No database pod selector
```

**Enabling Network Policies:**

```yaml
networkPolicy:
  enabled: true
  allowExternal: false # Restrict ingress to specific namespaces
  allowExternalEgress: false # Restrict egress to specific services
  databaseSelector:
    app: postgres # Allow egress to database pods
  ingressNSMatchLabels:
    name: ingress-nginx # Allow ingress from nginx namespace
```

**Important:** `allowExternalEgress: false` permits DNS and `moodle.database.port` and nothing else. Redis, SMTP, the OIDC discovery URL and every `moodle.plugins` download are dropped with no render-time warning. Add each one to `networkPolicy.extraEgress`.

**Note:** Network policies require a CNI plugin that supports NetworkPolicy (e.g., Calico, Cilium, Weave Net). The default configuration allows all traffic, making it suitable for testing and development environments. For production, enable and configure policies based on your security requirements.

## Troubleshooting

### Database Connection Issues

- Verify database is accessible from Moodle pods
- Check database credentials in secret
- Ensure database character set is UTF-8
- Verify network policies allow connection to database

### File Upload Issues

- Verify `moodle.php.uploadMaxFilesize` is sufficient
- Check ingress `proxy-body-size` annotation matches or exceeds `moodle.php.clientMaxBodySize`
  - The chart will automatically validate this and fail installation if misconfigured
  - If you see a validation error, update `ingress.annotations["nginx.ingress.kubernetes.io/proxy-body-size"]`
- Ensure moodledata volume has sufficient space
- Check permissions on moodledata directory (should be writable by user 65534)

### Multi-Replica Issues

- Verify Redis is configured and accessible
- Ensure moodledata uses ReadWriteMany storage
- Check that all pods can write to shared storage
- Verify read-only dirroot is configured if enabled
- Review pod logs for leader election messages
- One replica installs, the rest wait. If the installing replica fails, it writes `.moodle_install.failed` into `moodledata` and every replica then refuses to start, naming the file. That is deliberate: Moodle cannot recover a half finished install. Restore the database from backup, then delete the file so a replica may install again
- The heartbeat takeover recovers a leader that vanished before it touched the schema. It cannot recover one that was killed after: Moodle's own `upgraderunning` lock holds for 300 seconds and raising the chart's `STALE_AFTER` past it only yields `Config table does not contain the version.` Restore from backup instead

### Performance Issues

- Increase resource limits and requests
- Enable Redis for session storage
- Verify database performance and connection pooling
- Check if read-only dirroot is enabled for multi-replica

### Pod Crashes or Restarts

- Check resource limits are sufficient
- Verify startup probe timeout is adequate for Moodle initialization
- Check for database connection limits
- Review pod logs for errors
- Ensure persistent storage is properly mounted

### Read-Only Dirroot Issues

- Review the seed logs first with `kubectl logs <pod> -c seed-dirroot`. Every refusal it emits is prefixed `[ERROR]` and names the fix
- `The volume holds Moodle X and the image is Y` is a downgrade on a persistent dirroot volume. Moodle has no down-migration, so roll `image.tag` forward, or restore the database from backup and start from an empty volume
- `The chart rendered webRoot ... but the tree ...` means `image.tag` and the tree on the volume disagree about the 5.0/5.1 layout split, usually because the volume is stale
- Plugin failures name their component first. `unknown plugin type` means the type is neither in the tree's `lib/components.json` nor declared as a subplugin type by an installed plugin
- `[OVERRIDE] Drift:` in the main container means the image tried to write a setting the chart's `config.php` does not carry. It is a warning, not a failure
- For multi-replica, verify only one pod performs database installation (leader election)

## References

- [Moodle Documentation](https://docs.moodle.org/)
- [Alpine Moodle Image](https://github.com/erseco/alpine-moodle)
- [Moodle System Requirements](https://docs.moodle.org/en/Installing_Moodle#Requirements)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Helm Documentation](https://helm.sh/docs/)
