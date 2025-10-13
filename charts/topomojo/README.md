# TopoMojo Helm Chart

[TopoMojo](https://cmu-sei.github.io/crucible/topomojo/about/) is Crucible's application for designing simple labs and challenges using form-based configurations. Select and configure virtual machines, define networks, and write a guide.

This Helm chart deploys TopoMojo with both API and UI components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL or SQL Server database
- Identity provider (IdentityServer/Keycloak) for OAuth2/OIDC authentication
- VMware vSphere/vCenter, Proxmox, or compatible hypervisor
- Persistent storage for VM files and ISOs

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install topomojo sei/topomojo -f values.yaml
```

## Quick Start Configurations

### Development (Mock Hypervisor)

```yaml
topomojo-api:
  env:
    Database__Provider: InMemory
    Oidc__Authority: https://identity.example.com
    Oidc__Audience: topomojo-api
    # Pod__Url left empty = mock hypervisor
```

### Production (vSphere)

```yaml
topomojo-api:
  env:
    # Database
    Database__Provider: PostgreSQL
    Database__ConnectionString: "Host=postgres;Database=topomojo;Username=tm_user;Password=PASSWORD;"

    # Authentication
    Oidc__Authority: https://identity.example.com
    Oidc__Audience: topomojo-api
    Oidc__UserRolesClaimPath: realm_access.roles
    Oidc__UserRolesClaimMap__administrator: Administrator
    Oidc__UserRolesClaimMap__builder: Builder

    # File Storage
    FileUpload__TopoRoot: /mnt/tm
    FileUpload__IsoRoot: /mnt/tm/isos
    FileUpload__DocRoot: /mnt/tm/_docs

    # vSphere Connection
    Pod__Url: https://vcenter.example.com/sdk
    Pod__User: topomojo@vsphere.local
    Pod__Password: "PASSWORD"
    Pod__VmStore: "[datastore1] _run/"
    Pod__IsoStore: "[nfs-isos] iso/"
    Pod__DiskStore: "[datastore1]"
    Pod__Uplink: dvs-topomojo
    Pod__Vlan__Range: "100-200"

  storage:
    size: 100Gi
    class: nfs-client
```

## Configuration Reference

### Database Settings

| Parameter | Description | Values | Default |
|-----------|-------------|--------|---------|
| `topomojo-api.env.Database__Provider` | Database type | `InMemory`, `PostgreSQL`, `SqlServer` | `InMemory` |
| `topomojo-api.env.Database__ConnectionString` | Database connection string | Connection string | `topomojo_db` |
| `topomojo-api.env.Database__AdminId` | Initial admin user ID (subject claim) | GUID or email | `""` |
| `topomojo-api.env.Database__AdminName` | Initial admin display name | String | `""` |

**Important:**
- `InMemory` is for development only - data is lost on restart
- For production, use `PostgreSQL` or `SqlServer`
- `AdminId` should match the user's subject claim from your identity provider

### Authentication (OIDC)

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `topomojo-api.env.Oidc__Authority` | Identity provider URL | **Yes** | `http://localhost:5000` |
| `topomojo-api.env.Oidc__Audience` | Expected audience in tokens | **Yes** | `topomojo-api` |
| `topomojo-api.env.Oidc__UserRolesClaimPath` | Path to roles in JWT | No | `realm_access.roles` |

**Role Mapping** - Map IdP roles to TopoMojo roles:

```yaml
topomojo-api:
  env:
    Oidc__UserRolesClaimMap__administrator: Administrator  # Full access
    Oidc__UserRolesClaimMap__builder: Builder              # Create/manage workspaces
    Oidc__UserRolesClaimMap__creator: Creator              # Create gamespaces
    Oidc__UserRolesClaimMap__observer: Observer            # Read-only
    Oidc__UserRolesClaimMap__user: User                    # Standard user
```

### File Storage

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `topomojo-api.env.FileUpload__TopoRoot` | Root directory for topology files | **Yes** | `tm` |
| `topomojo-api.env.FileUpload__IsoRoot` | Directory for ISO files | **Yes** | `tm/isos` |
| `topomojo-api.env.FileUpload__DocRoot` | Directory for documentation | **Yes** | `tm/_docs` |

**Important:**
- These paths must be on persistent storage
- ISO directory must be accessible to both TopoMojo and hypervisors (typically NFS)
- For multi-replica deployments, use `ReadWriteMany` storage

### Core Application Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `topomojo-api.env.Core__DefaultGamespaceMinutes` | Default gamespace (lab session) duration | `120` (2 hours) |
| `topomojo-api.env.Core__DefaultGamespaceLimit` | Max concurrent gamespaces per user | `2` |
| `topomojo-api.env.Core__DefaultWorkspaceLimit` | Max workspaces per user (0=unlimited) | `0` |
| `topomojo-api.env.Core__DefaultTemplateLimit` | Max VMs per workspace | `3` |
| `topomojo-api.env.Core__AllowUnprivilegedVmReconfigure` | Allow users to change VM resources | `false` |

### Hypervisor Configuration

**Without a hypervisor** (`Pod__Url` empty), TopoMojo runs in mock mode for testing.

#### vSphere Connection

| Parameter | Description | Required | Example |
|-----------|-------------|----------|---------|
| `topomojo-api.env.Pod__Url` | vCenter SDK URL | **Yes** | `https://vcenter.example.com/sdk` |
| `topomojo-api.env.Pod__User` | vCenter username | **Yes** | `topomojo@vsphere.local` |
| `topomojo-api.env.Pod__Password` | vCenter password | **Yes** | Store in secret |

#### Resource Pools and Storage

| Parameter | Description | Example |
|-----------|-------------|---------|
| `topomojo-api.env.Pod__PoolPath` | vSphere resource pool path | `/Datacenter/host/Cluster/Resources/TopoMojo` |
| `topomojo-api.env.Pod__VmStore` | Datastore for VM files | `[datastore1] _run/` |
| `topomojo-api.env.Pod__IsoStore` | Datastore for ISO files | `[nfs-isos] iso/` |
| `topomojo-api.env.Pod__DiskStore` | Datastore for virtual disks | `[datastore1]` |

**Format:** `[datastore-name] path/`

**Storage Architecture:**
- **Block Storage (VMFS/VSAN):** Use for `VmStore` and `DiskStore`
- **NFS Storage:** Required for `IsoStore` (must be accessible to both TopoMojo and ESXi hosts)

**Example Configuration:**
```yaml
topomojo-api:
  env:
    Pod__VmStore: "[fast-ssd] vms/topomojo/"
    Pod__IsoStore: "[nfs-shared] isos/"
    Pod__DiskStore: "[fast-ssd]"
```

#### Network Configuration

| Parameter | Description | Example |
|-----------|-------------|---------|
| `topomojo-api.env.Pod__Uplink` | Virtual switch for VM networking | `dvs-topomojo` or `vSwitch0` |
| `topomojo-api.env.Pod__Vlan__Range` | Available VLANs for isolation | `100-200` or `10,20,30-40` |

**VLAN Configuration:**
- Format: Comma-separated ranges or individual VLANs
- VLANs must be trunked on physical network
- Required for network isolation between labs

#### Advanced Hypervisor Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `topomojo-api.env.Pod__KeepAliveMinutes` | Connection keepalive interval | `10` |
| `topomojo-api.env.Pod__DebugVerbose` | Enable verbose hypervisor logging | `false` |
| `topomojo-api.env.Pod__TicketUrlHandler` | Console ticket URL format | `querystring` |

### Console Proxy (Optional)

TopoMojo can proxy VM console connections through nginx ingress:

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

**Requirements:**
- Nginx ingress controller must allow snippet annotations:
  - `allow-snippet-annotations: true`
  - `annotations-risk-level: critical`

**How it works:**
- UI connects to: `wss://connect.example.com/console/ticket/TICKET?vmhost=10.4.52.68`
- Nginx proxies to: `https://10.4.52.68/ticket/TICKET`

**When to use:**
- vCenter hosts are on private network unreachable from browsers
- Additional security layer for console connections
- Centralized TLS termination

### Caching (Multi-Replica)

For high availability with multiple API replicas:

| Parameter | Description | Required |
|-----------|-------------|----------|
| `topomojo-api.env.Cache__RedisUrl` | Redis connection string | **Yes** (multi-replica) |
| `topomojo-api.env.Cache__Key` | Redis key prefix | No |

**Example:**
```yaml
topomojo-api:
  env:
    Cache__RedisUrl: "redis:6379"
    Cache__Key: "tm:"

  replicaCount: 3
  storage:
    mode: ReadWriteMany  # Required for multi-replica
```

### Database Migrations

Run migrations as a separate job (recommended for multi-replica):

```yaml
topomojo-api:
  migrations:
    enabled: true
    Database__Provider: PostgreSQL
    Database__ConnectionString: "Host=postgres;Database=topomojo;Username=admin;Password=PASSWORD;"
```

## TopoMojo UI Configuration

```yaml
topomojo-ui:
  basehref: ""  # Set to /topomojo if hosting at subpath

  settingsYaml:
    appname: TopoMojo
    oidc:
      client_id: topomojo-ui
      authority: https://identity.example.com
      redirect_uri: https://topomojo.example.com/oidc
      silent_redirect_uri: https://topomojo.example.com/oidc-silent.html
      response_type: code
      scope: openid profile topomojo-api
      automaticSilentRenew: true
      useLocalStorage: true
```

## Storage Configuration

TopoMojo requires persistent storage for VM files and ISOs:

```yaml
topomojo-api:
  storage:
    # Option 1: Use existing PVC
    existing: "topomojo-storage"

    # Option 2: Create new PVC
    size: "100Gi"
    mode: ReadWriteOnce  # Use ReadWriteMany for multi-replica
    class: "nfs-client"
```

**Important:**
- Without storage configuration, `emptyDir` is used (data lost on restart)
- ISO files must be on storage accessible to hypervisors (NFS recommended)

## VMware NSX-T / SDDC Configuration

For software-defined networking with NSX-T:

```yaml
topomojo-api:
  env:
    Pod__IsNsxNetwork: true
    Pod__Sddc__ApiUrl: https://nsx-manager.example.com/api/v1
    Pod__Sddc__ApiKey: "API_KEY"
    Pod__Sddc__SegmentApiPath: policy/api/v1/infra/tier-1s/cgw/segments
```

## Advanced Configuration

### Workspace/Gamespace Expiration

Configure automatic cleanup:

```yaml
topomojo-api:
  env:
    Core__Expirations__IdleWorkspaceVmExpiration: "7.00:00:00"      # 7 days
    Core__Expirations__WorkspaceExpiration: "365.00:00:00"          # 1 year
    Core__Expirations__UnpublishedWorkspaceExpiration: "14.00:00:00" # 14 days
```

Format: `days.hours:minutes:seconds`

### Custom Start Script

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

### OpenAPI/Swagger

```yaml
topomojo-api:
  env:
    OpenApi__Enabled: true  # Set false in production
    OpenApi__ApiName: TopoMojo
    OpenApi__Client__ClientId: topomojo-swagger
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
- Verify `Pod__IsoStore` datastore exists in vCenter
- Ensure ESXi hosts can access the ISO datastore
- Check that TopoMojo can write to `FileUpload__IsoRoot`
- For block storage, use separate NFS datastore for ISOs

### Storage/File Issues
- Ensure storage is persistent (not `emptyDir`)
- Check that `FileUpload__TopoRoot` is writable
- For multi-replica, verify `ReadWriteMany` access mode
- Check volume permissions (owner should be UID 1654)

### Network Isolation Not Working
- Verify `Pod__Vlan__Range` is configured
- Check VLANs are trunked on physical switches
- Ensure `Pod__Uplink` is a distributed virtual switch
- Verify VLANs aren't in use by other systems

### Console Connection Issues
- If using proxy: verify `Core__ConsoleHost` matches ingress host
- Check that ingress controller allows snippet annotations
- Verify WebSocket connections aren't blocked
- Try direct connection first (without proxy) to isolate issue

## Security Best Practices

1. **Secrets Management**: Use Kubernetes secrets for sensitive values:
   ```yaml
   topomojo-api:
     existingSecret: "topomojo-secrets"
   ```

2. **Hypervisor Isolation**: Use dedicated vSphere resource pool and VLAN range

3. **Network Segmentation**: Configure `Pod__Vlan__Range` on isolated network

4. **TLS Everywhere**: Use HTTPS for all endpoints in production

5. **Disable Swagger**: Set `OpenApi__Enabled: false` in production

## Migration from Older Versions

### Volume Permissions
If upgrading and experiencing permission issues:
```yaml
topomojo-api:
  env:
    SKIP_VOL_PERMISSIONS: "true"  # Skip automatic permission changes
```

## References

- [TopoMojo Documentation](https://cmu-sei.github.io/crucible/topomojo/about/)
- [TopoMojo API Repository](https://github.com/cmu-sei/TopoMojo)
- [TopoMojo UI Repository](https://github.com/cmu-sei/topomojo-ui)
- [Configuration Reference](https://github.com/cmu-sei/TopoMojo/blob/main/src/TopoMojo.Api/appsettings.conf)
