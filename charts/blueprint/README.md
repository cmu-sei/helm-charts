# Blueprint Helm Chart

[Blueprint](https://cmu-sei.github.io/crucible/blueprint/) is Crucible's application that enables collaborative creation and visualization of a Master Scenario Event List (MSEL) for an exercise. Scenario events are mapped to specific simulation objectives and organized into a timeline.

This Helm chart deploys Blueprint with both API and UI components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (IdentityServer/Keycloak) for OAuth2/OIDC authentication

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install blueprint sei/blueprint -f values.yaml
```

## Configuration

### Blueprint API

#### Database

| Parameter | Description | Required |
|-----------|-------------|----------|
| `blueprint-api.env.ConnectionStrings__PostgreSQL` | PostgreSQL connection string | **Yes** |

**Important:** Database requires the `uuid-ossp` extension:
```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

**Example:**
```yaml
blueprint-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=blueprint_api;Username=blueprint;Password=PASSWORD;"
```

#### OAuth2/OIDC

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `blueprint-api.env.Authorization__Authority` | Identity provider URL | **Yes** | `https://identity.example.com` |
| `blueprint-api.env.Authorization__AuthorizationUrl` | Authorization endpoint | **Yes** | `https://identity.example.com/connect/authorize` |
| `blueprint-api.env.Authorization__TokenUrl` | Token endpoint | **Yes** | `https://identity.example.com/connect/token` |
| `blueprint-api.env.Authorization__AuthorizationScope` | OAuth scopes | **Yes** | `blueprint` |
| `blueprint-api.env.Authorization__ClientId` | OAuth client ID | **Yes** | `blueprint.swagger` |
| `blueprint-api.env.Authorization__ClientName` | Client display name | No | `Blueprint API Swagger` |

#### CORS

| Parameter | Description | Default |
|-----------|-------------|---------|
| `blueprint-api.env.CorsPolicy__Origins__0` | Allowed CORS origin (typically Blueprint UI) | `https://blueprint.example.com` |

### Blueprint UI

```yaml
blueprint-ui:
  settingsYaml:
    ApiUrl: https://blueprint.example.com
    OIDCSettings:
      authority: https://identity.example.com/
      client_id: blueprint-ui
      redirect_uri: https://blueprint.example.com/auth-callback
      post_logout_redirect_uri: https://blueprint.example.com
      response_type: code
      scope: openid profile blueprint
      automaticSilentRenew: true
      silent_redirect_uri: https://blueprint.example.com/auth-callback-silent
    AppTitle: Blueprint
    AppTopBarHexColor: "#2d69b4"
    AppTopBarHexTextColor: "#FFFFFF"
    AppTopBarText: "Blueprint - Exercise Planning"
    AppTopBarImage: /assets/img/monitor-dashboard-white.png
    UseLocalAuthStorage: true
```

## Minimal Production Configuration

```yaml
blueprint-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=blueprint;Username=blueprint;Password=PASSWORD;"
    Authorization__Authority: https://identity.example.com
    Authorization__AuthorizationUrl: https://identity.example.com/connect/authorize
    Authorization__TokenUrl: https://identity.example.com/connect/token
    Authorization__AuthorizationScope: "blueprint"
    Authorization__ClientId: blueprint-swagger
    CorsPolicy__Origins__0: "https://blueprint.example.com"

blueprint-ui:
  settingsYaml:
    ApiUrl: https://blueprint.example.com
    OIDCSettings:
      authority: https://identity.example.com/
      client_id: blueprint-ui
      redirect_uri: https://blueprint.example.com/auth-callback
      response_type: code
      scope: openid profile blueprint
```

## Ingress Configuration

Requires long timeouts for SignalR:

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
          - path: /(api|swagger/hubs)
            pathType: ImplementationSpecific
```

## Security Best Practices

1. **Secrets Management**: Use Kubernetes secrets for sensitive values
2. **TLS Everywhere**: Always use HTTPS in production
3. **CORS Configuration**: Only allow necessary origins

## References

- [Blueprint Documentation](https://cmu-sei.github.io/crucible/blueprint/)
- [Blueprint API Repository](https://github.com/cmu-sei/Blueprint.Api)
- [Blueprint UI Repository](https://github.com/cmu-sei/Blueprint.Ui)
