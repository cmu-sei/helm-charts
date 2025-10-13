# Gallery Helm Chart

[Gallery](https://cmu-sei.github.io/crucible/gallery/) is Crucible's application that enables participants to review cyber incident data by source type. Information is grouped by critical infrastructure sector or organizational categories, with support for multiple source types including intelligence, reporting, orders, news, social media, telephone, and email.

This Helm chart deploys Gallery with both API and UI components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (IdentityServer/Keycloak) for OAuth2/OIDC authentication

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install gallery sei/gallery -f values.yaml
```

## Configuration

### Gallery API

#### Database

| Parameter | Description | Required |
|-----------|-------------|----------|
| `gallery-api.env.ConnectionStrings__PostgreSQL` | PostgreSQL connection string | **Yes** |

**Important:** Database requires the `uuid-ossp` extension:
```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

**Example:**
```yaml
gallery-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=gallery_api;Username=gallery;Password=PASSWORD;"
```

#### OAuth2/OIDC

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `gallery-api.env.Authorization__Authority` | Identity provider URL | **Yes** | `https://identity.example.com` |
| `gallery-api.env.Authorization__AuthorizationUrl` | Authorization endpoint | **Yes** | `https://identity.example.com/connect/authorize` |
| `gallery-api.env.Authorization__TokenUrl` | Token endpoint | **Yes** | `https://identity.example.com/connect/token` |
| `gallery-api.env.Authorization__AuthorizationScope` | OAuth scopes | **Yes** | `gallery` |
| `gallery-api.env.Authorization__ClientId` | OAuth client ID | **Yes** | `gallery.swagger` |
| `gallery-api.env.Authorization__ClientName` | Client display name | No | `Gallery API Swagger` |

#### CORS

| Parameter | Description | Default |
|-----------|-------------|---------|
| `gallery-api.env.CorsPolicy__Origins__0` | Allowed CORS origin (typically Gallery UI) | `https://gallery.example.com` |

### Gallery UI

```yaml
gallery-ui:
  settingsYaml:
    ApiUrl: https://gallery.example.com
    OIDCSettings:
      authority: https://identity.example.com/
      client_id: gallery-ui
      redirect_uri: https://gallery.example.com/auth-callback
      post_logout_redirect_uri: https://gallery.example.com
      response_type: code
      scope: openid profile gallery
      automaticSilentRenew: true
      silent_redirect_uri: https://gallery.example.com/auth-callback-silent
    AppTitle: Gallery
    AppTopBarHexColor: "#2d69b4"
    AppTopBarHexTextColor: "#FFFFFF"
    AppTopBarText: "Gallery - Exercise Information Sharing"
    AppTopBarImage: /assets/img/monitor-dashboard-white.png
    UseLocalAuthStorage: true
```

## Minimal Production Configuration

```yaml
gallery-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=gallery;Username=gallery;Password=PASSWORD;"
    Authorization__Authority: https://identity.example.com
    Authorization__AuthorizationUrl: https://identity.example.com/connect/authorize
    Authorization__TokenUrl: https://identity.example.com/connect/token
    Authorization__AuthorizationScope: "gallery"
    Authorization__ClientId: gallery-swagger
    CorsPolicy__Origins__0: "https://gallery.example.com"

gallery-ui:
  settingsYaml:
    ApiUrl: https://gallery.example.com
    OIDCSettings:
      authority: https://identity.example.com/
      client_id: gallery-ui
      redirect_uri: https://gallery.example.com/auth-callback
      response_type: code
      scope: openid profile gallery
```

## Ingress Configuration

Requires long timeouts for SignalR:

```yaml
gallery-api:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
      nginx.ingress.kubernetes.io/use-regex: "true"
    hosts:
      - host: gallery.example.com
        paths:
          - path: /(api|swagger/hubs)
            pathType: ImplementationSpecific
```

## Security Best Practices

1. **Secrets Management**: Use Kubernetes secrets for sensitive values
2. **TLS Everywhere**: Always use HTTPS in production
3. **CORS Configuration**: Only allow necessary origins

## References

- [Gallery Documentation](https://cmu-sei.github.io/crucible/gallery/)
- [Gallery API Repository](https://github.com/cmu-sei/Gallery.Api)
- [Gallery UI Repository](https://github.com/cmu-sei/Gallery.Ui)
