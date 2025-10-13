# CITE Helm Chart

[CITE (Collaborative Incident Threat Evaluator)](https://cmu-sei.github.io/crucible/cite/) is Crucible's application that enables participants from different organizations to evaluate, score, and comment on cyber incidents. CITE provides a situational awareness dashboard that allows teams to track their internal actions and roles.

This Helm chart deploys CITE with both API and UI components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (IdentityServer/Keycloak) for OAuth2/OIDC authentication

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install cite sei/cite -f values.yaml
```

## Configuration

### CITE API

#### Database

| Parameter | Description | Required |
|-----------|-------------|----------|
| `cite-api.env.ConnectionStrings__PostgreSQL` | PostgreSQL connection string | **Yes** |

**Important:** Database requires the `uuid-ossp` extension:
```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

**Example:**
```yaml
cite-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=cite_api;Username=cite;Password=PASSWORD;"
```

#### OAuth2/OIDC

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `cite-api.env.Authorization__Authority` | Identity provider URL | **Yes** | `https://identity.example.com` |
| `cite-api.env.Authorization__AuthorizationUrl` | Authorization endpoint | **Yes** | `https://identity.example.com/connect/authorize` |
| `cite-api.env.Authorization__TokenUrl` | Token endpoint | **Yes** | `https://identity.example.com/connect/token` |
| `cite-api.env.Authorization__AuthorizationScope` | OAuth scopes | **Yes** | `cite-api` |
| `cite-api.env.Authorization__ClientId` | OAuth client ID | **Yes** | `cite-api` |
| `cite-api.env.Authorization__ClientName` | Client display name | No | `CITE API` |

#### CORS

| Parameter | Description | Default |
|-----------|-------------|---------|
| `cite-api.env.CorsPolicy__Origins__0` | Allowed CORS origin (typically CITE UI) | `https://cite.example.com` |

#### Seed Data

Bootstrap initial data via ConfigMap:

```yaml
cite-api:
  conf:
    seed: |
      {
        "evaluations": [],
        "scoringModels": [],
        "teams": []
      }
```

#### Certificate Trust

Trust custom CA certificates:

```yaml
cite-api:
  certificateMap: "custom-ca-certs"
```

### CITE UI

```yaml
cite-ui:
  env:
    APP_BASEHREF: ""  # Set to /cite if hosting at subpath

  settingsYaml:
    ApiUrl: https://cite.example.com
    OIDCSettings:
      authority: https://identity.example.com/
      client_id: cite-ui
      redirect_uri: https://cite.example.com/auth-callback
      post_logout_redirect_uri: https://cite.example.com
      response_type: code
      scope: openid profile alloy-api player-api vm-api cite-api
      automaticSilentRenew: true
      silent_redirect_uri: https://cite.example.com/auth-callback-silent
    AppTitle: CITE
    AppTopBarHexColor: "#2d69b4"
    AppTopBarHexTextColor: "#FFFFFF"
    AppTopBarText: "CITE - Collaborative Incident Threat Evaluator"
    UseLocalAuthStorage: true
    DefaultScoringModelId: ""
    DefaultEvaluationId: ""
    DefaultTeamId: ""
```

**UI Configuration Notes:**
- `DefaultScoringModelId`: Pre-select a scoring model on load
- `DefaultEvaluationId`: Pre-select an evaluation on load
- `DefaultTeamId`: Pre-select a team on load

## Minimal Production Configuration

```yaml
cite-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=cite;Username=cite;Password=PASSWORD;"
    Authorization__Authority: https://identity.example.com
    Authorization__AuthorizationUrl: https://identity.example.com/connect/authorize
    Authorization__TokenUrl: https://identity.example.com/connect/token
    Authorization__AuthorizationScope: "cite-api"
    Authorization__ClientId: cite-api
    CorsPolicy__Origins__0: "https://cite.example.com"

cite-ui:
  settingsYaml:
    ApiUrl: https://cite.example.com
    OIDCSettings:
      authority: https://identity.example.com/
      client_id: cite-ui
      redirect_uri: https://cite.example.com/auth-callback
      response_type: code
      scope: openid profile cite-api
```

## Ingress Configuration

Requires long timeouts for SignalR:

```yaml
cite-api:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
      nginx.ingress.kubernetes.io/use-regex: "true"
    hosts:
      - host: cite.example.com
        paths:
          - path: /(api|swagger/hubs)
            pathType: ImplementationSpecific
```

## Security Best Practices

1. **Secrets Management**: Use Kubernetes secrets:
   ```yaml
   cite-api:
     existingSecret: "cite-secrets"
   ```

2. **TLS Everywhere**: Always use HTTPS in production

3. **CORS Configuration**: Only allow necessary origins

4. **Proxy Settings**: Configure if behind corporate proxy

## Integration with Crucible

CITE can integrate with other Crucible applications:
- **Alloy**: For event coordination
- **Player**: For view and team information
- **VM API**: For VM status

Include necessary scopes in OIDC configuration:
```yaml
scope: openid profile alloy-api player-api vm-api cite-api
```

## References

- [CITE Documentation](https://cmu-sei.github.io/crucible/cite/)
- [CITE API Repository](https://github.com/cmu-sei/CITE.Api)
- [CITE UI Repository](https://github.com/cmu-sei/CITE.Ui)
