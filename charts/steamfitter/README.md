# Steamfitter Helm Chart

[Steamfitter](https://cmu-sei.github.io/crucible/steamfitter/) is the [Crucible](https://cmu-sei.github.io/crucible/) application that enables the organization and execution of scenario tasks on virtual machines.

Steamfitter manages scenario-based automation by:
- Organizing tasks into scenarios and sessions
- Scheduling task execution on VMs
- Executing VM operations through the Crucible [VM API](https://github.com/cmu-sei/vm.Api), and commands over SSH and email directly
- Coordinating with [Player](https://github.com/cmu-sei/Player.Api) for VM and team information

This Helm chart deploys Steamfitter with both [API](https://github.com/cmu-sei/steamfitter.api) and [UI](https://github.com/cmu-sei/steamfitter.ui) components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (e.g., [Keycloak](https://www.keycloak.org/)) for OAuth2/OIDC authentication
- Crucible [Player](https://github.com/cmu-sei/Player.Api) instance
- Crucible [VM API](https://github.com/cmu-sei/vm.Api) **3.8.11 or later**. Steamfitter API 3.10.0 executes all VM operations through the VM API, and the guest process, guest file, snapshot and Proxmox endpoints it depends on were introduced in VM API 3.8.11. The [player](../player/) chart ships a compatible version.
- An SMTP relay, if any scenario uses `send_email` tasks (see [Email Task Execution](#email-task-execution))
- An SSH private key, if any scenario uses `core_remote`, `linux_file_touch` or `linux_rm` tasks (see [SSH Task Execution](#ssh-task-execution))

## Installation

```bash
helm repo add sei https://cmu-sei.github.io/helm-charts
helm install steamfitter sei/steamfitter -f values.yaml
```

## Upgrading to chart 1.9.0 (Steamfitter API 3.10.0)

Steamfitter API 3.10.0 removes the StackStorm dependency. VM operations now go through the Crucible [VM API](https://github.com/cmu-sei/vm.Api), and SSH and email tasks are executed directly by the Steamfitter API. **This is a breaking change for existing deployments.** Review the following before upgrading.

**Settings removed.** Delete these from your values file; they are no longer read:

- `VmTaskProcessing__ApiType`
- `VmTaskProcessing__ApiUsername`
- `VmTaskProcessing__ApiPassword`
- `VmTaskProcessing__ApiBaseUrl`
- `VmTaskProcessing__ApiParameters__clusters`

**Settings to add.** Configure [SSH Task Execution](#ssh-task-execution) and [Email Task Execution](#email-task-execution) if your scenarios use those task actions. Both fail until configured — SSH needs a private key, email needs an SMTP host.

**VM API version.** VM API 3.8.11 or later is required. See [Prerequisites](#prerequisites).

**Database migration.** The `RemoveStackstormApiUrl` migration rewrites existing `tasks` and `results` rows, remapping `api_url` from `stackstorm` to `vm`, `ssh` or `email` based on each row's action. It runs automatically on startup because the chart sets `Database__AutoMigrate: true`. Back up the database first.

**Task actions removed.** These actions no longer exist and existing scenarios using them will fail after the upgrade:

| Removed action | Behavior after upgrade |
|---------|-------------|
| `vm_create_from_template` | Task fails; `Vm Action ... has not been implemented` is logged |
| `vm_hw_remove` | Task fails; `Vm Action ... has not been implemented` is logged |
| `az_vm_shell_script`, `az_get_vms`, `az_vm_power_off`, `az_vm_power_on` | The migration does not remap these, so `api_url` stays `stackstorm` and execution throws `NotImplementedException` |

Audit your scenarios for these actions before upgrading. Azure task support is expected to return once the equivalent operations are available in the VM API.

**New actions.** `vm_snapshot_create`, `vm_snapshot_revert` and `vm_snapshot_delete` are now available, along with Proxmox support for VM actions alongside vSphere. No chart configuration is required for either; the provider is resolved per VM through the VM API.

## Steamfitter API Configuration

The following are configured via the `steamfitter-api.env` settings. These Steamfitter API settings reflect the application's [appsettings.json](https://github.com/cmu-sei/Steamfitter.Api/blob/development/Steamfitter.Api/appsettings.json) which may contain more settings than are described here.

### Image

| Setting | Description | Example |
|---------|-------------|---------|
| `image.tag` | Override the image tag (defaults to chart `appVersion`) | `""` |

### Database Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `PathBase` | Virtual directory path base | `""` |
| `Logging__IncludeScopes` | Include scopes in logging | `false` |
| `Logging__Debug__LogLevel__Default` | Debug log level default | `Information` |
| `Logging__Debug__LogLevel__Microsoft` | Debug log level Microsoft | `Error` |
| `Logging__Debug__LogLevel__System` | Debug log level System | `Error` |
| `Logging__Console__LogLevel__Default` | Console log level default | `Information` |
| `Logging__Console__LogLevel__Microsoft` | Console log level Microsoft | `Error` |
| `Logging__Console__LogLevel__System` | Console log level System | `Error` |
| `ConnectionStrings__PostgreSQL` | PostgreSQL connection string | `Server=postgres;Port=5432;Database=steamfitter_api;Username=steamfitter;Password=PASSWORD;` |
| `Database__AutoMigrate` | Automatically apply database migrations | `true` |
| `Database__DevModeRecreate` | Recreate database on startup (dev only) | `false` |
| `Database__Provider` | Database provider | `PostgreSQL` |

**Important:**
Database requires the `uuid-ossp` extension:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

**Example:**
```yaml
steamfitter-api:
  env:
    ConnectionStrings__PostgreSQL:
```

### Authentication (OIDC)

| Setting | Description | Example |
|---------|-------------|---------|
| `Authorization__Authority` | Identity provider URL for the user authentication flow | `https://identity.example.com` |
| `Authorization__AuthorizationUrl` | Identity provider authorization endpoint for the user authentication flow | `https://identity.example.com/connect/authorize` |
| `Authorization__TokenUrl` | Identity provider token endpoint for the user authentication flow | `https://identity.example.com/connect/token` |
| `Authorization__AuthorizationScope` | OAuth scopes for the Steamfitter to request for the user authentication flow | `player-api steamfitter-api vm-api` |
| `Authorization__ClientId` | OAuth client ID | `steamfitter-api` |
| `Authorization__ClientName` | OAuth client display name | `Steamfitter API` |
| `Authorization__ClientSecret` | OAuth2 client secret | `""` |
| `Authorization__RequireHttpsMetaData` | Require HTTPS for metadata | `false` |

### CORS Policy Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `CorsPolicy__Origins__0` | First allowed CORS origin | `https://steamfitter.example.com` |
| `CorsPolicy__Methods__0` | CORS allowed methods | `""` |
| `CorsPolicy__Headers__0` | CORS allowed headers | `""` |
| `CorsPolicy__AllowAnyOrigin` | Allow any CORS origin | `false` |
| `CorsPolicy__AllowAnyMethod` | Allow any CORS method | `true` |
| `CorsPolicy__AllowAnyHeader` | Allow any CORS header | `true` |
| `CorsPolicy__SupportsCredentials` | CORS supports credentials | `true` |

**Note:** Additional origins can be added using the pattern `CorsPolicy__Origins__1`, `CorsPolicy__Origins__2`, etc.

### xAPI Settings

Steamfitter can emit [xAPI](https://xapi.com/) statements to a Learning Record Store (LRS) to record scenario task activity.

| Setting | Description | Default |
|---------|-------------|---------|
| `XApiOptions__Enabled` | Enable xAPI statement recording | `false` |
| `XApiOptions__Endpoint` | LRS endpoint URL | `""` |
| `XApiOptions__Username` | LRS basic-auth username | `""` |
| `XApiOptions__Password` | LRS basic-auth password | `""` |
| `XApiOptions__IssuerUrl` | Identity provider issuer URL (used to resolve actor identifiers) | `""` |
| `XApiOptions__ApiUrl` | Steamfitter API URL (used in statement context) | `""` |
| `XApiOptions__UiUrl` | Steamfitter UI URL (used in statement context) | `""` |
| `XApiOptions__EmailDomain` | Email domain appended to usernames to form xAPI actor mbox | `""` |
| `XApiOptions__Platform` | Platform name reported in xAPI statements | `Steamfitter` |
| `XApiOptions__RetentionDays` | Number of days to retain locally stored xAPI records | `7` |
| `XApiOptions__ProcessingTimeoutMinutes` | Timeout in minutes for xAPI statement processing | `10` |
| `XApiOptions__ProcessingDelaySeconds` | Delay in seconds between xAPI processing cycles | `30` |

### Claims Transformation

| Setting | Description | Example |
|---------|-------------|---------|
| `ClaimsTransformation__EnableCaching` | Enable claims caching | `true` |
| `ClaimsTransformation__CacheExpirationSeconds` | Claims cache expiration in seconds | `60` |

### File Storage

| Setting | Description | Example |
|---------|-------------|---------|
| `Files__LocalDirectory` | Local file directory | `"/tmp/"` |

### Certificate Trust

Trust custom certificate authorities by referencing a Kubernetes ConfigMap that contains the CA bundle.

```yaml
steamfitter-api:
  certificateMap: "custom-ca-certs"
```

### Extra Environment Sources

Inject additional environment variables into the API container from existing Kubernetes Secrets or ConfigMaps using `extraEnvFrom`. This is useful for integrating with external secret managers such as AWS Secrets Manager (via the [External Secrets Operator](https://external-secrets.io/)) or HashiCorp Vault.

```yaml
steamfitter-api:
  extraEnvFrom:
    - secretRef:
        name: my-secret
    - configMapRef:
        name: my-configmap
```

Each entry follows the standard Kubernetes [`envFrom`](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#configure-all-key-value-pairs-in-a-configmap-as-container-environment-variables) spec and supports both `secretRef` and `configMapRef`.

### Crucible Integration (Player and VM API)

Steamfitter needs to integrate with Crucible [Player](https://github.com/cmu-sei/Player.Api) and [VM API](https://github.com/cmu-sei/vm.Api)

| Setting | Description | Example |
|---------|-------------|---------|
| `ClientSettings__urls__playerApi` | Player API URL | `https://player.example.com/` |
| `ClientSettings__urls__vmApi` | VM API URL | `https://vm.example.com/` |

**URLs must include trailing slash.**

Steamfitter needs to communicate to the Crucible [VM API](https://github.com/cmu-sei/vm.Api) application via a Resource Owner OAuth Flow for API-to-API communication using a service account. Use the following settings to configure the Resource Owner flow.

| Setting | Description | Example |
|---------|-------------|---------|
| `ResourceOwnerAuthorization__Authority` | Identity provider URL | `https://identity.example.com` |
| `ResourceOwnerAuthorization__ClientId` | Service account client ID | `steamfitter-api` |
| `ResourceOwnerAuthorization__UserName` | Service account username | `steamfitter-service` |
| `ResourceOwnerAuthorization__Password` | Service account password | `password` |
| `ResourceOwnerAuthorization__Scope` | Service account scopes | `vm-api` |
| `ResourceOwnerAuthorization__ClientSecret` | Resource owner client secret | `""` |
| `ResourceOwnerAuthorization__TokenExpirationBufferSeconds` | Token expiration buffer | `900` |

### VM Task Processing

| Setting | Description | Example |
|---------|-------------|---------|
| `VmTaskProcessing__VmListUpdateIntervalMinutes` | VM list update interval | `5` |
| `VmTaskProcessing__HealthCheckSeconds` | Health check interval | `30` |
| `VmTaskProcessing__HealthCheckTimeoutSeconds` | Health check timeout | `90` |
| `VmTaskProcessing__TaskProcessIntervalMilliseconds` | Task processing interval | `5000` |
| `VmTaskProcessing__TaskProcessMaxWaitSeconds` | Task processing max wait | `120` |
| `VmTaskProcessing__ExpirationCheckSeconds` | Expiration check interval | `30` |

### SSH Task Execution

The `core_remote`, `linux_file_touch` and `linux_rm` task actions are executed directly by the Steamfitter API over SSH, rather than through the VM API.

| Setting | Description | Example |
|---------|-------------|---------|
| `Ssh__DefaultPrivateKey` | Default SSH private key contents (PEM) | `"-----BEGIN OPENSSH PRIVATE KEY-----\n..."` |
| `Ssh__DefaultPrivateKeyPath` | Path to a mounted default SSH private key file | `/etc/steamfitter/ssh/id_ed25519` |
| `Ssh__DefaultPrivateKeyPassphrase` | Passphrase for the default private key, if encrypted | `""` |
| `Ssh__CommandTimeoutSeconds` | Connection and command timeout in seconds | `60` |

Authentication is key-based only; there is no password option. A key is resolved in this order:

1. The `PrivateKey` parameter on the individual task
2. `Ssh__DefaultPrivateKey`
3. `Ssh__DefaultPrivateKeyPath`

If none is set, SSH tasks fail with `No SSH private key configured`. Target hosts default to port 22 unless the task supplies a port.

Prefer mounting the key rather than inlining it. All `steamfitter-api.env` values are written to a Kubernetes Secret, but a key supplied through `extraEnvFrom` (see [Extra Environment Sources](#extra-environment-sources)) keeps it out of your values file:

```yaml
steamfitter-api:
  extraEnvFrom:
    - secretRef:
        name: steamfitter-ssh-key # provides Ssh__DefaultPrivateKey
```

Do not set `Ssh__CommandTimeoutSeconds` to `0`. The value is applied to both the connection and command timeout, so a zero value causes every SSH task to time out immediately.

### Email Task Execution

The `send_email` task action is executed directly by the Steamfitter API through an SMTP relay.

| Setting | Description | Example |
|---------|-------------|---------|
| `Email__SmtpHost` | SMTP server hostname. Email tasks fail until this is set | `smtp.example.com` |
| `Email__SmtpPort` | SMTP server port | `587` |
| `Email__UseStartTls` | Use STARTTLS when the server advertises it | `true` |
| `Email__SmtpUsername` | SMTP username. Leave empty for an unauthenticated relay | `""` |
| `Email__SmtpPassword` | SMTP password | `""` |
| `Email__DefaultFromAddress` | From address used when a task does not specify one | `steamfitter@example.com` |
| `Email__AcceptAllCertificates` | Skip SMTP TLS certificate validation. Do not enable in production | `false` |

Leaving `Email__SmtpPort` at `0` lets the SMTP client pick a default port (25), which is rarely what you want — set the port explicitly.

### Health Probes

The deployment configures Kubernetes liveness, readiness, and startup probes against the API's `/api/health/live` and `/api/health/ready` endpoints. Defaults are tuned to tolerate slow startups (e.g. EF Core migrations, cold JIT) while still surfacing failures.

```yaml
steamfitter-api:
  probes:
    livenessProbe:
      enabled: true
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 15
      failureThreshold: 5
      successThreshold: 1
    readinessProbe:
      enabled: true
      initialDelaySeconds: 5
      periodSeconds: 10
      timeoutSeconds: 15
      failureThreshold: 5
      successThreshold: 1
    startupProbe:
      enabled: true
      initialDelaySeconds: 0
      periodSeconds: 10
      timeoutSeconds: 15
      failureThreshold: 15
      successThreshold: 1
```

Set `enabled: false` on a probe to disable it.

### Ingress
Configure the ingress to allow connections to the application (typically uses an ingress controller like [ingress-nginx](https://github.com/kubernetes/ingress-nginx)).

```yaml
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      kubernetes.io/ingress.class: nginx
      nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
      nginx.ingress.kubernetes.io/use-regex: "true"
    hosts:
      - host: steamfitter.example.com
        paths:
          - path: /(api|swagger|hubs)
            pathType: ImplementationSpecific
    tls:
      - secretName: ""
        hosts:
          - example.com
```

### OpenTelemetry

Steamfitter.Api is wired with [Crucible.Common.ServiceDefaults](https://github.com/cmu-sei/crucible-common-dotnet/tree/main/src/Crucible.Common.ServiceDefaults), which auto-enables [OpenTelemetry](https://opentelemetry.io/) logs/traces/metrics. Configure the OTLP exporter endpoint and service name for Steamfitter to send OTLP to an OpenTelemetry Collector (e.g., [Otel Collector](https://opentelemetry.io/docs/collector/) or [Grafana Alloy](https://grafana.com/docs/alloy/latest/)):

```yaml
steamfitter-api:
  env:
    # This can be a kubernetes service address if the collector is running in the cluster
    OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317

    # Optional: force HTTP instead of the default gRPC protocol
    # OTEL_EXPORTER_OTLP_PROTOCOL: http/protobuf
    # Optional: override the service name reported to collectors
    # OTEL_SERVICE_NAME: steamfitter-api

    # These settings toggle ServiceDefaults configurations for Otel
    # The values listed here are the defaults
    # OpenTelemetry__AddAlwaysOnTracingSampler: false
    # OpenTelemetry__AddConsoleExporter: false
    # OpenTelemetry__AddPrometheusExporter: false
    # OpenTelemetry__IncludeDefaultActivitySources: true
    # OpenTelemetry__IncludeDefaultMeters: true
```

| Setting | Description | Default |
|---------|-------------|---------|
| `OpenTelemetry__AddAlwaysOnTracingSampler` | Always sample every trace (useful for development; not recommended in high-traffic production) | `false` |
| `OpenTelemetry__AddConsoleExporter` | Export traces and metrics to stdout in addition to the OTLP endpoint | `false` |
| `OpenTelemetry__AddPrometheusExporter` | Expose a `/metrics` scrape endpoint for Prometheus | `false` |
| `OpenTelemetry__IncludeDefaultActivitySources` | Register the default ASP.NET Core, HttpClient, and EF Core activity sources | `true` |
| `OpenTelemetry__IncludeDefaultMeters` | Register the default ASP.NET Core, HttpClient, and runtime meters | `true` |

#### Default metrics from ServiceDefaults
- Instrumentations: ASP.NET Core, HttpClient, Entity Framework Core, .NET runtime, and process resource metrics.
- Built-in meters: `Microsoft.AspNetCore.Hosting`, `Microsoft.AspNetCore.Server.Kestrel`, `System.Net.Http`, `System.Net.NameResolution`, `Microsoft.EntityFrameworkCore`, plus runtime/process meters.
- Resource attribute `service_name` defaults to `steamfitter-api` (or your `OTEL_SERVICE_NAME` override).

## Steamfitter UI Configuration

### Image

| Setting | Description | Example |
|---------|-------------|---------|
| `image.tag` | Override the image tag (defaults to chart `appVersion`) | `""` |

### Application Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `APP_BASEHREF` | To host Steamfitter from a subpath | `/steamfitter` |

Use `settingsYaml` to configure settings for the Angular UI application.

| Setting                         | Description                                        | Example Value                                     |
|---------------------------------|----------------------------------------------------|---------------------------------------------------|
| `ApiUrl`           | Base URL for the Steamfitter API                                | `https://steamfitter.example.com/api`             |
| `VmApiUrl`         | Base URL for the VM API used by Steamfitter                     | `https://vm.example.com/api`                      |
| `ApiPlayerUrl`     | Base URL for the Player API interface                           | `https://player.example.com/api`                  |
| `OIDCSettings.authority` | URL of the identity provider (OIDC authority)             | `https://identity.example.com`                    |
| `OIDCSettings.client_id` | OAuth client ID used by the Steamfitter UI                | `steamfitter-ui`                              |
| `OIDCSettings.redirect_uri`  | URI where the identity provider redirects after login | `https://steamfitter.example.com/auth-callback/`  |
| `OIDCSettings.post_logout_redirect_uri` | URI users are redirected to after logout   | `https://steamfitter.example.com`                 |
| `OIDCSettings.response_type` | OAuth response type defining the authentication flow  | `code`                                            |
| `OIDCSettings.scope`         | Space-delimited list of OAuth scopes requested        | `openid profile player-api vm-api steamfitter-api`|
| `OIDCSettings.automaticSilentRenew` | Enables automatic token renewal                | `true`                                            |
| `OIDCSettings.silent_redirect_uri`  | URI for silent token renewal callbacks         | `https://steamfitter.example.com/auth-callback-silent.html` |
| `UseLocalAuthStorage` | Whether authentication state is stored locally in browser    | `true`                                            |

### Shared Settings ConfigMap

`sharedSettingsConfigMap` mounts a pre-existing Kubernetes ConfigMap as `settings.shared.json` into the Angular app's `assets/config/` directory alongside `settings.env.json`. This is intended for UI configuration values that are consistent across several Crucible applications, so the values only need to be defined in one place. Any value in the shared file can be overridden per-application using `settingsYaml`.

```yaml
steamfitter-ui:
  sharedSettingsConfigMap: "crucible-shared-ui-settings"
```

The referenced ConfigMap must contain a key named `settings.shared.json`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: crucible-shared-ui-settings
data:
  settings.shared.json: |
    {
      "HeaderBarSettings": {
        "banner_background_color": "#d40000ff",
        "classification_text": "EXAMPLE // CLASSIFICATION",
        "enabled": true
      }
    }
```

When `sharedSettingsConfigMap` is not set (the default), no shared settings file is mounted and the behavior is unchanged.

### Classification Banner

Steamfitter UI supports an optional classification banner via `HeaderBarSettings`. The banner is enabled by default with empty message values, resulting in no header bar being shown to the user. Configure `classification_text` and `message_text` to display content.

| Setting | Description | Example |
|---------|-------------|---------|
| `HeaderBarSettings.enabled` | Show or hide the classification banner | `true` |
| `HeaderBarSettings.banner_background_color` | Background color of the banner (hex with alpha) | `#d40000ff` |
| `HeaderBarSettings.classification_text` | Classification label displayed in the banner | `""` |
| `HeaderBarSettings.classification_text_color` | Color of the classification label text | `#ffffff` |
| `HeaderBarSettings.classification_text_fontsize` | Font size (px) of the classification label | `"14"` |
| `HeaderBarSettings.message_text` | Secondary message text displayed in the banner | `""` |
| `HeaderBarSettings.message_text_color` | Color of the secondary message text | `#ffffff` |
| `HeaderBarSettings.message_text_fontsize` | Font size (px) of the secondary message text | `"14"` |

Example:

```yaml
steamfitter-ui:
  settingsYaml:
    HeaderBarSettings:
      enabled: true
      banner_background_color: "#d40000ff"
      classification_text: "Example Classification Test"
      classification_text_color: "#ffffff"
      classification_text_fontsize: "14"
      message_text: "Example Message"
      message_text_color: "#ffffff"
      message_text_fontsize: "14"
```

![example classification banner with an example message](img/steamfitter-classification-banner-example.png)

## Troubleshooting

### Task Execution Failures
- Check VM API integration is working
- Ensure service account has VM API permissions
- Verify the target VMs are powered on and reachable
- Review the Steamfitter API pod logs for task execution errors
- `Vm Action ... has not been implemented` means the task uses an action removed in 3.10.0; see [Upgrading](#upgrading-to-chart-190-steamfitter-api-3100)

### SSH Task Failures
- `No SSH private key configured` means neither `Ssh__DefaultPrivateKey` nor `Ssh__DefaultPrivateKeyPath` is set and the task supplied no `PrivateKey`
- Timeouts on every host usually mean `Ssh__CommandTimeoutSeconds` is `0`; set it to a positive value
- Per-host errors are captured in the task result output, prefixed with the host name
- Verify the API pod can reach the target hosts on the SSH port and that the key is authorized for the task's username

### Email Task Failures
- `Email:SmtpHost is not configured` means `Email__SmtpHost` is unset
- Verify `Email__SmtpPort` is correct for your relay; `0` falls back to port 25
- For TLS handshake errors, confirm `Email__UseStartTls` matches what the relay expects, and trust the relay's CA via `certificateMap` (see [Certificate Trust](#certificate-trust)) rather than enabling `Email__AcceptAllCertificates`
- Ensure `Email__DefaultFromAddress` is set, or that each task supplies a from address the relay will accept

### Integration Issues
- Verify Player and VM API URLs are accessible
- Check service account credentials
- Ensure scopes include necessary APIs

### Database Connection Issues
- Verify database exists and is accessible
- Ensure `uuid-ossp` extension is installed
- Check connection string credentials

## Task Execution

Typical workflow:

1. Steamfitter creates a scenario with scheduled tasks
2. At execution time, VM operations (power, snapshot, guest file and process actions) are submitted to the Crucible [VM API](https://github.com/cmu-sei/vm.Api); SSH and email tasks are executed directly by the Steamfitter API
3. Results are returned to Steamfitter for tracking

## References

- [Steamfitter Documentation](https://cmu-sei.github.io/crucible/steamfitter/)
- [Steamfitter API Repository](https://github.com/cmu-sei/Steamfitter.Api)
- [Steamfitter UI Repository](https://github.com/cmu-sei/Steamfitter.Ui)
