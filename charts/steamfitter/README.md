# Steamfitter Helm Chart

[Steamfitter](https://cmu-sei.github.io/crucible/steamfitter/) is Crucible's application that enables the organization and execution of scenario tasks on virtual machines. It automates workflows and executes commands using StackStorm as its automation engine.

This Helm chart deploys Steamfitter with both API and UI components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (IdentityServer/Keycloak) for OAuth2/OIDC authentication
- StackStorm instance for task execution
- Player and VM API instances

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install steamfitter sei/steamfitter -f values.yaml
```

## Overview

Steamfitter manages scenario-based automation by:
- Organizing tasks into scenarios and sessions
- Scheduling task execution on VMs
- Integrating with StackStorm for workflow automation
- Coordinating with Player for VM and team information

## Configuration

### Steamfitter API

#### Database

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `steamfitter-api.env.ConnectionStrings__PostgreSQL` | PostgreSQL connection string | **Yes** | Example shown |

**Important:** Database requires the `uuid-ossp` extension:
```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

**Example:**
```yaml
steamfitter-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=steamfitter_api;Username=steamfitter;Password=PASSWORD;"
```

#### OAuth2/OIDC

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `steamfitter-api.env.Authorization__Authority` | Identity provider URL | **Yes** | `https://identity.example.com` |
| `steamfitter-api.env.Authorization__AuthorizationUrl` | Authorization endpoint | **Yes** | `https://identity.example.com/connect/authorize` |
| `steamfitter-api.env.Authorization__TokenUrl` | Token endpoint | **Yes** | `https://identity.example.com/connect/token` |
| `steamfitter-api.env.Authorization__AuthorizationScope` | OAuth scopes | **Yes** | `player-api steamfitter-api vm-api` |
| `steamfitter-api.env.Authorization__ClientId` | OAuth client ID | **Yes** | `steamfitter-api-dev` |
| `steamfitter-api.env.Authorization__ClientName` | Client display name | No | `"Steamfitter API"` |

#### Service Account (for VM API integration)

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `steamfitter-api.env.ResourceOwnerAuthorization__Authority` | Identity provider URL | **Yes** | `https://identity.example.com` |
| `steamfitter-api.env.ResourceOwnerAuthorization__ClientId` | Service account client ID | **Yes** | `steamfitter-api` |
| `steamfitter-api.env.ResourceOwnerAuthorization__UserName` | Service account username | **Yes** | `""` |
| `steamfitter-api.env.ResourceOwnerAuthorization__Password` | Service account password | **Yes** | `""` |
| `steamfitter-api.env.ResourceOwnerAuthorization__Scope` | Service account scopes | **Yes** | `vm-api` |

**Example:**
```yaml
steamfitter-api:
  env:
    ResourceOwnerAuthorization__Authority: https://identity.example.com
    ResourceOwnerAuthorization__ClientId: steamfitter-service
    ResourceOwnerAuthorization__UserName: steamfitter-sa
    ResourceOwnerAuthorization__Password: "PASSWORD"
    ResourceOwnerAuthorization__Scope: "vm-api"
```

#### Crucible Integration

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `steamfitter-api.env.ClientSettings__urls__playerApi` | Player API URL | **Yes** | `https://player.example.com/` |
| `steamfitter-api.env.ClientSettings__urls__vmApi` | VM API URL | **Yes** | `https://vm.example.com/` |

**Important:** URLs must include trailing slash.

**Example:**
```yaml
steamfitter-api:
  env:
    ClientSettings__urls__playerApi: "https://player.example.com/"
    ClientSettings__urls__vmApi: "https://vm.example.com/"
```

#### StackStorm Configuration

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `steamfitter-api.env.VmTaskProcessing__ApiType` | Task processing API type | **Yes** | `st2` |
| `steamfitter-api.env.VmTaskProcessing__ApiUsername` | StackStorm username | **Yes** | `st2admin` |
| `steamfitter-api.env.VmTaskProcessing__ApiPassword` | StackStorm password | **Yes** | `""` |
| `steamfitter-api.env.VmTaskProcessing__ApiBaseUrl` | StackStorm API URL | **Yes** | `https://stackstorm.example.com` |
| `steamfitter-api.env.VmTaskProcessing__ApiParameters__clusters` | vSphere cluster names (comma-separated) | No | `""` |

**StackStorm Setup:**
1. Deploy StackStorm instance
2. Create service account with API access
3. Configure workflows for task execution

**Example:**
```yaml
steamfitter-api:
  env:
    VmTaskProcessing__ApiType: st2
    VmTaskProcessing__ApiUsername: "st2admin"
    VmTaskProcessing__ApiPassword: "ST2_PASSWORD"
    VmTaskProcessing__ApiBaseUrl: "https://stackstorm.example.com"
    VmTaskProcessing__ApiParameters__clusters: "cluster1,cluster2"
```

#### CORS

| Parameter | Description | Default |
|-----------|-------------|---------|
| `steamfitter-api.env.CorsPolicy__Origins__0` | Allowed CORS origin (typically Steamfitter UI) | `https://steamfitter.example.com` |

#### Seed Data

Bootstrap users and permissions:

```yaml
steamfitter-api:
  env:
    SeedData__Users__0__id: "user-guid-from-identity"
    SeedData__Users__0__name: "Admin User"

    SeedData__UserPermissions__0__UserId: "user-guid"
    SeedData__UserPermissions__0__PermissionId: "permission-guid"
```

### Steamfitter UI

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

## Minimal Production Configuration

```yaml
steamfitter-api:
  env:
    # Database
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=steamfitter;Username=steamfitter;Password=PASSWORD;"

    # OAuth
    Authorization__Authority: https://identity.example.com
    Authorization__AuthorizationUrl: https://identity.example.com/connect/authorize
    Authorization__TokenUrl: https://identity.example.com/connect/token
    Authorization__AuthorizationScope: "player-api steamfitter-api vm-api"
    Authorization__ClientId: steamfitter-api

    # Service Account
    ResourceOwnerAuthorization__Authority: https://identity.example.com
    ResourceOwnerAuthorization__ClientId: steamfitter-service
    ResourceOwnerAuthorization__UserName: steamfitter-sa
    ResourceOwnerAuthorization__Password: "PASSWORD"
    ResourceOwnerAuthorization__Scope: "vm-api"

    # Crucible URLs
    ClientSettings__urls__playerApi: "https://player.example.com/"
    ClientSettings__urls__vmApi: "https://vm.example.com/"

    # StackStorm
    VmTaskProcessing__ApiType: st2
    VmTaskProcessing__ApiUsername: "st2admin"
    VmTaskProcessing__ApiPassword: "ST2_PASSWORD"
    VmTaskProcessing__ApiBaseUrl: "https://stackstorm.example.com"

    # CORS
    CorsPolicy__Origins__0: "https://steamfitter.example.com"

steamfitter-ui:
  settingsYaml:
    ApiUrl: https://steamfitter.example.com
    VmApiUrl: https://vm.example.com
    ApiPlayerUrl: https://player.example.com
    OIDCSettings:
      authority: https://identity.example.com
      client_id: steamfitter-ui
      redirect_uri: https://steamfitter.example.com/auth-callback/
      response_type: code
      scope: openid profile player-api vm-api steamfitter-api
```

## Ingress Configuration

Requires long timeouts for SignalR:

```yaml
steamfitter-api:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
      nginx.ingress.kubernetes.io/use-regex: "true"
    hosts:
      - host: steamfitter.example.com
        paths:
          - path: /(api|swagger|hubs)
            pathType: ImplementationSpecific
```

## Troubleshooting

### StackStorm Connection Issues
- Verify StackStorm URL is accessible from Steamfitter pod
- Check StackStorm credentials
- Ensure StackStorm API is properly configured
- Test connection: `curl -u st2admin:password https://stackstorm.example.com/api`

### Task Execution Failures
- Verify StackStorm workflows are installed
- Check VM API integration is working
- Ensure service account has VM API permissions
- Review StackStorm execution logs
- Verify cluster names are correct if specified

### Integration Issues
- Verify Player and VM API URLs are accessible
- Check service account credentials
- Ensure scopes include necessary APIs
- Review SignalR hub connections

### Database Connection Issues
- Verify database exists and is accessible
- Ensure `uuid-ossp` extension is installed
- Check connection string credentials

## Security Best Practices

1. **Secrets Management**: Use Kubernetes secrets:
   ```yaml
   steamfitter-api:
     existingSecret: "steamfitter-secrets"
   ```

2. **StackStorm Security**: Use dedicated StackStorm user with minimal permissions

3. **Service Account**: Use dedicated identity for VM operations

4. **TLS Everywhere**: Always use HTTPS in production

## StackStorm Integration

Steamfitter relies on StackStorm for executing commands on VMs. Typical workflow:

1. Steamfitter creates a scenario with scheduled tasks
2. At execution time, tasks are submitted to StackStorm
3. StackStorm workflows execute commands on target VMs
4. Results are returned to Steamfitter for tracking

**Required StackStorm Workflows:**
- VM command execution
- File operations
- Credential management

## References

- [Steamfitter Documentation](https://cmu-sei.github.io/crucible/steamfitter/)
- [Steamfitter API Repository](https://github.com/cmu-sei/Steamfitter.Api)
- [Steamfitter UI Repository](https://github.com/cmu-sei/Steamfitter.Ui)
- [StackStorm Documentation](https://docs.stackstorm.com/)
