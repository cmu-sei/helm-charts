# Steamfitter Helm Chart

[Steamfitter](https://cmu-sei.github.io/crucible/steamfitter/) is the [Crucible](https://cmu-sei.github.io/crucible/) application that enables the organization and execution of scenario tasks on virtual machines. It automates workflows and executes commands using [StackStorm](https://stackstorm.com/) as its automation engine.

Steamfitter manages scenario-based automation by:
- Organizing tasks into scenarios and sessions
- Scheduling task execution on VMs
- Integrating with [StackStorm](https://stackstorm.com/) for workflow automation
- Coordinating with [Player](https://github.com/cmu-sei/Player.Api) for VM and team information

This Helm chart deploys Steamfitter with both [API](https://github.com/cmu-sei/steamfitter.api) and [UI](https://github.com/cmu-sei/steamfitter.ui) components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (e.g., Keycloak) for OAuth2/OIDC authentication
- [StackStorm](https://stackstorm.com/) instance for task execution
- Crucible [Player](https://github.com/cmu-sei/Player.Api) and [VM API](https://github.com/cmu-sei/vm.Api) instances

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install steamfitter sei/steamfitter -f values.yaml
```

## Steamfitter API Configuration

The following are configured via the `steamfitter-api.env` settings. These Steamfitter API settings reflect the application's [appsettings.json](https://github.com/cmu-sei/Steamfitter.Api/blob/development/Steamfitter.Api/appsettings.json) which may contain more settings than are described here.

### Database Settings

| Setting | Description | Default |
|---------|-------------|---------|
| `ConnectionStrings__PostgreSQL` | PostgreSQL connection string | Example shown |

**Important:**
Database requires the `uuid-ossp` extension:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

**Example:**
```yaml
steamfitter-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=steamfitter_api;Username=steamfitter;Password=PASSWORD;"
```

### Authentication (OIDC)

| Setting | Description | Default |
|---------|-------------|---------|
| `Authorization__Authority` | Identity provider URL for the user authentication flow | None |
| `Authorization__AuthorizationUrl` | Identity provider authorization endpoint for the user authentication flow | None |
| `Authorization__TokenUrl` | Identity provider token endpoint for the user authentication flow | None |
| `Authorization__AuthorizationScope` | OAuth scopes for the Steamfitter to request for the user authentication flow | `player-api steamfitter-api vm-api` |
| `Authorization__ClientId` | OAuth client ID | `steamfitter-api-dev` |
| `Authorization__ClientName` | OAuth client display name | `"Steamfitter API"` |

### Crucible Integration (Player and VM API)

Steamfitter needs to integrate with Crucible [Player](https://github.com/cmu-sei/Player.Api) and [VM API](https://github.com/cmu-sei/vm.Api)

| Setting | Description | Default |
|---------|-------------|---------|
| `ClientSettings__urls__playerApi` | Player API URL | `""` |
| `ClientSettings__urls__vmApi` | VM API URL | `""` |

**URLs must include trailing slash.**

Steamfitter needs to communicate to the Crucible [VM API](https://github.com/cmu-sei/vm.Api) application via a Resource Owner OAuth Flow for API-to-API communication using a service account. Use the following settings to configure the Resource Owner flow.

| Setting | Description | Default |
|---------|-------------|---------|
| `ResourceOwnerAuthorization__Authority` | Identity provider URL | `""` |
| `ResourceOwnerAuthorization__ClientId` | Service account client ID | `""` |
| `ResourceOwnerAuthorization__UserName` | Service account username | `""` |
| `ResourceOwnerAuthorization__Password` | Service account password | `""` |
| `ResourceOwnerAuthorization__Scope` | Service account scopes | `""` |

### StackStorm Integration

| Setting | Description | Default |
|---------|-------------|---------|
| `VmTaskProcessing__ApiType` | Task processing API type | `st2` |
| `VmTaskProcessing__ApiUsername` | StackStorm username | `st2admin` |
| `VmTaskProcessing__ApiPassword` | StackStorm password | `""` |
| `VmTaskProcessing__ApiBaseUrl` | StackStorm API URL | `https://stackstorm.example.com` |
| `VmTaskProcessing__ApiSettings__clusters` | vSphere cluster names (comma-separated) | `""` |

**StackStorm Setup**
1. Deploy StackStorm instance
2. Create service account with API access
3. Configure workflows for task execution

See the [StackStorm](https://docs.stackstorm.com/) documentation for more information.

### Ingress
Configure the ingress to allow connections to the application (typically uses an ingress controller like [ingress-nginx](https://github.com/kubernetes/ingress-nginx)).

```yaml
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      kubernetes.io/ingress.class: nginx
      nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
      nginx.ingress.kubernetes.io/use-regex: "true"
    hosts:
      - host: steamfitter.example.com
        paths:
          - path: /(api|swagger|hubs)
            pathType: ImplementationSpecific
    tls:
      - secretName: ""
        hosts:
          - example.com
```

## Steamfitter UI Configuration

| Setting | Description | Example |
|---------|-------------|---------|
| `APP_BASEHREF` | To host Steamfitter from a subpath | `"/steamfitter"` |

Use `settingsYaml` to configure settings for the Angular UI application.

| Setting                         | Description                                       | Example Value                         |
|---------------------------------|---------------------------------------------------|---------------------------------------|
| `ApiUrl`           | Base URL for the Steamfitter API                               | `https://steamfitter.example.com`                 |
| `VmApiUrl`         | Base URL for the VM API used by Steamfitter                    | `https://vm.example.com`                          |
| `ApiPlayerUrl`     | Base URL for the Player API interface                          | `https://player.example.com`                      |
| `OIDCSettings.authority` | URL of the identity provider (OIDC authority)            | `https://identity.example.com`                    |
| `OIDCSettings.client_id` | OAuth client ID used by the Steamfitter UI               | `steamfitter-ui-dev`                              |
| `OIDCSettings.redirect_uri` | URI where the identity provider redirects after login | `https://steamfitter.example.com/auth-callback/`  |
| `OIDCSettings.post_logout_redirect_uri` | URI users are redirected to after logout  | `https://steamfitter.example.com`                 |
| `OIDCSettings.response_type` | OAuth response type defining the authentication flow | `code`                                            |
| `OIDCSettings.scope`        | Space-delimited list of OAuth scopes requested        | `openid profile player-api vm-api steamfitter-api`|
| `OIDCSettings.automaticSilentRenew` | Enables automatic token renewal               | `true`                                            |
| `OIDCSettings.silent_redirect_uri` | URI for silent token renewal callbacks         | `https://steamfitter.example.com/auth-callback-silent/` |
| `UseLocalAuthStorage` | Whether authentication state is stored locally in browser   | `true`                                            |


**Example:**
```yaml
steamfitter-ui:
  env:
    APP_BASEHREF: ""  # Set to /steamfitter if hosting at subpath

  settingsYaml:
    ApiUrl: https://steamfitter.example.com
    VmApiUrl: https://vm.example.com
    ApiPlayerUrl: https://player.example.com
    OIDCSettings:
      authority: https://identity.example.com
      client_id: steamfitter-ui-dev
      redirect_uri: https://steamfitter.example.com/auth-callback/
      post_logout_redirect_uri: https://steamfitter.example.com
      response_type: code
      scope: openid profile player-api vm-api steamfitter-api
      automaticSilentRenew: true
      silent_redirect_uri: https://steamfitter.example.com/auth-callback-silent/
    UseLocalAuthStorage: true
```

## Troubleshooting

### StackStorm Connection Issues
- Verify StackStorm URL is accessible from Steamfitter pod
- Check StackStorm credentials
- Test connection: `curl -u st2admin:password https://stackstorm.example.com/api`

### Task Execution Failures
- Verify StackStorm workflows are installed
- Check VM API integration is working
- Ensure service account has VM API permissions
- Review StackStorm execution logs
- Verify StackStorm cluster names are correct (if specified)

### Integration Issues
- Verify Player and VM API URLs are accessible
- Check service account credentials
- Ensure scopes include necessary APIs

### Database Connection Issues
- Verify database exists and is accessible
- Ensure `uuid-ossp` extension is installed
- Check connection string credentials

## StackStorm Integration

Steamfitter relies on StackStorm for executing commands on VMs. Typical workflow:

1. Steamfitter creates a scenario with scheduled tasks
2. At execution time, tasks are submitted to StackStorm
3. StackStorm workflows execute commands on target VMs
4. Results are returned to Steamfitter for tracking

## References

- [Steamfitter Documentation](https://cmu-sei.github.io/crucible/steamfitter/)
- [Steamfitter API Repository](https://github.com/cmu-sei/Steamfitter.Api)
- [Steamfitter UI Repository](https://github.com/cmu-sei/Steamfitter.Ui)
- [StackStorm Documentation](https://docs.stackstorm.com/)
