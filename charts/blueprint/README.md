# Blueprint Helm Chart

[Blueprint](https://cmu-sei.github.io/crucible/blueprint/) is the [Crucible](https://cmu-sei.github.io/crucible/) application that enables collaborative creation and visualization of a Master Scenario Event List (MSEL) for an exercise. Scenario events are mapped to specific simulation objectives and organized into a timeline.

This Helm chart deploys Blueprint with both [API](https://github.com/cmu-sei/Blueprint.Api) and [UI](https://github.com/cmu-sei/Blueprint.Ui) components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (e.g., [Keycloak](https://www.keycloak.org/)) for OAuth2/OIDC authentication

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install blueprint sei/blueprint -f values.yaml
```

## Blueprint API Configuration

The following are configured via the `blueprint-api.env` settings. These Blueprint API settings reflect the application's [appsettings.json](https://github.com/cmu-sei/Blueprint.Api/blob/development/Blueprint.Api/appsettings.json) which may contain more settings than are described here.

### Database Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `ConnectionStrings__PostgreSQL` | PostgreSQL connection string | `Server=postgres;Port=5432;Database=blueprint;Username=blueprint;Password=PASSWORD;` |

**Important:** The PostgreSQL database must include the `uuid-ossp` extension:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

### Authentication (OIDC)

| Setting | Description | Example |
|---------|-------------|---------|
| `Authorization__Authority` | Identity provider base URL | `https://identity.example.com` |
| `Authorization__AuthorizationUrl` | Authorization endpoint | `https://identity.example.com/connect/authorize` |
| `Authorization__TokenUrl` | Token endpoint | `https://identity.example.com/connect/token` |
| `Authorization__AuthorizationScope` | OAuth scope requested by the API | `blueprint` |
| `Authorization__ClientId` | OAuth client ID used by the API and interactive clients | `blueprint-api` |
| `Authorization__ClientName` | Display name for the client (optional) | `Blueprint` |

### Certificate Trust

Trust custom certificate authorities by referencing a Kubernetes ConfigMap that contains the CA bundle.

```yaml
blueprint-api:
  certificateMap: "custom-ca-certs"
```

### Helm Deployment Configuration

The following are configurations for the Blueprint API Helm Chart and application configurations that are configured outside of the `blueprint-api.env` section.

#### Ingress

```yaml
blueprint-api:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
      nginx.ingress.kubernetes.io/use-regex: "true"
    hosts:
      - host: blueprint.example.com
        paths:
          - path: /(api|swagger|hubs)
            pathType: ImplementationSpecific
```

## Blueprint UI Configuration

Use `settingsYaml` to configure the Angular UI application. Nested keys in the table below (e.g., `OIDCSettings.authority`) use dot notation for readability.

| Setting | Description | Example |
|---------|-------------|---------|
| `ApiUrl` | Base URL for the Blueprint API | `https://blueprint.example.com` |
| `OIDCSettings.authority` | OIDC authority URL | `https://identity.example.com/` |
| `OIDCSettings.client_id` | OAuth client ID for the Blueprint UI | `blueprint-ui` |
| `OIDCSettings.redirect_uri` | Callback URL after login | `https://blueprint.example.com/auth-callback` |
| `OIDCSettings.post_logout_redirect_uri` | URL users return to after logout | `https://blueprint.example.com` |
| `OIDCSettings.response_type` | OAuth response type | `code` |
| `OIDCSettings.scope` | Space-delimited scopes requested during login | `openid profile blueprint` |
| `OIDCSettings.automaticSilentRenew` | Enables background token renewal | `true` |
| `OIDCSettings.silent_redirect_uri` | URI for silent token renewal callbacks | `https://blueprint.example.com/auth-callback-silent` |
| `UseLocalAuthStorage` | Persist auth state in browser local storage | `true` |
| `AppTitle` | Browser/application title | `Blueprint` |
| `AppTopBarHexColor` | Hex color for the top bar background | `#2d69b4` |
| `AppTopBarHexTextColor` | Hex color for the top bar text | `#FFFFFF` |
| `AppTopBarText` | Banner text displayed in the top bar | `Blueprint - Exercise Planning` |
| `AppTopBarImage` | Path to the banner image | `/assets/img/monitor-dashboard-white.png` |


## References

- [Blueprint Documentation](https://cmu-sei.github.io/crucible/blueprint/)
- [Blueprint API Repository](https://github.com/cmu-sei/Blueprint.Api)
- [Blueprint UI Repository](https://github.com/cmu-sei/Blueprint.Ui)
