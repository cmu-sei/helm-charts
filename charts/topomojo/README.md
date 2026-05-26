# TopoMojo Helm Chart

[TopoMojo](https://cmu-sei.github.io/crucible/topomojo/) is the [Crucible](https://cmu-sei.github.io/crucible/) application for designing labs and challenges using a simple user interface. Deploy and configure virtual machines, define networks, and write a guide.

This Helm chart deploys TopoMojo with both [API](https://github.com/cmu-sei/TopoMojo) and [UI](https://github.com/cmu-sei/TopoMojo-ui) components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL or SQL Server database
- Identity provider (e.g., [Keycloak](https://www.keycloak.org/)) for OAuth2/OIDC authentication
- Supported Hypervisor (VMware vSphere/vCenter or Proxmox). Note that each TopoMojo instance supports either vSphere or Proxmox, not both simultaneously.
- Persistent storage for VM files and ISOs

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install topomojo sei/topomojo -f values.yaml
```

## TopoMojo API Configuration

The following are configured via the `topomojo-api.env` settings. These TopoMojo API settings reflect the application's [appsettings.conf](https://github.com/cmu-sei/TopoMojo/blob/main/src/TopoMojo.Api/appsettings.conf) which may contain more settings than are described here.

### General Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `PathBase` | Path base for virtual directory hosting (e.g., `/tm` when serving from a subpath) | `""` |

### Database Settings

| Setting | Description | Values | Example |
|---------|-------------|--------|---------|
| `Database__Provider` | Database type | `InMemory`, `PostgreSQL`, `SqlServer` | `InMemory` |
| `Database__ConnectionString` | Database connection string | Connection string | `Server=postgres;Port=5432;Database=topomojo;Username=topomojo;Password=PASSWORD;` |
| `Database__AdminId` | Initial admin user ID (subject claim) | GUID or email | `<GUID>` |
| `Database__AdminName` | Initial admin display name | String | `Admin` |

**Important:**
- `InMemory` is for development only - data is lost on restart
- For production, use `PostgreSQL` or `SqlServer`
- `AdminId` should match the user's subject claim from your identity provider

### Cache Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `Cache__RedisUrl` | Redis connection URL for distributed caching. Leave empty to use the default in-process cache. | `""` |
| `Cache__Key` | Cache key prefix used to namespace entries in the cache store. | `""` |
| `Cache__SharedFolder` | Path to a shared folder used for file-based cache sharing between replicas. | `""` |

### Authentication (OIDC)

| Setting | Description | Default |
|---------|-------------|---------|
| `Oidc__Authority` | Identity provider URL | `http://localhost:5000` |
| `Oidc__Audience` | Expected audience in tokens | `topomojo-api` |
| `Oidc__ServiceAccountClientIdClaimType` | JWT claim type used to identify service account clients. Set to `"null"` to disable client credentials authentication. | `client_id` |

#### Identity Provider Role Mapping

TopoMojo can ingest roles from the identity provider. For example, an identity administrator can add roles like administrator, builder, or any custom role of their choosing and configure TopoMojo's API to map those IDP roles to TopoMojo roles.

Use the `Oidc__UserRolesClaimPath` setting to provide the JWT path to identity role assignments.

You can add any number of unique entries in this format to TopoMojo API's configuration to map an identity role to a TopoMojo role. For example, if you want to map users with the identity role "powerUser" to the TopoMojo role "Builder", you'd add an entry that looks like this: `Oidc__UserRolesClaimMap__powerUser = Builder`.

**If you specify any Oidc__UserRolesClaimMap__\* values in your application configuration, no default mappings will be applied.** If you don't specify any claim mappings, you'll automatically receive the default mappings.

| Setting | Description | Default |
|---------|-------------|---------|
| `Oidc__UserRolesClaimPath` | Path to roles in JWT | `realm_access.roles` (Keycloak default). <br> Set this to `""` to disable IDP role mapping. |
| `Oidc__UserRolesClaimMap__[identityRoleName]` | Identity role name to map to TopoMojo role | Default mapping below. |

##### Default Mapping
```yaml
topomojo-api:
  env:
    Oidc__UserRolesClaimPath: "realm_access.roles"         # Keycloak default roles path
    Oidc__UserRolesClaimMap__administrator: Administrator  # Full access
    Oidc__UserRolesClaimMap__builder: Builder              # Create/manage workspaces
    Oidc__UserRolesClaimMap__creator: Creator              # Create gamespaces
    Oidc__UserRolesClaimMap__observer: Observer            # Read-only
    Oidc__UserRolesClaimMap__user: User                    # Standard user
```

### Certificate Trust

Trust custom certificate authorities by referencing a Kubernetes ConfigMap that contains the CA bundle.

```yaml
topomojo-api:
  certificateMap: "custom-ca-certs"
```

### File Storage

TopoMojo writes uploaded files to several directories inside the API pod. The most important is the path that holds ISOs, because ISOs ultimately need to be written where the hypervisor can read them. There are two ways the chart can deliver an uploaded ISO to the hypervisor:

| Mode | Where TopoMojo writes the file | Where the hypervisor reads from | When to use |
|---|---|---|---|
| **NFS-mounted ISO datastore** (default) | `FileUpload__IsoRoot` — a path inside the container backed by an NFS share | The same NFS share, mounted on ESXi as a vSphere datastore (named in `Pod__IsoStore`) | When you have the ability to attach an NFS datastore to ESXi hosts |
| **vSphere HTTP datastore upload** (`FileUpload__UseDatastoreApi: true`) | `FileUpload__TempRoot` — a transient staging dir on the API pod, then HTTP PUT to vSphere | The vSphere datastore named in `Pod__IsoStore` (vSAN, VMFS, etc.), populated by the upload | VMware Cloud on AWS or any environment where the ESXi/SDDC hosts cannot mount your NFS share as a datastore |

In NFS mode, `IsoRoot` is the *final destination* — the file is written once and stays there, visible to both TopoMojo and the hypervisor through the shared NFS mount. In datastore-API mode, `TempRoot` is just a staging area: the file is written there, optionally wrapped in an ISO, HTTP PUT to the vSphere datastore through vCenter, and then reaped by the Janitor when stale.

`TempRoot` is therefore unrelated to `IsoRoot`. They never both contain the same file. `TempRoot` is only read when `UseDatastoreApi=true`; `IsoRoot` is only used as a destination when `UseDatastoreApi=false`. Both are still set on the chart at all times — they're just unused in the mode they don't apply to.

#### Path settings

| Setting | Description | Chart default |
|---------|-------------|---------------|
| `FileUpload__TopoRoot` | Root directory for workspace import/export zips and other persistent files. Backed by the topomojo PVC mount. | `/mnt/tm` |
| `FileUpload__IsoRoot` | Directory for ISO files in NFS mode. Must be accessible to both TopoMojo and the hypervisor — typically an NFS share that ESXi mounts as a vSphere datastore. Unused when `FileUpload__UseDatastoreApi=true`. | `/mnt/tm/isos` |
| `FileUpload__DocRoot` | Directory where workspace document images are stored and served. Points at the chart's dedicated `wwwroot/docs` mount so uploaded images are served by ASP.NET's static-file handler. | `/home/app/wwwroot/docs` |
| `FileUpload__TempRoot` | Staging directory for datastore-API uploads. Backed by a subdirectory on the topomojo PVC; the vol-permissions init container creates and chowns it. Override only if you have provisioned alternative storage yourself. Unused when `FileUpload__UseDatastoreApi=false`. | `/mnt/tm/_iso-staging` |

**Important**
- These paths must be on persistent storage for data to remain after a pod restart.
- **NFS mode:** the chart default `FileUpload__IsoRoot` points at the topomojo PVC, which is *not* readable by ESXi. Override it to a path mounted from the same NFS share your hypervisor uses as a vSphere datastore (the share named in `Pod__IsoStore`); otherwise uploaded ISOs never reach the hypervisor.
- **Datastore-API mode:** `TempRoot` does **not** need to be visible to the hypervisor — only the API pod writes to it. ISOs reach the hypervisor over HTTP via vCenter.
- See the [Storage Section](#storage) for more information on storage.

#### Datastore-API upload settings (VMware Cloud)

In environments where the ESXi hosts cannot mount the shared NFS share
backing `Pod__IsoStore` — most notably **VMware Cloud on AWS**, where
the SDDC's hosts can only see datastores presented by the SDDC itself
(vSAN or attached VMFS) — set `FileUpload__UseDatastoreApi: true`.
TopoMojo will stage uploads to `FileUpload__TempRoot` and then HTTP PUT
them to the vSphere datastore named in `Pod__IsoStore` through vCenter.
The chart provisions `TempRoot` automatically; no extra storage values
are required.

To enable:

```yaml
topomojo-api:
  env:
    FileUpload__UseDatastoreApi: true
```

Optional tuning knobs (defaults shown):

| Setting | Description | Default |
|---------|-------------|---------|
| `FileUpload__MaxFileBytes` | Max upload size in bytes (`0` for unlimited) | `0` |
| `FileUpload__UploadTimeoutMinutes` | HTTP timeout for the datastore PUT | `120` |
| `FileUpload__TempFileExpirationHours` | Stale temp file cleanup threshold | `24` |

Existing NFS-mount deployments leave `FileUpload__UseDatastoreApi`
unset (the default is `false`) and behavior is unchanged.

### Core Application Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `Core__DefaultGamespaceMinutes` | Default gamespace duration in minutes | `120` |
| `Core__DefaultGamespaceLimit` | Max concurrent gamespaces per user | `2` |
| `Core__DefaultWorkspaceLimit` | Max workspaces per user (0=unlimited) | `0` |
| `Core__DefaultTemplateLimit` | Max VMs per workspace | `3` |
| `Core__DefaultUserScope` | Default scope assigned to new users for gamespace access | `everyone` |
| `Core__ReplicaLimit` | Maximum number of replicas allowed per gamespace | `5` |
| `Core__NetworkHostTemplateId` | Template ID used for network host VMs (0 = disabled) | `0` |
| `Core__GameEngineIsoFolder` | Folder name within the ISO store used by the game engine | `static` |
| `Core__LaunchUrl` | URL path used for gamespace launch links | `/lp` |
| `Core__DocPath` | Server-relative path where workspace document assets are served from | `wwwroot/docs` |
| `Core__AllowUnprivilegedVmReconfigure` | Allow unprivileged users to set VM networks to reserved network segments | `false` |

### OpenAPI/Swagger

| Setting | Description | Example |
|---------|-------------|---------|
| `OpenApi__Enabled` | Enable the built-in Swagger/OpenAPI UI and JSON endpoint. | `false` (Default) |
| `OpenApi__ApiName` | Display name for the API in the Swagger/OpenAPI UI. | `TopoMojo API` (Default) |
| `OpenApi__Client__ClientId` | OAuth2/OpenID Connect client ID used for authenticating via the Swagger UI. | `topomojo-swagger` |

### Mock Hypervisor Configuration

**Without a hypervisor** (`Pod__Url` empty), TopoMojo runs in "mock hypervisor" mode for testing.

### vSphere Configuration

See the [TopoMojo documentation](https://github.com/cmu-sei/TopoMojo/blob/main/docs/vSphere.md) for more details and an example vSphere configuration.

| Setting | Description | Example |
|---------|-------------|---------|
| `Pod__HypervisorType` | Set to `vsphere` for vSphere mode | `vsphere` |
| `Pod__Url` | vCenter SDK URL | `https://vcenter.example.com/sdk` |
| `Pod__User` | vCenter username | `topomojo@vsphere.local` |
| `Pod__Password` | vCenter password | `abcd1234` |
| `Pod__PoolPath` | vSphere resource pool path | `/Datacenter/host/Cluster/Resources/TopoMojo` |
| `Pod__VmStore` | Datastore for running VM files | `[datastore1] _run/` |
| `Pod__DiskStore` | Datastore for virtual disks | `[datastore1] topomojo/` |
| `Pod__IsoStore` | Datastore for ISO files | `[nfs-isos] iso/` |
| `Pod__Uplink` | Virtual switch for VM networking | `dvs-topomojo` or `vSwitch0` or `vmc-hostswitch` |
| `Pod__Vlan__Range` | Available VLAN IDs for isolation | `100-200` or `10,20,30-40` |
| `Pod__IsNsxNetwork` | Set to `true` when using NSX Networking. | `false` (default) |
| `Pod__TicketUrlHandler` | Method used to construct VM console ticket URLs. | `querystring` |
| `Pod__Sddc__AuthUrl` | When using a VMware Cloud SDDC, set the URL for SDDC authentication. | `https://console.cloud.vmware.com/csp/gateway/am/api/auth/api-tokens/authorize` |
| `Pod__Sddc__MetadataUrl` | When using a VMware Cloud SDDC, set the URL used to read SDDC Metadata such as the NSX endpoint URLs | `https://vmc.vmware.com/vmc/api/orgs/<org_id>/sddcs/<sddc_id>` |
| `Pod__Sddc__ApiKey` | When using a VMware Cloud SDDC, set the value of an API key for authentication | `api_key` |
| `Pod__Sddc__ApiUrl` | SDDC/vSphere API base URL for direct API calls (distinct from MetadataUrl). | `""` |
| `Pod__Sddc__SegmentApiPath` | NSX-T API path used to manage SDDC network segments. | `policy/api/v1/infra/tier-1s/cgw/segments` |
| `Pod__Sddc__CertificatePath` | Path to a client certificate file used for SDDC API authentication. | `""` |
| `Pod__Sddc__CertificatePassword` | Password for the SDDC client certificate. | `""` |
| `Pod__ExcludeNetworkMask` | Exclude network segments from TopoMojo | `vmcloud` |
| `Pod__KeepAliveMinutes` | Connection keepalive interval | `10` |
| `Pod__DebugVerbose` | Enable verbose hypervisor logging | `false` |
| `Pod__Vlan__Reservations__*__Id` | VLAN ID for a reserved VLAN segment made available to elevated users. This is useful for providing a shared/persistent VLAN segment for accessing the internet (commonly called `bridge-net`). <br> Replace the `*` with an index (e.g., `0`, `1`, etc.) Reserve multiple segments by defining this key multiple times with a different index.  | `200` |
| `Pod__Vlan__Reservations__*__Name` | VLAN name for a reserved VLAN segment made available to elevated users. This is useful for providing a shared/persistent VLAN segment for accessing the internet (commonly called `bridge-net`). <br> Replace the `*` with an index (e.g., `0`, `1`, etc.) Reserve multiple segments by defining this key multiple times with a different index.  | `bridge-net` |

#### vSphere Storage Notes
- Storage Path Format: `[datastore-name] path/`
- Use Block Storage (VMFS/VSAN) for `VmStore` and `DiskStore`
- NFS Storage: Required for `IsoStore` (must be accessible to both TopoMojo and ESXi hosts)

#### vSphere Networking Notes
- Format: Comma-separated ranges or individual VLANs
- VLANs must be trunked on physical network
- Required for network isolation between labs
- Only users with elevated permissions can use reserved VLANs unless `Core__AllowUnprivilegedVmReconfigure` is set to `true`.

#### Console Proxy

TopoMojo can proxy VM console connections through an nginx ingress.

Example:

```yaml
topomojo-api:
  env:
    Core__ConsoleHost: connect.example.com

  consoleIngress:
    deployConsoleProxy: true
    hosts:
      - host: connect.example.com
        paths: []
    tls:
      - secretName: console-tls
        hosts:
          - connect.example.com
```

##### Requirements
- Nginx ingress controller must allow snippet annotations:
  - `allow-snippet-annotations: true`
  - `annotations-risk-level: critical`

##### How it works
- UI connects to: `wss://connect.example.com/console/ticket/TICKET?vmhost=10.4.52.68`
- Nginx proxies to: `https://10.4.52.68/ticket/TICKET`

##### When to use
- vCenter hosts are on private network unreachable from browsers
- Additional security layer for console connections
- Centralized TLS termination


### Proxmox Configuration

See the [TopoMojo documentation](https://github.com/cmu-sei/TopoMojo/blob/main/docs/Proxmox.md) for more details and an example Proxmox configuration. **There are several prerequisite configurations outlined in that documentation.**

| Setting | Description | Example |
|---------|-------------|---------|
| `Pod__HypervisorType` | Set to `Proxmox` for Proxmox mode | `Proxmox` |
| `Pod__Url` | Set to the URL of your primary Proxmox node | `https://proxmox.local` |
| `Pod__AccessToken` | Proxmox authentication access token | `root@pam!TopoMojo=4c4fbe1e-b31e-55a9-9fg0-2de4a411cd23` |
| `Pod__SDNZone` | Name of the Proxmox SDN Zone to use for VM networking (VXLAN is the only supported type) | `topomojo` |
| `Pod__Password` | (Optional) Set this to the password of the **root** user account to enable Guest Settings support. <br>If no password or an invalid root password is provided, Guest Settings will be disabled. | `<root-password>` |
| `Pod__Vlan__ResetDebounceDuration` | (Optional) Number of milliseconds to wait after a virtual network operation is initiated before reloading Proxmox's SDN. | `2000` |
| `Pod__Vlan__ResetDebounceMaxDuration` | (Optional) Maximum number of milliseconds TopoMojo will debounce before it reloads Proxmox's SDN following a network operation. | `5000` |
| `Pod__IsoStore` | Datastore for ISO files | `iso` |
| `FileUpload__IsoRoot` | Path mounted to the container that ISOs uploaded through TopoMojo will be saved to - should map to the same storage as `Pod__IsoStore`. **For Proxmox deployments, this path must end with `/template/iso`.** | `/mnt/isos/template/iso` |
| `FileUpload_SupportsSubFolders` | Set to `false` for Proxmox deployments because Proxmox does not allow sub folders in ISO stores | `false` |


### Helm Deployment Configuration

The following are configurations for the TopoMojo API Helm Chart rather than application configurations.

#### Ingress
Configure the ingress to allow connections to the application (typically uses an ingress controller like [ingress-nginx](https://github.com/kubernetes/ingress-nginx)).

```yaml
  ingress:
    enabled: true
    className: nginx
    # optional ingress annotations to adjust ingress behavior
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: '3600'
      nginx.ingress.kubernetes.io/proxy-send-timeout: '3600'
      nginx.ingress.kubernetes.io/proxy-body-size: 30m

    hosts:
      - host: topomojo.example.com
        paths:
          - path: /tm/api
            pathType: ImplementationSpecific
          - path: /tm/hub
            pathType: ImplementationSpecific
          - path: /tm/docs
            pathType: ImplementationSpecific
          - path: /tm/theme
            pathType: ImplementationSpecific
    tls:
      - secretName: tls-secret-name # this tls secret should already exist
        hosts:
         - topomojo.example.com
```

#### Storage
Configure TopoMojo to use a new/existing Kubernetes Persistent Volume Claim (see the Kubernetes documentation for creating [Persistent Volumes and Persistent Volume Claims](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)).

```yaml
topomojo-api:
  storage:
    # Option 1: Use existing PVC
    existing: "topomojo-storage"

    # Option 2: Create new PVC
    size: "100Gi"
    mode: ReadWriteOnce
    class: "nfs-client"
```

The chart does not impose a default `storage.size` — operators choose a value appropriate for their usage based on factors such as: workspace import/export volume, document-image footprint, and ISO uploads (if using datastore-API mode).

##### Sizing for ISO uploads (datastore-API mode only)

This guidance **only applies when `FileUpload__UseDatastoreApi: true`**. In NFS mode (the default), uploaded ISOs are written directly to the NFS share backing `Pod__IsoStore` and never touch this PVC, so PVC sizing is governed only by `TopoRoot` (workspace export data) and `DocRoot` (documents and images).

When the datastore-API upload feature is enabled, TopoMojo stages each upload at `FileUpload__TempRoot` (a subdirectory on this PVC) before HTTP PUT to vSphere. Sizing this directory has to account for two cases:

- **Non-ISO uploads are wrapped into an ISO before transfer.** A user can upload any file (e.g., an installer or media file) and TopoMojo will build a `.iso` container around it. During that wrap step the staging directory holds *both* the original file *and* the generated ISO — roughly **2× the original size** — until the wrap completes. The original is then deleted immediately, before the upload to vCenter starts.

To size the PVC:

1. **Cap per-upload size** by setting `FileUpload__MaxFileBytes` to a non-zero value. The chart default of `0` means unlimited. Pick a size based on the largest file you expect operators to upload (ISO or otherwise).
2. **Allow at least 4× `FileUpload__MaxFileBytes`** of headroom on top of your normal `TopoRoot` working set. This covers a few concurrent uploads in flight (each transiently 2× during the ISO wrap step for non-ISO files). Environments expecting many simultaneous uploaders should size higher.
3. **Shorten `FileUpload__TempFileExpirationHours`** if mid-upload crashes are leaving residue — successful and failed uploads both clean up immediately, so this knob only governs how long files orphaned by an unclean pod restart linger.

Example for a deployment expecting up to 20 GB ISOs:

```yaml
topomojo-api:
  storage:
    size: "100Gi"  # ~80Gi staging headroom + TopoRoot working set
  env:
    FileUpload__UseDatastoreApi: true
    FileUpload__MaxFileBytes: 21474836480  # 20 GB cap
```

#### Volume Permissions

On startup, an init container chowns the paths under `FileUpload__TopoRoot` and `FileUpload__DocRoot` to UID/GID `1654` (the .NET runtime user). Set `SKIP_VOL_PERMISSIONS` to `"true"` to skip this step — for example, when using a storage class that handles ownership automatically or when the pod runs with a different security context.

```yaml
topomojo-api:
  env:
    SKIP_VOL_PERMISSIONS: "true"
```

#### Extra Environment Sources

Inject additional environment variables into the API container from existing Kubernetes Secrets or ConfigMaps using `extraEnvFrom`. This is useful for integrating with external secret managers such as AWS Secrets Manager (via the [External Secrets Operator](https://external-secrets.io/)) or HashiCorp Vault.

```yaml
topomojo-api:
  extraEnvFrom:
    - secretRef:
        name: my-secret
    - configMapRef:
        name: my-configmap
```

Each entry follows the standard Kubernetes [`envFrom`](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#configure-all-key-value-pairs-in-a-configmap-as-container-environment-variables) spec and supports both `secretRef` and `configMapRef`.

### Logging Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `Logging__Console__DisableColors` | Disable ANSI color codes in console log output (useful in environments that don't support color). | `false` |
| `Logging__LogLevel__Default` | Default minimum log level for all categories. Valid values: `Trace`, `Debug`, `Information`, `Warning`, `Error`, `Critical`, `None`. | `Information` |

### OpenTelemetry

TopoMojo.Api is wired with [Crucible.Common.ServiceDefaults](https://github.com/cmu-sei/crucible-common-dotnet/tree/main/src/Crucible.Common.ServiceDefaults), which auto-enables [OpenTelemetry](https://opentelemetry.io/) logs/traces/metrics. Configure the OTLP exporter endpoint and service name for TopoMojo to send OTLP to an OpenTelemetry Collector (e.g., [Otel Collector](https://opentelemetry.io/docs/collector/) or [Grafana Alloy](https://grafana.com/docs/alloy/latest/)):

```yaml
topomojo-api:
  env:
    # This can be a kubernetes service address if the collector is running in the cluster
    OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317

    # Optional: force HTTP instead of the default gRPC protocol
    # OTEL_EXPORTER_OTLP_PROTOCOL: http/protobuf
    # Optional: override the service name reported to collectors
    # OTEL_SERVICE_NAME: topomojo-api

    # These settings toggle ServiceDefaults configurations for Otel
    # The values listed here are the defaults
    # OpenTelemetry__AddAlwaysOnTracingSampler: false
    # OpenTelemetry__AddConsoleExporter: false
    # OpenTelemetry__AddPrometheusExporter: false
    # OpenTelemetry__IncludeDefaultActivitySources: true
    # OpenTelemetry__IncludeDefaultMeters: true
```

#### OpenTelemetry Settings Reference

| Setting | Description | Default |
|---------|-------------|---------|
| `OTEL_EXPORTER_OTLP_PROTOCOL` | Wire protocol used by the OTLP exporter. Use `http/protobuf` to force HTTP instead of the default gRPC. | `http/protobuf` |
| `OTEL_SERVICE_NAME` | Service name reported to the OpenTelemetry collector. Overrides the default derived from the application name. | `topomojo-api` |
| `OpenTelemetry__AddAlwaysOnTracingSampler` | When `true`, enables an always-on sampler that records every trace regardless of upstream sampling decisions. | `false` |
| `OpenTelemetry__AddConsoleExporter` | When `true`, exports traces and metrics to the console (stdout). Useful for local debugging. | `false` |
| `OpenTelemetry__AddPrometheusExporter` | When `true`, exposes a `/metrics` Prometheus scrape endpoint. | `false` |
| `OpenTelemetry__IncludeDefaultActivitySources` | When `true`, registers the default ASP.NET Core and HttpClient activity sources for distributed tracing. | `true` |
| `OpenTelemetry__IncludeDefaultMeters` | When `true`, registers the default ASP.NET Core, HttpClient, EF Core, and runtime meters. | `true` |

#### Default metrics from ServiceDefaults
- Instrumentations: ASP.NET Core, HttpClient, Entity Framework Core, .NET runtime, and process resource metrics.
- Built-in meters: `Microsoft.AspNetCore.Hosting`, `Microsoft.AspNetCore.Server.Kestrel`, `System.Net.Http`, `System.Net.NameResolution`, `Microsoft.EntityFrameworkCore`, plus runtime/process meters.
- Resource attribute `service_name` defaults to `topomojo-api` (or your `OTEL_SERVICE_NAME` override).

#### Custom Start Script

For custom initialization (e.g., trusting CA certificates):

```yaml
topomojo-api:
  customStart:
    command: ['/bin/sh']
    args: ['/start/start.sh']
    files:
      start.sh: |
        #!/bin/sh
        cp /start/*.crt /usr/local/share/ca-certificates
        update-ca-certificates
        cd /app && dotnet TopoMojo.Api.dll
      custom-ca.crt: |
        -----BEGIN CERTIFICATE-----
        ...
        -----END CERTIFICATE-----
```
#### UI Branding
Configure this variable in the API environment settings area and specify the location and name of the file which is already mounted in the volume.

| Setting | Description | Example |
|---------|-------------|---------|
| `UI__Branding__BackgroundImageUrl` | Set the location and name of the file. | `theme/background.png` |


## TopoMojo UI Configuration

Use `settingsYaml` to configure settings for the Angular UI application. Example settings are provided in the [application repository](https://github.com/cmu-sei/topomojo-ui/blob/main/projects/topomojo-work/src/assets/example-settings.json).

| Setting | Description | Example |
|---------|-------------|---------|
| `appname` | The display name of the application shown in the UI and browser title. | `TopoMojo` |
| `docsUrl` | Overrides the documentation link shown on the UI "About" page. Defaults to the Crucible TopoMojo docs if not set. | `https://cmu-sei.github.io/crucible/topomojo` |
| `disableExternalLinks` | Set to `true` in air-gapped/restricted environments to remove external linking from the UI. | `true` |
| `oidc.client_id` | The OIDC client identifier used when authenticating the UI with the identity provider. | `topomojo-ui` |
| `oidc.authority` | The base URL of the identity provider (OIDC authority) that issues tokens. | `https://identity.example.com` |
| `oidc.redirect_uri` | The URL where users are redirected after a successful login via OIDC. | `https://topomojo.example.com/oidc` |
| `oidc.silent_redirect_uri` | The hidden iframe endpoint used for silently renewing tokens without user interaction. | `https://topomojo.example.com/oidc-silent.html` |
| `oidc.response_type` | The OAuth2 flow response type to request during login, typically `code` for PKCE authorization code flow. | `code` |
| `oidc.scope` | The list of identity and API scopes requested during authentication. | `openid profile topomojo-api` |
| `oidc.automaticSilentRenew` | Enables automatic background token refresh before expiration to maintain user sessions. | `true` |
| `oidc.useLocalStorage` | Stores authentication tokens in localStorage instead of sessionStorage to persist login across browser sessions. | `true` |


### Ingress

To host TopoMojo from a subpath, set `basehref` and configure the ingress accordingly

```yaml
topomojo-ui:
  basehref: "/topomojo"
  ingress:
    enabled: true
    className: nginx
    hosts:
      - host: topomojo.example.com
        paths:
          - path: /topomojo
            pathType: ImplementationSpecific
    tls:
      - secretName: tls-secret-name # this tls secret should already exist
      hosts:
         - topomojo.example.com
```

### OpenGraph

You can configure OpenGraph for enhanced link preview support.

```yaml
topomojo-ui:
  openGraph: >
    <!-- Open Graph info for link previews -->
    <meta property="og:title" content="TopoMojo" />
    <meta property="og:type" content="website" />
    <meta property="og:image" content="https://topomojo.example.com/topomojo/favicon.ico" />
    <meta property="og:url" content="https://topomojo.example.com/topomojo" />
    <meta property="og:description" content="TopoMojo is a lab building environment" />
```

### Favicons

You can customize favicons using a URL to a tgz favicon bundle. The bundle's `favicon.html` will be merged into `index.html`.

```yaml
topomojo-ui:
  faviconsUrl: https://example.com/files/topomojo-favicons.tgz
```

## Troubleshooting

### Database Connection Issues
- Verify database is accessible from pod
- Check connection string format matches provider
- Ensure database user has CREATE permissions for migrations

### Hypervisor Connection Failures
- Verify `Pod__Url` is accessible (try from within a pod)
- Check credentials (`Pod__User` and `Pod__Password`)
- For self-signed certs, may need custom CA trust
- Enable `Pod__DebugVerbose: true` for detailed logs

### ISO Mounting Problems
- Verify `Pod__IsoStore` datastore exists on the Hypervisor
- Ensure hypervisor hosts can access the ISO datastore
- Check that TopoMojo can write to `FileUpload__IsoRoot`
- For block storage, use separate NFS datastore for ISOs

### Storage/File Issues
- Ensure storage is persistent (not `emptyDir`)
- Check that `FileUpload__TopoRoot` is writable
- Check volume permissions (owner should be `UID 1654`)

### Console Connection Issues
- If using proxy: verify `Core__ConsoleHost` matches ingress host
- Check that ingress controller allows snippet annotations
- Verify WebSocket connections aren't blocked
- Try direct connection first (without proxy) to isolate issue

## References

- [TopoMojo Documentation](https://cmu-sei.github.io/crucible/topomojo)
- [TopoMojo API Repository](https://github.com/cmu-sei/TopoMojo)
- [TopoMojo UI Repository](https://github.com/cmu-sei/topomojo-ui)
- [Additional API Settings](https://github.com/cmu-sei/TopoMojo/blob/main/src/TopoMojo.Api/appsettings.conf)
