# Player Helm Chart

[Player](https://cmu-sei.github.io/crucible/player/) is Crucible's window into virtual environments. Player enables assignment of team membership and customization of responsive, browser-based user interfaces using various integrated applications. Administrators can shape how scenario information, assessments, and virtual environments are presented.

This Helm chart deploys the full Player stack including:
- **Player API** - Core view and team management
- **Player UI** - Main user interface
- **VM API** - Virtual machine management
- **VM UI** - VM administration interface
- **Console UI** - VM console viewer

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL databases (player_api and vm_api)
- Identity provider (IdentityServer/Keycloak) for OAuth2/OIDC authentication
- VMware vSphere/vCenter for VM management
- NFS storage for ISO files (optional)

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install player sei/player -f values.yaml
```

## Architecture

Player consists of multiple integrated components:

1. **Player API**: Manages views, teams, applications, and roles
2. **Player UI**: Primary user interface for viewing and team collaboration
3. **VM API**: Interfaces with vSphere for VM operations and console access
4. **VM UI**: Administrative interface for VM management
5. **Console UI**: Full-screen VM console viewer

## Configuration

### Player API

#### Database

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `player-api.env.ConnectionStrings__PostgreSQL` | PostgreSQL connection string | **Yes** | Example shown |

**Important:** Database requires the `uuid-ossp` extension:
```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

**Example:**
```yaml
player-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=player_api;Username=player;Password=PASSWORD;"
```

#### OAuth2/OIDC

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `player-api.env.Authorization__Authority` | Identity provider URL | **Yes** | `https://identity.example.com` |
| `player-api.env.Authorization__AuthorizationUrl` | Authorization endpoint | **Yes** | `https://identity.example.com/connect/authorize` |
| `player-api.env.Authorization__TokenUrl` | Token endpoint | **Yes** | `https://identity.example.com/connect/token` |
| `player-api.env.Authorization__AuthorizationScope` | OAuth scopes | **Yes** | `player-api` |
| `player-api.env.Authorization__ClientId` | OAuth client ID | **Yes** | `player-api-dev` |
| `player-api.env.Authorization__ClientName` | Client display name | No | `"Player API"` |

#### CORS

| Parameter | Description | Default |
|-----------|-------------|---------|
| `player-api.env.CorsPolicy__Origins__0` | Player UI URL | `https://player.example.com` |
| `player-api.env.CorsPolicy__Origins__1` | VM UI URL | `https://vm.example.com` |
| `player-api.env.CorsPolicy__Origins__2` | Other integrated apps (e.g., OSTicket) | `https://osticket.example.com` |

Add more origins with `__3`, `__4`, etc.

#### Storage

Persistent storage for uploaded files:

```yaml
player-api:
  storage:
    size: "10Gi"
    mode: ReadWriteOnce
    class: default
```

#### Seed Data

Bootstrap roles, permissions, and users:

```yaml
player-api:
  env:
    SeedData__Permissions__0__Name: "ViewAdmin"
    SeedData__Permissions__0__Description: "Administer views"

    SeedData__Roles__0__Name: "Administrator"
    SeedData__Roles__0__AllPermissions: true

    SeedData__TeamPermissions__0__Name: "ManageTeam"
    SeedData__TeamPermissions__0__Description: "Manage team membership"

    SeedData__TeamRoles__0__Name: "TeamLead"
    SeedData__TeamRoles__0__Permissions__0: "ManageTeam"

    SeedData__Users__0__Id: "user-guid-from-identity"
    SeedData__Users__0__Name: "Admin User"
    SeedData__Users__0__Role: "Administrator"
```

### Player UI

```yaml
player-ui:
  env:
    APP_BASEHREF: ""  # Set to /player if hosting at subpath

  settingsYaml:
    ApiUrl: https://player.example.com
    OIDCSettings:
      authority: https://identity.example.com
      client_id: player-ui-dev
      redirect_uri: https://player.example.com/auth-callback/
      post_logout_redirect_uri: https://player.example.com
      response_type: code
      scope: openid profile player-api
      automaticSilentRenew: true
      silent_redirect_uri: https://player.example.com/auth-callback-silent/
    NotificationsSettings:
      url: https://player.example.com/hubs
      number_to_display: 4
    AppTitle: Crucible
    AppTopBarText: Crucible
    AppTopBarHexColor: "#b00"
    AppTopBarHexTextColor: "#FFFFFF"
    UseLocalAuthStorage: true
```

### VM API

#### Database

| Parameter | Description | Required |
|-----------|-------------|----------|
| `vm-api.env.ConnectionStrings__PostgreSQL` | Separate PostgreSQL connection for VM API | **Yes** |

**Example:**
```yaml
vm-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=vm_api;Username=vm_user;Password=PASSWORD;"
```

#### OAuth2/OIDC

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `vm-api.env.Authorization__Authority` | Identity provider URL | **Yes** | `https://identity.example.com` |
| `vm-api.env.Authorization__AuthorizationUrl` | Authorization endpoint | **Yes** | `https://identity.example.com/connect/authorize` |
| `vm-api.env.Authorization__TokenUrl` | Token endpoint | **Yes** | `https://identity.example.com/connect/token` |
| `vm-api.env.Authorization__AuthorizationScope` | OAuth scopes | **Yes** | `vm-api player-api` |
| `vm-api.env.Authorization__ClientId` | OAuth client ID | **Yes** | `vm-api-dev` |

#### Service Account (for Player API integration)

| Parameter | Description | Required |
|-----------|-------------|----------|
| `vm-api.env.IdentityClient__TokenUrl` | Token endpoint | **Yes** |
| `vm-api.env.IdentityClient__ClientId` | Service account client ID | **Yes** |
| `vm-api.env.IdentityClient__Username` | Service account username | **Yes** |
| `vm-api.env.IdentityClient__Password` | Service account password | **Yes** |
| `vm-api.env.IdentityClient__Scope` | Service account scopes | **Yes** |

**Example:**
```yaml
vm-api:
  env:
    IdentityClient__TokenUrl: https://identity.example.com/connect/token
    IdentityClient__ClientId: "player-vm-admin"
    IdentityClient__Username: "vm-service"
    IdentityClient__Password: "PASSWORD"
    IdentityClient__Scope: "player-api vm-api"
```

#### Player Integration

| Parameter | Description | Required |
|-----------|-------------|----------|
| `vm-api.env.ClientSettings__urls__playerApi` | Player API URL | **Yes** |

**Example:**
```yaml
vm-api:
  env:
    ClientSettings__urls__playerApi: "https://player.example.com"
```

#### vSphere Configuration

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `vm-api.env.Vsphere__Host` | vCenter hostname | **Yes** | `vcenter.example.com` |
| `vm-api.env.Vsphere__Username` | vCenter username | **Yes** | `player-account@vsphere.local` |
| `vm-api.env.Vsphere__Password` | vCenter password | **Yes** | `""` |
| `vm-api.env.Vsphere__DsName` | Datastore name for file storage | **Yes** | `""` |
| `vm-api.env.Vsphere__BaseFolder` | Folder within datastore | No | `player` |

**Important:**
- Requires a privileged vCenter user for file operations
- Datastore should be NFS for ease of access
- Format: `<DATASTORE>/player/`

**Example:**
```yaml
vm-api:
  env:
    Vsphere__Host: "vcenter.example.com"
    Vsphere__Username: "player@vsphere.local"
    Vsphere__Password: "PASSWORD"
    Vsphere__DsName: "nfs-player"
    Vsphere__BaseFolder: "player"
```

#### Console Proxy (Optional)

For proxying VM console connections through nginx ingress:

```yaml
vm-api:
  env:
    RewriteHost__RewriteHost: true
    RewriteHost__RewriteHostUrl: "connect.example.com"
    RewriteHost__RewriteHostQueryParam: "vmhost"

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

**How it works:**
- Console UI connects to: `wss://connect.example.com/ticket/TICKET?vmhost=10.4.52.68`
- Nginx proxies to: `https://10.4.52.68/ticket/TICKET`

**When to use:**
- vCenter hosts are on private network
- Additional security layer for consoles
- Centralized TLS termination

#### ISO Storage (Optional)

Mount NFS volume for ISO uploads:

```yaml
vm-api:
  iso:
    enabled: true
    server: "nfs-server.example.com"
    path: "/exports/isos"
    size: "100Gi"
```

#### CORS

| Parameter | Description | Default |
|-----------|-------------|---------|
| `vm-api.env.CorsPolicy__Origins__0` | VM UI URL | `https://vm.example.com` |
| `vm-api.env.CorsPolicy__Origins__1` | Console UI URL | `https://console.example.com` |

### VM UI

```yaml
vm-ui:
  env:
    APP_BASEHREF: ""

  settingsYaml:
    ApiUrl: https://vm.example.com/api
    ApiPlayerUrl: https://player.example.com/api
    UserFollowUrl: https://console.example.com/user/{userId}/view/{viewId}/console
    OIDCSettings:
      authority: https://identity.example.com
      client_id: vm-ui-dev
      redirect_uri: https://vm.example.com/auth-callback/
      post_logout_redirect_uri: https://vm.example.com
      response_type: code
      scope: openid profile player-api vm-api
      automaticSilentRenew: true
      silent_redirect_uri: https://vm.example.com/auth-callback-silent/
    UseLocalAuthStorage: true
```

### Console UI

```yaml
console-ui:
  env:
    APP_BASEHREF: ""

  settingsYaml:
    ConsoleApiUrl: https://vm.example.com/api/
    OIDCSettings:
      authority: https://identity.example.com
      client_id: vm-console-ui-dev
      redirect_uri: https://console.example.com/auth-callback/
      post_logout_redirect_uri: https://console.example.com
      response_type: code
      scope: openid profile player-api vm-api vm-console-api
      automaticSilentRenew: true
      silent_redirect_uri: https://console.example.com/auth-callback-silent/
    UseLocalAuthStorage: true
    VmResolutionOptions:
      - width: 1920
        height: 1200
      - width: 1600
        height: 1200
      - width: 1280
        height: 1024
      - width: 1024
        height: 768
```

## Minimal Production Configuration

```yaml
player-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=player_api;Username=player;Password=PASSWORD;"
    Authorization__Authority: https://identity.example.com
    Authorization__AuthorizationUrl: https://identity.example.com/connect/authorize
    Authorization__TokenUrl: https://identity.example.com/connect/token
    Authorization__AuthorizationScope: "player-api"
    Authorization__ClientId: player-api
    CorsPolicy__Origins__0: "https://player.example.com"
    CorsPolicy__Origins__1: "https://vm.example.com"

  storage:
    size: "10Gi"

player-ui:
  settingsYaml:
    ApiUrl: https://player.example.com
    OIDCSettings:
      authority: https://identity.example.com
      client_id: player-ui
      redirect_uri: https://player.example.com/auth-callback/
      response_type: code
      scope: openid profile player-api

vm-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=vm_api;Username=vm;Password=PASSWORD;"
    Authorization__Authority: https://identity.example.com
    Authorization__AuthorizationUrl: https://identity.example.com/connect/authorize
    Authorization__TokenUrl: https://identity.example.com/connect/token
    Authorization__AuthorizationScope: "vm-api player-api"
    Authorization__ClientId: vm-api

    IdentityClient__TokenUrl: https://identity.example.com/connect/token
    IdentityClient__ClientId: "player-vm-admin"
    IdentityClient__Username: "vm-service"
    IdentityClient__Password: "PASSWORD"
    IdentityClient__Scope: "player-api vm-api"

    ClientSettings__urls__playerApi: "https://player.example.com"

    Vsphere__Host: "vcenter.example.com"
    Vsphere__Username: "player@vsphere.local"
    Vsphere__Password: "PASSWORD"
    Vsphere__DsName: "nfs-player"
    Vsphere__BaseFolder: "player"

    CorsPolicy__Origins__0: "https://vm.example.com"
    CorsPolicy__Origins__1: "https://console.example.com"

vm-ui:
  settingsYaml:
    ApiUrl: https://vm.example.com/api
    ApiPlayerUrl: https://player.example.com/api
    OIDCSettings:
      authority: https://identity.example.com
      client_id: vm-ui
      redirect_uri: https://vm.example.com/auth-callback/
      response_type: code
      scope: openid profile player-api vm-api

console-ui:
  settingsYaml:
    ConsoleApiUrl: https://vm.example.com/api/
    OIDCSettings:
      authority: https://identity.example.com
      client_id: vm-console-ui
      redirect_uri: https://console.example.com/auth-callback/
      response_type: code
      scope: openid profile player-api vm-api
```

## Ingress Configuration

### Player API
Requires long timeouts for SignalR:
```yaml
player-api:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
      nginx.ingress.kubernetes.io/use-regex: "true"
    hosts:
      - host: player.example.com
        paths:
          - path: /(hubs|swagger|api)
            pathType: ImplementationSpecific
```

### VM API
Requires long timeouts and large body size for ISO uploads:
```yaml
vm-api:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
      nginx.ingress.kubernetes.io/use-regex: "true"
      nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    hosts:
      - host: vm.example.com
        paths:
          - path: /(notifications|hubs|api|swagger)
            pathType: ImplementationSpecific
```

## Troubleshooting

### Database Connection Issues
- Verify both `player_api` and `vm_api` databases exist
- Ensure `uuid-ossp` extension is installed in both databases
- Check connection string credentials and network access

### vSphere Connection Failures
- Verify vCenter is accessible from VM API pod
- Check vCenter credentials have appropriate permissions
- Ensure datastore exists and is accessible
- For self-signed certs, consider trust configuration

### Authentication Issues
- Verify all OAuth clients are registered in identity provider
- Check that scopes match between Player/VM and identity provider
- Ensure service account credentials are correct
- Verify CORS origins include all UI URLs

### Console Connection Problems
- If using proxy: verify `RewriteHost__RewriteHostUrl` matches ingress host
- Check that WebSocket connections aren't blocked
- Verify console ingress snippet annotations are allowed
- Try direct connection first (without proxy) to isolate issue

### SignalR/Notifications Not Working
- Verify `/hubs` path is included in ingress
- Check ingress timeout settings (must be long for WebSockets)
- Ensure CORS is properly configured
- Verify `NotificationsSettings.url` in Player UI matches Player API URL

### ISO Upload Failures
- Check `proxy-body-size` annotation is set (100m or higher)
- Verify NFS mount is accessible if using `iso.enabled`
- Ensure vCenter datastore has sufficient space
- Check file permissions on datastore

## Security Best Practices

1. **Separate Databases**: Use separate PostgreSQL databases for Player and VM APIs

2. **Service Account Isolation**: Use dedicated service accounts with minimal scopes

3. **TLS Everywhere**: Always use HTTPS in production

4. **vCenter Permissions**: Grant only necessary permissions to Player service account

5. **Secrets Management**: Use Kubernetes secrets:
   ```yaml
   player-api:
     existingSecret: "player-secrets"
   vm-api:
     existingSecret: "vm-secrets"
   ```

6. **Console Security**: Use console proxy to avoid exposing vCenter hosts directly

## References

- [Player Documentation](https://cmu-sei.github.io/crucible/player/)
- [Player API Repository](https://github.com/cmu-sei/Player.Api)
- [Player Console UI Repository](https://github.com/cmu-sei/Console.Ui)
- [Player UI Repository](https://github.com/cmu-sei/Player.Ui)
- [Player VM API Repository](https://github.com/cmu-sei/Vm.Api)
- [Player VM UI Repository](https://github.com/cmu-sei/Vm.Ui)
