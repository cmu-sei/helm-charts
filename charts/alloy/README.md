# Alloy Helm Chart

[Alloy](https://cmu-sei.github.io/crucible/alloy/) is the [Crucible](https://cmu-sei.github.io/crucible/) application that enables users to launch on-demand events or join instances of already-running simulations. Following the event, reports can provide a summary of knowledge and performance assessments.

This Helm chart deploys Alloy with both [API](https://github.com/cmu-sei/Alloy.Api) and [UI](https://github.com/cmu-sei/Alloy.Ui) components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (e.g., Keycloak) for OAuth2/OIDC authentication
- Crucible services: [Player](https://cmu-sei.github.io/crucible/player), [Caster](https://cmu-sei.github.io/crucible/caster), and [Steamfitter](https://cmu-sei.github.io/crucible/steamfitter)

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install alloy sei/alloy -f values.yaml
```

## Alloy API Configuration

The following are configured via the `alloy-api.env` settings. These Alloy API settings reflect the application's [appsettings.json](https://github.com/cmu-sei/Alloy.Api/blob/development/Alloy.Api/appsettings.json) which may contain more settings than are described here.

### Database Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `ConnectionStrings__PostgreSQL` | PostgreSQL connection string for the Alloy API | `"Server=postgres;Port=5432;Database=alloy_api;Username=alloy_dbu;Password=PASSWORD;"` |

**Important:** The database must include the `uuid-ossp` extension:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

### Authentication (OIDC)

| Setting | Description | Example |
|---------|-------------|---------|
| `Authorization__Authority` | Identity provider base URL | `https://identity.example.com` |
| `Authorization__AuthorizationUrl` | Authorization endpoint | `https://identity.example.com/connect/authorize` |
| `Authorization__TokenUrl` | Token endpoint | `https://identity.example.com/connect/token` |
| `Authorization__AuthorizationScope` | Space-delimited scopes requested by the API | `alloy-api player-api caster-api steamfitter-api vm-api` |
| `Authorization__ClientId` | OAuth client ID used by Swagger or other interactive clients | `alloy-api-dev` |
| `Authorization__ClientName` | Optional display name for the client | `Alloy API` |

### Service Account (Resource Owner Flow)

Alloy uses a service account to call downstream Crucible services via the resource owner password flow.

| Setting | Description | Example |
|---------|-------------|---------|
| `ResourceOwnerAuthorization__Authority` | Identity provider base URL | `https://identity.example.com` |
| `ResourceOwnerAuthorization__ClientId` | OAuth client ID for the service account | `alloy-api` |
| `ResourceOwnerAuthorization__ClientSecret` | Client secret associated with the service account | `"SECRET"` |
| `ResourceOwnerAuthorization__UserName` | Service account username | `"alloy-sa"` |
| `ResourceOwnerAuthorization__Password` | Service account password | `"PASSWORD"` |
| `ResourceOwnerAuthorization__Scope` | Space-delimited scopes required for downstream APIs | `alloy-api player-api caster-api steamfitter-api vm-api` |

Store secrets in a Kubernetes Secret and reference it via `alloy-api.existingSecret`.

### Crucible Service Endpoints

| Setting | Description | Example |
|---------|-------------|---------|
| `ClientSettings__urls__playerApi` | Player API base URL | `https://player.example.com/` |
| `ClientSettings__urls__casterApi` | Caster API base URL | `https://caster.example.com/` |
| `ClientSettings__urls__steamfitterApi` | Steamfitter API base URL | `https://steamfitter.example.com/` |

**Note:** Include trailing slashes.

### Background Service Settings

Alloy’s background worker coordinates event lifecycles and Caster operations. Override these defaults via `alloy-api.env` as needed:

| Setting | Description | Default |
|---------|-------------|---------|
| `ClientSettings__BackgroundTimerIntervalSeconds` | Interval between background job runs | `60` |
| `ClientSettings__BackgroundTimerHealthSeconds` | Interval between health checks | `180` |
| `ClientSettings__CasterCheckIntervalSeconds` | Poll interval for Caster operations | `30` |
| `ClientSettings__CasterPlanningMaxWaitMinutes` | Max wait for Caster to plan | `15` |
| `ClientSettings__CasterDeployMaxWaitMinutes` | Max wait for Caster to deploy | `120` |
| `ClientSettings__CasterDestroyMaxWaitMinutes` | Max wait for destroy operations | `60` |
| `ClientSettings__CasterDestroyRetryDelayMinutes` | Delay between destroy retries | `1` |
| `ClientSettings__ApiClientRetryIntervalSeconds` | Retry interval for dependent API calls | `10` |
| `ClientSettings__ApiClientLaunchFailureMaxRetries` | Max retries for event launch failures | `10` |
| `ClientSettings__ApiClientEndFailureMaxRetries` | Max retries for event end failures | `10` |

### Proxy Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `http_proxy` | Lowercase HTTP proxy URL | `http://proxy.example.com:8080` |
| `https_proxy` | Lowercase HTTPS proxy URL | `http://proxy.example.com:8080` |
| `HTTP_PROXY` | Uppercase HTTP proxy URL | `http://proxy.example.com:8080` |
| `HTTPS_PROXY` | Uppercase HTTPS proxy URL | `http://proxy.example.com:8080` |
| `NO_PROXY` | Domains/IPs excluded from the proxy | `.local,10.0.0.0/8` |
| `no_proxy` | Lowercase exclusion list for libraries that expect it | `.local,10.0.0.0/8` |

### Helm Deployment Configuration

The following are configurations for the Alloy API Helm Chart and application configurations that are configured outside of the `alloy-api.env` section.

#### Ingress
Configure the ingress to allow connections to the application (typically uses an ingress controller like [ingress-nginx](https://github.com/kubernetes/ingress-nginx)).

```yaml
alloy-api:
  ingress:
    className: "nginx"
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
      nginx.ingress.kubernetes.io/use-regex: "true"
    hosts:
      - host: alloy.example.com
        paths:
          - path: /(api|swagger|hubs)
            pathType: ImplementationSpecific
```

#### Certificate Trust

Mount custom certificate authorities when using internal PKI:

```yaml
alloy-api:
  certificateMap: "custom-ca-certs"
```

Certificates are mounted to `/usr/local/share/ca-certificates`.

## Alloy UI Configuration

| Setting | Description | Example |
|---------|-------------|---------|
| `APP_BASEHREF` | Set when hosting the UI from a subpath | `"/alloy"` |

Use `settingsYaml` to configure settings for the Angular UI application.

| Setting | Description | Example |
|---------|-------------|---------|
| `ApiUrl` | Base URL for the Alloy API | `https://alloy.example.com` |
| `OIDCSettings.authority` | OIDC authority URL | `https://identity.example.com/` |
| `OIDCSettings.client_id` | OAuth client ID for the Alloy UI | `alloy-ui` |
| `OIDCSettings.redirect_uri` | Callback URL after login | `https://alloy.example.com/auth-callback` |
| `OIDCSettings.post_logout_redirect_uri` | URL users return to after logout | `https://alloy.example.com` |
| `OIDCSettings.response_type` | OAuth response type | `code` |
| `OIDCSettings.scope` | Space-delimited scopes requested during login | `openid profile alloy-api player-api caster-api steamfitter-api vm-api` |
| `OIDCSettings.automaticSilentRenew` | Enables background token renewal | `true` |
| `OIDCSettings.silent_redirect_uri` | URI for silent token renewal callbacks | `https://alloy.example.com/auth-callback-silent` |
| `AppTitle` | Browser/application title | `Alloy` |
| `AppTopBarText` | Text displayed in the UI header | `Alloy` |
| `AppTopBarHexColor` | Hex color for the header background | `"#b00"` |
| `PlayerUIAddress` | Player UI URL for cross-navigation | `https://player.example.com` |
| `UseLocalAuthStorage` | Persist auth state in local storage | `true` |

## Troubleshooting

### Database Connection Issues
- Confirm PostgreSQL is reachable from the Alloy API pod.
- Verify the `uuid-ossp` extension is installed on the database.
- Check connection string syntax, credentials, and SSL requirements.
- Ensure the database user can run migrations (CREATE/ALTER permissions).

### Authentication Failures
- Confirm identity provider URLs are accessible from the cluster network.
- Ensure OAuth clients are registered with the identity provider.
- Verify requested scopes exist and match identity provider configuration.
- Double-check CORS origins for protocol and host accuracy.
- Confirm service account credentials align with identity provider settings.

### Service Integration Issues
- Validate Player, Caster, and Steamfitter APIs are reachable from Alloy.
- Ensure the service account has permissions in each downstream service.
- Review background service logs for timeout or retry warnings.
- Confirm trailing slashes are present in dependent service URLs.

### SignalR Connection Problems
- Verify ingress timeout annotations are set to high values (e.g., 86400).
- Ensure the ingress path includes `/(api|swagger|hubs)`.
- Confirm WebSocket traffic is allowed by network policies and load balancers.
- Check browser console logs for CORS or authentication errors.

## References

- [Alloy Documentation](https://cmu-sei.github.io/crucible/alloy/)
- [Alloy API Repository](https://github.com/cmu-sei/Alloy.Api)
- [Alloy UI Repository](https://github.com/cmu-sei/Alloy.Ui)
- [Crucible Documentation](https://cmu-sei.github.io/crucible/)
