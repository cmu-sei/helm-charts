# Player Helm Chart

[Player](https://cmu-sei.github.io/crucible/player/) is the [Crucible](https://cmu-sei.github.io/crucible/) window into virtual environments. Player enables assignment of team membership and customization of responsive, browser-based user interfaces using various integrated applications. Administrators can shape how scenario information, assessments, and virtual environments are presented.

This Helm chart deploys the full Player stack of integrated components:
- [Player API](https://github.com/cmu-sei/Player.Api) - Backend API for the main Player application
- [Player UI](https://github.com/cmu-sei/Player.Ui) - Frontend web interface for the main Player application
- [VM API](https://github.com/cmu-sei/VM.Api) - Backend API for the VM application that integrates with Player to display and manage virtual machines
- [VM UI](https://github.com/cmu-sei/VM.Ui) - Frontend web interface for the VM application that integrates with Player to display and manage virtual machines
- [Console UI](https://github.com/cmu-sei/console.Ui) - VMware Virtual Machine console viewer used by the VM application (above)

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL
- Identity provider (Keycloak) for OAuth2/OIDC authentication
- VMware vSphere/vCenter or Proxmox for VM management
- NFS storage for ISO files (optional)

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install player sei/player -f values.yaml
```

## Player API Configuration

The following are configured via the `player-api.env` settings. These Player API settings reflect the application's [appsettings.json](https://github.com/cmu-sei/Player.Api/blob/main/Player.Api/appsettings.json) which may contain more settings than are described here.

### Database

| Setting | Description | Example |
|---------|-------------|---------|
| `ConnectionStrings__PostgreSQL` | PostgreSQL connection string | `"Server=postgres;Port=5432;Database=player_api;Username=player;Password=PASSWORD;"` |

**Important:**
Database requires the `uuid-ossp` extension:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

### Authentication (OIDC)

| Setting | Description | Example |
|---------|-------------|---------|
| `Authorization__Authority` | Identity provider URL | `https://identity.example.com` |
| `Authorization__AuthorizationUrl` | Authorization endpoint | `https://identity.example.com/connect/authorize` |
| `Authorization__TokenUrl` | Token endpoint | `https://identity.example.com/connect/token` |
| `Authorization__AuthorizationScope` | OAuth scopes | `player-api` |
| `Authorization__ClientId` | OAuth client ID | `vm-api` |

### CORS

Add CORS origins to allow bidirectional communication between Player and the integrated apps.

| Setting | Description | Example |
|---------|-------------|---------|
| `CorsPolicy__Origins__0` | Player UI URL | `https://player.example.com` |
| `CorsPolicy__Origins__1` | VM UI URL | `https://vm.example.com` |
| `CorsPolicy__Origins__2` | Other integrated apps (e.g., OSTicket) | `https://osticket.example.com` |

Add more origins with `__3`, `__4`, etc.

### Seed Data
Optionally bootstrap roles, permissions, and users:

```yaml
player-api:
  env:
    # Custom Permission for your application
    SeedData__Permissions__0__Name: "MyPermission"
    SeedData__Permissions__0__Description: "Does something in my app"

    # Custom TeamPermission for your application
    SeedData__TeamPermissions__0__Name: "MyTeamPermission"
    SeedData__TeamPermissions__0__Description: "Does something for a team in my app"

    # Custom Role
    SeedData__Roles__0__Name: "My Environment Administrator"
    SeedData__Roles__0__AllPermissions: true

    # Custom Team Role
    SeedData__TeamRoles__0__Name: "Team Lead"
    SeedData__TeamRoles__0__Permissions__0: "ManageTeam"

    # Explicitly give a User a Role before they log in.
    SeedData__Users__0__Id: "user-guid-from-identity"
    SeedData__Users__0__Name: "Admin User"
    SeedData__Users__0__Role: "Administrator"
```

### Storage
Configure Player to use a new Kubernetes Persistent Volume Claim to store uploaded files (see the Kubernetes documentation for creating [Persistent Volumes and Persistent Volume Claims](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)).

```yaml
player-api:
  storage:
    # Option 1: Use existing PVC
    existing: "player-storage"

    # Option 2: Create new PVC
    size: "10Gi"
    mode: ReadWriteOnce
    class: "default"
```

### Ingress
Configure the ingress to allow connections to the application (typically uses an ingress controller like [ingress-nginx](https://github.com/kubernetes/ingress-nginx)).

```yaml
player-api:
  ingress:
    enabled: true
    className: "nginx"
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

## Player UI

| Setting | Description | Example |
|---------|-------------|---------|
| `APP_BASEHREF` | To host Player from a subpath | `"/player"` |

Use `settingsYaml` to configure settings for the Angular UI application.

| Setting                      | Description                                                 | Example Value                                      |
|------------------------------|-------------------------------------------------------------|----------------------------------------------------|
| `ApiUrl`                     | Base URL for the Player API                                 | `https://player.example.com`                       |
| `OIDCSettings.authority`     | URL of the identity provider (OIDC authority)               | `https://identity.example.com`                     |
| `OIDCSettings.client_id`     | OAuth client ID used by the Player UI                       | `player-ui`                                    |
| `OIDCSettings.redirect_uri`  | URI where the identity provider redirects after login       | `https://player.example.com/auth-callback/`        |
| `OIDCSettings.post_logout_redirect_uri` | URI users are redirected to after logout         | `https://player.example.com`                       |
| `OIDCSettings.response_type` | OAuth response type defining the authentication flow        | `code`                                             |
| `OIDCSettings.scope`         | Space-delimited list of OAuth scopes requested              | `openid profile player-api`                        |
| `OIDCSettings.automaticSilentRenew` | Enables automatic token renewal                      | `true`                                             |
| `OIDCSettings.silent_redirect_uri`  | URI for silent token renewal callbacks               | `https://player.example.com/auth-callback-silent/` |
| `UseLocalAuthStorage`        | Whether authentication state is stored locally in browser   | `true`                                             |
| `NotificationsSettings.url`  | URL for receiving notifications                             | `https://player.example.com/hubs`                  |
| `NotificationsSettings.number_to_display` | Number of items in the notification area       | `4`                                                |

## VM API Configuration

The following are configured via the `vm-api.env` settings. These VM API settings reflect the application's [appsettings.json](https://github.com/cmu-sei/Vm.Api/blob/main/src/Player.Vm.Api/appsettings.json) which may contain more settings than are described here.


### Database

| Setting | Description | Example |
|---------|-------------|----------|
| `ConnectionStrings__PostgreSQL` | PostgreSQL connection string for VM API | `"Server=postgres;Port=5432;Database=vm_api;Username=vm_user;Password=PASSWORD;"` |

### Authentication (OIDC)

| Setting | Description | Example |
|---------|-------------|---------|
| `Authorization__Authority` | Identity provider URL | `https://identity.example.com` |
| `Authorization__AuthorizationUrl` | Authorization endpoint | `https://identity.example.com/connect/authorize` |
| `Authorization__TokenUrl` | Token endpoint | `https://identity.example.com/connect/token` |
| `Authorization__AuthorizationScope` | OAuth scopes | `vm-api player-api` |
| `Authorization__ClientId` | OAuth client ID | `vm-api` |

### Player API Integration

VM API needs to communicate to the Crucible [VM API](https://github.com/cmu-sei/vm.Api) application via a Resource Owner OAuth Flow for API-to-API communication using a service account. Use the following settings to configure the Resource Owner flow.

| Setting | Description | Example |
|---------|-------------|----------|
| `ClientSettings__urls__playerApi` | Player API URL | `https://player.example.com/` |
| `IdentityClient__TokenUrl` | Token endpoint | `https://identity.example.com/connect/token` |
| `IdentityClient__ClientId` | Service account client ID | `"vm-api"` |
| `IdentityClient__Username` | Service account username | `"vm-service"` |
| `IdentityClient__Password` | Service account password | `"password"` |
| `IdentityClient__Scope` | Service account scopes | `"player-api"` |


### vSphere Configuration

VM API supports connection to multiple vSphere instances. Use the following settings to configure each vSphere host. Replace the `*` with the host index (starting at 0).

| Setting | Description | Example |
|---------|-------------|---------|
| `Vsphere__Hosts__*__Enabled` | Boolean that enables this vSphere host | `true` |
| `Vsphere__Hosts__*__Address` | vCenter hostname or IP address | `vcenter.example.com` |
| `Vsphere__Hosts__*__Username` | vCenter username | `player-account@vsphere.local` |
| `Vsphere__Hosts__*__Password` | vCenter password | `"password"` |
| `Vsphere__Hosts__*__DsName` | Datastore name for file storage | `"nfs-player"` |
| `Vsphere__Hosts__*__BaseFolder` | Folder within datastore | `player` |

**Important:**
- Requires a privileged vCenter user for file operations
- Datastore should be NFS for ease of access
- Format: `<DATASTORE>/player/` (if BaseFolder is provided)

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

| Setting | Description | Default |
|-----------|-------------|---------|
| `CorsPolicy__Origins__0` | VM UI URL | `https://vm.example.com` |
| `CorsPolicy__Origins__1` | Console UI URL | `https://console.example.com` |

### Ingress

Configure the ingress to allow connections to the application (typically uses an ingress controller like [ingress-nginx](https://github.com/kubernetes/ingress-nginx)).

```yaml
vm-api:
  ingress:
    enabled: true
    className: "nginx"
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

## VM UI Configuration

| Setting | Description | Example |
|---------|-------------|---------|
| `APP_BASEHREF` | To host VM UI from a subpath | `"/vm-ui"` |

Use `settingsYaml` to configure settings for the Angular UI application.

| Setting                         | Description                                        | Example Value                                     |
|---------------------------------|----------------------------------------------------|---------------------------------------------------|
| `ApiUrl`           | Base URL for the VM API                                         | `https://vm.example.com/api`                      |
| `ApiPlayerUrl`     | Base URL for the Player API interface                           | `https://player.example.com/api`                  |
| `UserFollowUrl`    | URL scheme for the User Follow feature of Console UI            | `https://console.example.com/user/{userId}/view/{viewId}/console` |
| `OIDCSettings.authority` | URL of the identity provider (OIDC authority)             | `https://identity.example.com`                    |
| `OIDCSettings.client_id` | OAuth client ID used by the VM UI                         | `vm-ui`                                       |
| `OIDCSettings.redirect_uri`  | URI where the identity provider redirects after login | `https://vm.example.com/auth-callback/`           |
| `OIDCSettings.post_logout_redirect_uri` | URI users are redirected to after logout   | `https://vm.example.com`                          |
| `OIDCSettings.response_type` | OAuth response type defining the authentication flow  | `code`                                            |
| `OIDCSettings.scope`         | Space-delimited list of OAuth scopes requested        | `openid profile player-api vm-api`                |
| `OIDCSettings.automaticSilentRenew` | Enables automatic token renewal                | `true`                                            |
| `OIDCSettings.silent_redirect_uri`  | URI for silent token renewal callbacks         | `https://vm.example.com/auth-callback-silent/`    |
| `UseLocalAuthStorage` | Whether authentication state is stored locally in browser    | `true`                                            |


### Console UI Configuration

| Setting | Description | Example |
|---------|-------------|---------|
| `APP_BASEHREF` | To host Console UI from a subpath | `"/console-ui"` |

Use `settingsYaml` to configure settings for the Angular UI application.

| Setting                         | Description                                        | Example Value                                       |
|---------------------------------|----------------------------------------------------|-----------------------------------------------------|
| `ConsoleApiUrl`    | Base URL for the VM API                                         | `https://vm.example.com/api/`                       |
| `OIDCSettings.authority` | URL of the identity provider (OIDC authority)             | `https://identity.example.com`                      |
| `OIDCSettings.client_id` | OAuth client ID used by the VM UI                         | `vm-console-ui`                                 |
| `OIDCSettings.redirect_uri`  | URI where the identity provider redirects after login | `https://console.example.com/auth-callback/`        |
| `OIDCSettings.post_logout_redirect_uri` | URI users are redirected to after logout   | `https://console.example.com`                       |
| `OIDCSettings.response_type` | OAuth response type defining the authentication flow  | `code`                                              |
| `OIDCSettings.scope`         | Space-delimited list of OAuth scopes requested        | `openid profile player-api vm-api vm-console-api`   |
| `OIDCSettings.automaticSilentRenew` | Enables automatic token renewal                | `true`                                              |
| `OIDCSettings.silent_redirect_uri`  | URI for silent token renewal callbacks         | `https://console.example.com/auth-callback-silent/` |
| `UseLocalAuthStorage` | Whether authentication state is stored locally in browser    | `true`                                              |
| `VmResolutionOptions` | List of width/height configurations for allowable display resolutions | `- width: 1920`<br>`  height: 1200`<br>`- width: 16280`<br>`  height: 1024` |


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
- Check `proxy-body-size` annotation is set depending on your ISO size needs
- Verify NFS mount is accessible if using `iso.enabled`
- Ensure vCenter datastore has sufficient space
- Check file permissions on datastore

## References

- [Player Documentation](https://cmu-sei.github.io/crucible/player/)
- [Player API Repository](https://github.com/cmu-sei/Player.Api)
- [Player Console UI Repository](https://github.com/cmu-sei/Console.Ui)
- [Player UI Repository](https://github.com/cmu-sei/Player.Ui)
- [Player VM API Repository](https://github.com/cmu-sei/Vm.Api)
- [Player VM UI Repository](https://github.com/cmu-sei/Vm.Ui)
