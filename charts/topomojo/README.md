# TopoMojo Helm Chart

[TopoMojo](https://cmu-sei.github.io/crucible/topomojo/) is the [Crucible](https://cmu-sei.github.io/crucible/) application for designing labs and challenges using a simple user interface. Deploy and configure virtual machines, define networks, and write a guide.

This Helm chart deploys TopoMojo with both [API](https://github.com/cmu-sei/TopoMojo) and [UI](https://github.com/cmu-sei/TopoMojo-ui) components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL or SQL Server database
- Identity provider (e.g., Keycloak) for OAuth2/OIDC authentication
- Supported Hypervisor (VMware vSphere/vCenter or Proxmox). Note that each TopoMojo instance supports either vSphere or Proxmox, not both simultaneously.
- Persistent storage for VM files and ISOs

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install topomojo sei/topomojo -f values.yaml
```

## TopoMojo API Configuration

The following are configured via the `topomojo-api.env` settings. These TopoMojo API settings reflect the application's [appsettings.conf](https://github.com/cmu-sei/TopoMojo/blob/main/src/TopoMojo.Api/appsettings.conf) which may contain more settings than are described here.

### Database Settings

| Setting | Description | Values | Example |
|---------|-------------|--------|---------|
| `Database__Provider` | Database type | `InMemory`, `PostgreSQL`, `SqlServer` | `InMemory` |
| `Database__ConnectionString` | Database connection string | Connection string | `"Server=postgres;Port=5432;Database=topomojo;Username=topomojo;Password=PASSWORD;"` |
| `Database__AdminId` | Initial admin user ID (subject claim) | GUID or email | `"<GUID>"` |
| `Database__AdminName` | Initial admin display name | String | `"Admin"` |

**Important:**
- `InMemory` is for development only - data is lost on restart
- For production, use `PostgreSQL` or `SqlServer`
- `AdminId` should match the user's subject claim from your identity provider

### Authentication (OIDC)

| Setting | Description | Example |
|---------|-------------|---------|
| `Oidc__Authority` | Identity provider URL | `https://identity.example.com` |
| `Oidc__Audience` | Expected audience in tokens | `topomojo-api` |

#### Identity Provider Role Mapping

TopoMojo can ingest roles from the identity provider (e.g. Keycloak). For example, an identity administrator can add roles like administrator, builder, or any custom role of their choosing and configure TopoMojo's API to map those IDP roles to TopoMojo roles.

Use the `Oidc__UserRolesClaimPath` setting to provide the JWT path to identity role assignments.

You can add any number of unique entries in this format to TopoMojo API's configuration to map an identity role to a TopoMojo role. For example, if you want to map users with the identity role "powerUser" to the TopoMojo role "Builder", you'd add an entry that looks like this: `Oidc__UserRolesClaimMap__powerUser = Builder`.

**If you specify any Oidc__UserRolesClaimMap__\* values in your application configuration, no default mappings will be applied.** If you don't specify any claim mappings, you'll automatically receive the default mappings.

| Setting | Description | Default |
|---------|-------------|---------|
| `Oidc__UserRolesClaimPath` | Path to roles in JWT | `"realm_access.roles"` (Keycloak default). <br> Set this to `""` to disable IDP role mapping. |
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

### File Storage

| Setting | Description | Example |
|---------|-------------|---------|
| `FileUpload__TopoRoot` | Root directory for various files such as workspace import/export zips. The path provided is a path mounted in the container. (e.g., `/mnt/tm`) | `/opt/topomojo` (Default) |
| `FileUpload__IsoRoot` | Directory for ISO files. This is typically an NFS mounted volume that is also presented as a datastore to the hypervisor to allow mounting ISOs to VMs. | `/opt/topomojo/isos` (Default) |
| `FileUpload__DocRoot` | Directory for documentation | `/opt/topomojo/docs` (Default) |

**Important**
- These paths must be on persistent storage for data to remain after a pod restart.
- ISO directory must be accessible to both TopoMojo and hypervisors (typically NFS).
- See the [Storage Section](#storage) for more information on storage.

### Core Application Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `Core__DefaultGamespaceMinutes` | Default gamespace duration | `60` (Default) |
| `Core__DefaultGamespaceLimit` | Max concurrent gamespaces per user | `1` (Default) |
| `Core__DefaultWorkspaceLimit` | Max workspaces per user (0=unlimited) | `10` (Default) |
| `Core__DefaultTemplateLimit` | Max VMs per workspace | `10` (Default) |
| `Core__AllowUnprivilegedVmReconfigure` | Allow users set VM networks to reserved network segments  | `false` (Default) |

### OpenAPI/Swagger

| Setting | Description | Example |
|---------|-------------|---------|
| `OpenApi__Enabled` | Enable the built-in Swagger/OpenAPI UI and JSON endpoint. | `false` (Default) |
| `OpenApi__ApiName` | Display name for the API in the Swagger/OpenAPI UI. | `TopoMojo API` (Default) |
| `OpenApi__Client__ClientId` | OAuth2/OpenID Connect client ID used for authenticating via the Swagger UI. | `"topomojo-swagger"` |

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
| `Pod__Sddc__AuthUrl` | When using a VMware Cloud SDDC, set the URL for SDDC authentication. | `https://console.cloud.vmware.com/csp/gateway/am/api/auth/api-tokens/authorize` |
| `Pod__Sddc__MetadataUrl` | When using a VMware Cloud SDDC, set the URL used to read SDDC Metadata such as the NSX endpoint URLs | `https://vmc.vmware.com/vmc/api/orgs/<org_id>/sddcs/<sddc_id>`
| Pod__Sddc__ApiKey` | When using a VMware Cloud SDDC, set the value of an API key for authentication | `api_key`
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
| `FileUpload_IsoRoot` | Path mounted to the container that ISOs uploaded through TopoMojo will be saved to - should map to the same storage as `Pod__IsoStore`. **For Proxmox deployments, this path must end with `/template/iso`.** | `/mnt/isos/template/iso` |
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

## TopoMojo UI Configuration

Use `settingsYaml` to configure settings for the Angular UI application. Example settings are provided in the [application repository](https://github.com/cmu-sei/topomojo-ui/blob/main/projects/topomojo-work/src/assets/example-settings.json).

| Setting | Description | Example |
|---------|-------------|---------|
| `appname` | The display name of the application shown in the UI and browser title. | `TopoMojo` |
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
