# Alloy Helm Chart

[Alloy](https://cmu-sei.github.io/crucible/alloy/) is Crucible's application that enables users to launch on-demand events or join instances of already-running simulations. Following the event, reports can provide a summary of knowledge and performance assessments.

This Helm chart deploys Alloy with both API and UI components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (IdentityServer/Keycloak) for OAuth2/OIDC authentication
- Crucible services: Player, Caster, and Steamfitter

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install alloy sei/alloy -f values.yaml
```

## Configuration

### Alloy API Configuration

#### Proxy Settings

Configure HTTP/HTTPS proxy for outbound API calls if your environment requires it.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `alloy-api.env.http_proxy` | HTTP proxy URL (lowercase) | `""` |
| `alloy-api.env.https_proxy` | HTTPS proxy URL (lowercase) | `""` |
| `alloy-api.env.HTTP_PROXY` | HTTP proxy URL (uppercase) | `""` |
| `alloy-api.env.HTTPS_PROXY` | HTTPS proxy URL (uppercase) | `""` |
| `alloy-api.env.NO_PROXY` | Domains to exclude from proxy | `""` |
| `alloy-api.env.no_proxy` | Domains to exclude from proxy (lowercase) | `""` |

**Note:** Both uppercase and lowercase versions may be needed for different libraries.

#### Application Path

| Parameter | Description | Default |
|-----------|-------------|---------|
| `alloy-api.env.PathBase` | Base path when hosted in virtual directory | `""` |

Set this when hosting behind a reverse proxy at a subpath (e.g., `/alloy`).

#### Database Configuration

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `alloy-api.env.ConnectionStrings__PostgreSQL` | PostgreSQL connection string | **Yes** | See example below |

**Example:**
```yaml
alloy-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=alloy_api;Username=alloy_dbu;Password=secretpassword;"
```

**Important:** The database must have the `uuid-ossp` extension installed:
```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

#### CORS Configuration

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `alloy-api.env.CorsPolicy__Origins__0` | First allowed CORS origin (typically Alloy UI) | **Yes** | `https://alloy.example.com` |
| `alloy-api.env.CorsPolicy__Origins__1` | Additional allowed origins | No | `http://site2.com` |

**Important:**
- Origins must include protocol (http/https) and match exactly
- The first origin should be your Alloy UI URL
- Add more with `__2`, `__3`, etc. for multiple origins

#### OAuth2/OIDC Authentication

Configure interactive authentication for Swagger UI and web clients:

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `alloy-api.env.Authorization__Authority` | Identity provider base URL | **Yes** | `https://identity.example.com` |
| `alloy-api.env.Authorization__AuthorizationUrl` | Authorization endpoint URL | **Yes** | `https://identity.example.com/connect/authorize` |
| `alloy-api.env.Authorization__TokenUrl` | Token endpoint URL | **Yes** | `https://identity.example.com/connect/token` |
| `alloy-api.env.Authorization__AuthorizationScope` | Space-separated OAuth scopes | **Yes** | See below |
| `alloy-api.env.Authorization__ClientId` | OAuth client ID | **Yes** | `alloy-api-dev` |
| `alloy-api.env.Authorization__ClientName` | Display name for client | No | `"Alloy API"` |

**Required Scopes:**
```yaml
Authorization__AuthorizationScope: "alloy-api player-api caster-api steamfitter-api vm-api"
```

#### Service Account (Resource Owner) Authentication

Configure service-to-service authentication for calling Player, Caster, and Steamfitter:

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `alloy-api.env.ResourceOwnerAuthorization__Authority` | Identity provider URL | **Yes** | `https://identity.example.com` |
| `alloy-api.env.ResourceOwnerAuthorization__ClientId` | Service account client ID | **Yes** | `alloy-api` |
| `alloy-api.env.ResourceOwnerAuthorization__ClientSecret` | Client secret | **Yes** | `""` |
| `alloy-api.env.ResourceOwnerAuthorization__UserName` | Service account username | **Yes** | `""` |
| `alloy-api.env.ResourceOwnerAuthorization__Password` | Service account password | **Yes** | `""` |
| `alloy-api.env.ResourceOwnerAuthorization__Scope` | Space-separated scopes | **Yes** | See Authorization scopes |

**Security Note:** Store sensitive values in Kubernetes secrets:

```yaml
alloy-api:
  existingSecret: "alloy-api-secrets"
```

Then create the secret:
```bash
kubectl create secret generic alloy-api-secrets \
  --from-literal=ResourceOwnerAuthorization__ClientSecret="your-secret" \
  --from-literal=ResourceOwnerAuthorization__Password="service-password"
```

#### Crucible Service URLs

Configure endpoints for integrated Crucible services:

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `alloy-api.env.ClientSettings__urls__playerApi` | Player API base URL | **Yes** | `https://player.example.com/` |
| `alloy-api.env.ClientSettings__urls__casterApi` | Caster API base URL | **Yes** | `https://caster.example.com/` |
| `alloy-api.env.ClientSettings__urls__steamfitterApi` | Steamfitter API base URL | **Yes** | `https://steamfitter.example.com/` |

**Important:** URLs must include trailing slash.

#### Certificate Trust

If using self-signed or internal certificates:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `alloy-api.certificateMap` | Name of ConfigMap containing CA certificates | `""` |

### Alloy UI Configuration

#### Ingress

| Parameter | Description | Default |
|-----------|-------------|---------|
| `alloy-ui.ingress.enabled` | Enable ingress | `true` |
| `alloy-ui.ingress.hosts[0].host` | Hostname for UI | `alloy.example.com` |
| `alloy-ui.env.APP_BASEHREF` | Base path for UI | `""` |

#### Application Settings

Configure via `settingsYaml` (recommended) or `settings` (legacy JSON string):

```yaml
alloy-ui:
  settingsYaml:
    ApiUrl: https://alloy.example.com
    OIDCSettings:
      authority: https://identity.example.com/
      client_id: alloy-ui
      redirect_uri: https://alloy.example.com/auth-callback
      post_logout_redirect_uri: https://alloy.example.com
      response_type: code
      scope: openid profile alloy-api player-api caster-api steamfitter-api vm-api
      automaticSilentRenew: true
      silent_redirect_uri: https://alloy.example.com/auth-callback-silent
    AppTitle: Alloy
    AppTopBarText: Alloy
    AppTopBarHexColor: "#b00"
    PlayerUIAddress: https://player.example.com
    UseLocalAuthStorage: true
```

| Parameter | Description | Required |
|-----------|-------------|----------|
| `settingsYaml.ApiUrl` | Alloy API base URL | **Yes** |
| `settingsYaml.OIDCSettings.authority` | Identity provider URL | **Yes** |
| `settingsYaml.OIDCSettings.client_id` | OAuth client ID for UI | **Yes** |
| `settingsYaml.OIDCSettings.redirect_uri` | OAuth redirect after login | **Yes** |
| `settingsYaml.OIDCSettings.scope` | Space-separated OAuth scopes | **Yes** |
| `settingsYaml.PlayerUIAddress` | Player UI URL for navigation | **Yes** |
| `settingsYaml.AppTitle` | Application title | No |
| `settingsYaml.AppTopBarText` | Top bar display text | No |
| `settingsYaml.AppTopBarHexColor` | Top bar color (hex) | No |

## Minimal Production Configuration

```yaml
alloy-api:
  env:
    # Database
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=alloy_api;Username=alloy_dbu;Password=PASSWORD;"

    # CORS
    CorsPolicy__Origins__0: https://alloy.example.com

    # OAuth
    Authorization__Authority: https://identity.example.com
    Authorization__AuthorizationUrl: https://identity.example.com/connect/authorize
    Authorization__TokenUrl: https://identity.example.com/connect/token
    Authorization__AuthorizationScope: "alloy-api player-api caster-api steamfitter-api vm-api"
    Authorization__ClientId: alloy-api

    # Service Account
    ResourceOwnerAuthorization__Authority: https://identity.example.com
    ResourceOwnerAuthorization__ClientId: alloy-service
    ResourceOwnerAuthorization__ClientSecret: "SECRET"
    ResourceOwnerAuthorization__UserName: alloy-sa
    ResourceOwnerAuthorization__Password: "PASSWORD"
    ResourceOwnerAuthorization__Scope: "alloy-api player-api caster-api steamfitter-api vm-api"

    # Crucible Services
    ClientSettings__urls__playerApi: https://player.example.com/
    ClientSettings__urls__casterApi: https://caster.example.com/
    ClientSettings__urls__steamfitterApi: https://steamfitter.example.com/

alloy-ui:
  settingsYaml:
    ApiUrl: https://alloy.example.com
    PlayerUIAddress: https://player.example.com
    OIDCSettings:
      authority: https://identity.example.com/
      client_id: alloy-ui
      redirect_uri: https://alloy.example.com/auth-callback
      silent_redirect_uri: https://alloy.example.com/auth-callback-silent
      response_type: code
      scope: openid profile alloy-api player-api caster-api steamfitter-api vm-api
```

## Advanced Configuration

### Background Service Settings

The Alloy API includes a background service that manages event lifecycles and Caster operations. While not directly configurable via Helm, the following settings exist in `appsettings.json`:

- `ClientSettings__BackgroundTimerIntervalSeconds` (default: 30) - Bootstrap retry interval
- `ClientSettings__CasterCheckIntervalSeconds` (default: 5) - Caster polling interval
- `ClientSettings__CasterPlanningMaxWaitMinutes` (default: 10) - Max wait for Caster plan
- `ClientSettings__CasterDeployMaxWaitMinutes` (default: 20) - Max wait for Caster deploy
- `ClientSettings__CasterDestroyMaxWaitMinutes` (default: 10) - Max wait for Caster destroy
- `ClientSettings__ApiClientRetryIntervalSeconds` (default: 30) - API retry interval
- `ClientSettings__ApiClientLaunchFailureMaxRetries` (default: 5) - Event launch retries
- `ClientSettings__ApiClientEndFailureMaxRetries` (default: 5) - Event end retries

### SignalR Configuration

For real-time updates via WebSocket connections:

- Requires long ingress timeouts (see `proxy-read-timeout` and `proxy-send-timeout` annotations)
- Default: 86400 seconds (24 hours)
- Path pattern must include `/hubs` in ingress regex

## Troubleshooting

### Database Connection Issues

- Verify PostgreSQL is accessible from the pod
- Ensure `uuid-ossp` extension is installed: `CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`
- Check connection string format and credentials
- Verify database user has CREATE permissions for migrations

### Authentication Failures

- Verify all identity provider URLs are accessible from the pod
- Ensure OAuth client IDs are registered in the identity provider
- Check that scopes match between Alloy and identity provider configuration
- Verify CORS origins include the exact UI URL (protocol and port)
- Confirm service account credentials are correct

### Service Integration Issues

- Verify Player, Caster, and Steamfitter URLs are accessible
- Check that service account has permissions in all integrated services
- Ensure scopes include all required API scopes
- Review background service logs for timeout/retry errors
- Verify trailing slashes are included in service URLs

### SignalR Connection Problems

- Check ingress timeout settings (must be very long for WebSocket)
- Verify ingress path pattern includes `/(api|swagger|hubs)`
- Ensure CORS `AllowCredentials` is enabled
- Confirm WebSocket connections aren't blocked by firewalls

## References

- [Alloy Documentation](https://cmu-sei.github.io/crucible/alloy/)
- [Alloy API Repository](https://github.com/cmu-sei/Alloy.Api)
- [Alloy UI Repository](https://github.com/cmu-sei/Alloy.ui)
- [Crucible Project](https://github.com/cmu-sei/crucible)
