# CITE Helm Chart

[CITE (Collaborative Incident Threat Evaluator)](https://cmu-sei.github.io/crucible/cite/) is the [Crucible](https://cmu-sei.github.io/crucible/) application that enables participants from different organizations to evaluate, score, and comment on cyber incidents. CITE provides a situational awareness dashboard that allows teams to track their internal actions and roles.

This Helm chart deploys CITE with both [API](https://github.com/cmu-sei/CITE.Api) and [UI](https://github.com/cmu-sei/CITE.Ui) components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (e.g., [Keycloak](https://www.keycloak.org/)) for OAuth2/OIDC authentication

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install cite sei/cite -f values.yaml
```

## CITE API Configuration

The following are configured via the `cite-api.env` settings. These CITE API settings reflect the application's [appsettings.json](https://github.com/cmu-sei/CITE.Api/blob/development/Cite.Api/appsettings.json) which may contain more options than are described here.

### Database Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `ConnectionStrings__PostgreSQL` | PostgreSQL connection string | `Server=postgres;Port=5432;Database=cite;Username=cite;Password=PASSWORD;` |

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
| `Authorization__AuthorizationScope` | OAuth scope requested by the API | `cite-api` |
| `Authorization__ClientId` | OAuth client ID used by the API and interactive clients | `cite-api` |
| `Authorization__ClientName` | Display name for the client (optional) | `CITE` |

### Certificate Trust

Trust custom certificate authorities by referencing a Kubernetes ConfigMap that contains the CA bundle.

```yaml
cite-api:
  certificateMap: "custom-ca-certs"
```

### Helm Deployment Configuration

The following are configurations for the CITE API Helm Chart and application configurations that are configured outside of the `cite-api.env` section.

### Ingress

Configure the ingress to allow connections to the application (typically uses an ingress controller like [ingress-nginx](https://github.com/kubernetes/ingress-nginx)).

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

## CITE UI Configuration

Use ``settingsYaml` to configure the Angular UI application.

| Setting | Description | Example |
|---------|-------------|---------|
| `ApiUrl` | Base URL for the CITE API | `https://cite.example.com` |
| `OIDCSettings.authority` | OIDC authority URL | `https://identity.example.com/` |
| `OIDCSettings.client_id` | OAuth client ID for the CITE UI | `cite-ui` |
| `OIDCSettings.redirect_uri` | Callback URL after login | `https://cite.example.com/auth-callback` |
| `OIDCSettings.post_logout_redirect_uri` | URL users return to after logout | `https://cite.example.com` |
| `OIDCSettings.response_type` | OAuth response type | `code` |
| `OIDCSettings.scope` | Space-delimited scopes requested during login | `openid profile alloy-api player-api vm-api cite-api` |
| `OIDCSettings.automaticSilentRenew` | Enables background token renewal | `true` |
| `OIDCSettings.silent_redirect_uri` | URI for silent token renewal callbacks | `https://cite.example.com/auth-callback-silent` |
| `UseLocalAuthStorage` | Persist auth state in browser local storage | `true` |
| `AppTitle` | Browser/application title | `CITE` |
| `AppTopBarHexColor` | Hex color for the top bar background | `#2d69b4` |
| `AppTopBarHexTextColor` | Hex color for the top bar text | `#FFFFFF` |
| `AppTopBarText` | Banner text displayed in the top bar | `CITE - Collaborative Incident Threat Evaluator` |
| `DefaultScoringModelId` | Optional ID to pre-select a scoring model | `` |
| `DefaultEvaluationId` | Optional ID to pre-select an evaluation | `` |
| `DefaultTeamId` | Optional ID to pre-select a team | `` |

### Ingress

To host CITE from a subpath, set `env.APP_BASEHREF` and configure the ingress accordingly

```yaml
cite-ui:
  env:
    APP_BASEHREF: "/cite"
  ingress:
    enabled: true
    className: nginx
    hosts:
      - host: cite.example.com
        paths:
          - path: /cite
            pathType: ImplementationSpecific
    tls:
      - secretName: tls-secret-name # this tls secret should already exist
      hosts:
         - cite.example.com
```

## References

- [CITE Documentation](https://cmu-sei.github.io/crucible/cite/)
- [CITE API Repository](https://github.com/cmu-sei/CITE.Api)
- [CITE UI Repository](https://github.com/cmu-sei/CITE.Ui)
