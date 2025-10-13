# Caster Helm Chart

[Caster](https://cmu-sei.github.io/crucible/caster/) is Crucible's application that enables the "coded" design and deployment of cyber topologies. Using Caster Designs, content developers can avoid scripting Terraform/OpenTofu code by defining variables within pre-configured modules. Caster supports deployment to VMware vSphere, Proxmox, and Azure.

This Helm chart deploys Caster with both API and UI components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (IdentityServer/Keycloak) for OAuth2/OIDC authentication
- GitLab instance for Terraform state storage
- VMware vSphere, Proxmox, or Azure infrastructure
- Internet access for Terraform plugin installation (or pre-cached plugins)

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install caster sei/caster -f values.yaml
```

## Overview

Caster manages infrastructure-as-code deployments using Terraform/OpenTofu. It provides:
- Web-based interface for managing Terraform workspaces
- Version control integration with GitLab
- Variable templating for simplified topology design
- Integration with Crucible Player for VM management

## Configuration

### Caster API Configuration

#### Database

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `caster-api.env.ConnectionStrings__PostgreSQL` | PostgreSQL connection string | **Yes** | Example shown |

**Important:** Database requires the `uuid-ossp` extension:
```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

**Example:**
```yaml
caster-api:
  env:
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=caster_api;Username=caster_dbu;Password=PASSWORD;"
```

#### OAuth2/OIDC Authentication

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `caster-api.env.Authorization__Authority` | Identity provider base URL | **Yes** | `https://identity.example.com` |
| `caster-api.env.Authorization__AuthorizationUrl` | Authorization endpoint | **Yes** | `https://identity.example.com/connect/authorize` |
| `caster-api.env.Authorization__TokenUrl` | Token endpoint | **Yes** | `https://identity.example.com/connect/token` |
| `caster-api.env.Authorization__AuthorizationScope` | OAuth scopes | **Yes** | `caster-api` |
| `caster-api.env.Authorization__ClientId` | OAuth client ID | **Yes** | `caster-api-dev` |

#### Service Account (for Player/VM API integration)

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `caster-api.env.Client__TokenUrl` | Token endpoint for service account | **Yes** | `https://identity.example.com/connect/token` |
| `caster-api.env.Client__ClientId` | Service account client ID | **Yes** | `caster-admin` |
| `caster-api.env.Client__UserName` | Service account username | **Yes** | `""` |
| `caster-api.env.Client__Password` | Service account password | **Yes** | `""` |
| `caster-api.env.Client__Scope` | Service account scopes | **Yes** | `player-api vm-api` |

**Note:** Store credentials in Kubernetes secrets using `existingSecret`.

#### Player Integration

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `caster-api.env.Player__VmApiUrl` | VM API base URL | **Yes** | `https://vm.example.com` |
| `caster-api.env.Player__VmConsoleUrl` | VM console URL pattern | No | `https://console.example.com/vm/{id}/console` |

**Example:**
```yaml
caster-api:
  env:
    Player__VmApiUrl: "https://vm.example.com"
    Player__VmConsoleUrl: "https://console.example.com/vm/{id}/console"
```

#### Terraform Configuration

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `caster-api.env.Terraform__DefaultVersion` | Default Terraform version | No | `0.14.0` |
| `caster-api.env.Terraform__GitlabApiUrl` | GitLab API endpoint | **Yes** | `https://gitlab.example.com/api/v4/` |
| `caster-api.env.Terraform__GitlabToken` | GitLab access token | **Yes** | Example token |
| `caster-api.env.Terraform__GitlabGroupId` | GitLab group ID for projects | **Yes** | `6` |

**GitLab Setup:**
1. Create a GitLab group for Caster projects
2. Generate a personal access token with `api` scope
3. Note the group ID from GitLab UI

**Example:**
```yaml
caster-api:
  env:
    Terraform__DefaultVersion: "1.5.7"
    Terraform__GitlabApiUrl: "https://gitlab.example.com/api/v4/"
    Terraform__GitlabToken: "glpat-xxxxxxxxxxxxxxxxxxxx"
    Terraform__GitlabGroupId: 42
```

#### Terraform Installation

| Parameter | Description | Default |
|-----------|-------------|---------|
| `caster-api.env.SKIP_TERRAFORM_INSTALLATION` | Skip automatic Terraform installation | `false` |

**Important:**
- By default, Caster installs Terraform and plugins on startup
- Requires internet access to download from terraform.io and registry.terraform.io
- For air-gapped environments, set to `true` and provide pre-installed binaries

#### Git Credentials

| Parameter | Description | Default |
|-----------|-------------|---------|
| `caster-api.gitcredentials` | Git credentials for GitLab access | Template shown |

**Format:** `https://git-access-token:TOKEN@gitlab.example.com`

**Example:**
```yaml
caster-api:
  gitcredentials: "https://git-access-token:glpat-xxxxxxxxxxxxxxxxxxxx@gitlab.example.com"
```

**Note:** This is written to `/root/.git-credentials` for Git operations.

#### Terraform RC Configuration

For custom Terraform provider caching or mirrors:

```yaml
caster-api:
  terraformrc:
    enabled: true
    value: |
      plugin_cache_dir = "/terraform/plugin-cache"
      provider_installation {
          filesystem_mirror {
              path = "/terraform/plugins/linux_amd64"
              include = []
          }
          direct {
              include = []
          }
      }
```

**Note:** When enabled, explicitly set `Terraform__PluginDirectory` to empty string.

#### File Version Management

| Parameter | Description | Default |
|-----------|-------------|---------|
| `caster-api.env.FileVersions__DaysToSaveAllUntaggedVersions` | Keep all versions for N days | `7` |
| `caster-api.env.FileVersions__DaysToSaveDailyUntaggedVersions` | Keep daily snapshots for N days | `31` |

Controls retention of Terraform state file versions.

#### CORS Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `caster-api.env.CorsPolicy__Origins__0` | Allowed CORS origin (typically Caster UI) | `https://caster.example.com` |

#### Proxy Settings

For environments requiring HTTP proxies:

```yaml
caster-api:
  env:
    http_proxy: proxy.example.com:9000
    https_proxy: proxy.example.com:9000
    HTTP_PROXY: proxy.example.com:9000
    HTTPS_PROXY: proxy.example.com:9000
    NO_PROXY: .local
```

### VMware vSphere Configuration

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `caster-api.env.VSPHERE_SERVER` | vCenter hostname | **Yes** | `vcenter.example.com` |
| `caster-api.env.VSPHERE_USER` | vCenter username | **Yes** | `caster-account@vsphere.local` |
| `caster-api.env.VSPHERE_PASSWORD` | vCenter password | **Yes** | `""` |
| `caster-api.env.VSPHERE_ALLOW_UNVERIFIED_SSL` | Allow self-signed certs | No | `true` |

**Example:**
```yaml
caster-api:
  env:
    VSPHERE_SERVER: vcenter.example.com
    VSPHERE_USER: caster-service@vsphere.local
    VSPHERE_PASSWORD: "SECRET"
    VSPHERE_ALLOW_UNVERIFIED_SSL: false  # Set false with valid certs
```

### Terraform Crucible Provider

For using the [Crucible Terraform Provider](https://registry.terraform.io/providers/cmu-sei/crucible/latest):

| Parameter | Description | Required |
|-----------|-------------|----------|
| `caster-api.env.SEI_CRUCIBLE_USERNAME` | Service account username | **Yes** |
| `caster-api.env.SEI_CRUCIBLE_PASSWORD` | Service account password | **Yes** |
| `caster-api.env.SEI_CRUCIBLE_AUTH_URL` | Authorization endpoint | **Yes** |
| `caster-api.env.SEI_CRUCIBLE_TOK_URL` | Token endpoint | **Yes** |
| `caster-api.env.SEI_CRUCIBLE_CLIENT_ID` | OAuth client ID | **Yes** |
| `caster-api.env.SEI_CRUCIBLE_CLIENT_SECRET` | OAuth client secret | **Yes** |
| `caster-api.env.SEI_CRUCIBLE_VM_API_URL` | VM API URL | **Yes** |
| `caster-api.env.SEI_CRUCIBLE_PLAYER_API_URL` | Player API URL | **Yes** |

**Example:**
```yaml
caster-api:
  env:
    SEI_CRUCIBLE_USERNAME: "caster-service"
    SEI_CRUCIBLE_PASSWORD: "SECRET"
    SEI_CRUCIBLE_AUTH_URL: https://identity.example.com/connect/authorize
    SEI_CRUCIBLE_TOK_URL: https://identity.example.com/connect/token
    SEI_CRUCIBLE_CLIENT_ID: player.provider
    SEI_CRUCIBLE_CLIENT_SECRET: "SECRET"
    SEI_CRUCIBLE_VM_API_URL: https://vm.example.com/api/
    SEI_CRUCIBLE_PLAYER_API_URL: https://player.example.com/
```

### Terraform Identity Provider

For using the [Identity Terraform Provider](https://registry.terraform.io/providers/cmu-sei/identity/latest):

| Parameter | Description | Required |
|-----------|-------------|----------|
| `caster-api.env.SEI_IDENTITY_TOK_URL` | Identity token endpoint | **Yes** |
| `caster-api.env.SEI_IDENTITY_API_URL` | Identity API endpoint | **Yes** |
| `caster-api.env.SEI_IDENTITY_CLIENT_ID` | OAuth client ID | **Yes** |
| `caster-api.env.SEI_IDENTITY_CLIENT_SECRET` | OAuth client secret | **Yes** |

**Example:**
```yaml
caster-api:
  env:
    SEI_IDENTITY_TOK_URL: https://identity.example.com/connect/token
    SEI_IDENTITY_API_URL: https://id.example.com/api/
    SEI_IDENTITY_CLIENT_ID: terraform-identity-provider
    SEI_IDENTITY_CLIENT_SECRET: "SECRET"
```

### Azure Provider

For using the [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest):

| Parameter | Description |
|-----------|-------------|
| `caster-api.env.ARM_CLIENT_ID` | Azure client ID |
| `caster-api.env.ARM_CLIENT_CERTIFICATE_PATH` | Path to client certificate |
| `caster-api.env.ARM_TENANT_ID` | Azure tenant ID |
| `caster-api.env.ARM_SUBSCRIPTION_ID` | Azure subscription ID |
| `caster-api.env.ARM_ENVIRONMENT` | Azure environment |
| `caster-api.env.ARM_SKIP_PROVIDER_REGISTRATION` | Skip provider registration |

**Note:** Use `certificateMap` to mount certificates to `/usr/local/share/ca-certificates`.

### Seed Data

Bootstrap initial users and permissions:

```yaml
caster-api:
  env:
    SeedData__Users__0__id: "user-guid-1"
    SeedData__Users__0__name: "Admin User"
    SeedData__Users__1__id: "user-guid-2"
    SeedData__Users__1__name: "Developer User"

    SeedData__UserPermissions__0__UserId: "user-guid-1"
    SeedData__UserPermissions__0__PermissionId: "permission-guid-1"
```

### Storage Configuration

Caster requires persistent storage for Terraform state and working directories:

```yaml
caster-api:
  storage:
    # Option 1: Use existing PVC
    existing: "caster-storage"

    # Option 2: Create new PVC
    size: "50Gi"
    mode: ReadWriteOnce
    class: "default"
```

**Important:**
- Without storage, `emptyDir` is used (data lost on restart)
- Multi-replica deployments may require `ReadWriteMany`

### Certificate Trust

Trust custom CA certificates:

```yaml
caster-api:
  certificateMap: "custom-ca-certs"
```

Certificates from the ConfigMap are mounted to `/usr/local/share/ca-certificates`.

## Caster UI Configuration

```yaml
caster-ui:
  env:
    APP_BASEHREF: ""  # Set to /caster if hosting at subpath

  settingsYaml:
    ApiUrl: https://caster.example.com
    OIDCSettings:
      authority: https://identity.example.com/
      client_id: caster-ui-dev
      redirect_uri: https://caster.example.com/auth-callback/
      post_logout_redirect_uri: https://caster.example.com/
      response_type: code
      scope: openid profile email caster-api
      automaticSilentRenew: true
      silent_redirect_uri: https://caster.example.com/auth-callback-silent/
    UseLocalAuthStorage: true
```

## Minimal Production Configuration

```yaml
caster-api:
  env:
    # Database
    ConnectionStrings__PostgreSQL: "Server=postgres;Port=5432;Database=caster;Username=caster;Password=PASSWORD;"

    # OAuth
    Authorization__Authority: https://identity.example.com
    Authorization__AuthorizationUrl: https://identity.example.com/connect/authorize
    Authorization__TokenUrl: https://identity.example.com/connect/token
    Authorization__AuthorizationScope: "caster-api"
    Authorization__ClientId: caster-api

    # Service Account
    Client__TokenUrl: https://identity.example.com/connect/token
    Client__ClientId: caster-service
    Client__UserName: caster-sa
    Client__Password: "PASSWORD"
    Client__Scope: "player-api vm-api"

    # Player Integration
    Player__VmApiUrl: "https://vm.example.com"

    # Terraform
    Terraform__DefaultVersion: "1.5.7"
    Terraform__GitlabApiUrl: "https://gitlab.example.com/api/v4/"
    Terraform__GitlabToken: "glpat-xxxxxxxxxxxxxxxxxxxx"
    Terraform__GitlabGroupId: 42

    # vSphere
    VSPHERE_SERVER: vcenter.example.com
    VSPHERE_USER: caster@vsphere.local
    VSPHERE_PASSWORD: "PASSWORD"

    # CORS
    CorsPolicy__Origins__0: "https://caster.example.com"

  gitcredentials: "https://git-access-token:glpat-xxxxxxxxxxxxxxxxxxxx@gitlab.example.com"

  storage:
    size: "50Gi"

caster-ui:
  settingsYaml:
    ApiUrl: https://caster.example.com
    OIDCSettings:
      authority: https://identity.example.com/
      client_id: caster-ui
      redirect_uri: https://caster.example.com/auth-callback/
      response_type: code
      scope: openid profile email caster-api
```

## Ingress Configuration

The Caster API ingress requires long timeouts for Terraform operations:

```yaml
caster-api:
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: nginx
      nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
      nginx.ingress.kubernetes.io/use-regex: "true"
    hosts:
      - host: caster.example.com
        paths:
          - path: /(api|swagger|hubs)
            pathType: ImplementationSpecific
```

**Note:** Path pattern `/(api|swagger|hubs)` ensures API and SignalR routes are accessible.

## Troubleshooting

### Terraform Installation Failures
- Verify internet access if `SKIP_TERRAFORM_INSTALLATION: false`
- Check proxy settings if behind a corporate firewall
- For air-gapped environments, pre-install Terraform and set `SKIP_TERRAFORM_INSTALLATION: true`
- Review pod logs during startup for download errors

### GitLab Connection Issues
- Verify `Terraform__GitlabApiUrl` is accessible from the pod
- Check that `Terraform__GitlabToken` has `api` scope
- Ensure `Terraform__GitlabGroupId` exists and token has access
- Verify `gitcredentials` format is correct
- Test GitLab access: `curl -H "PRIVATE-TOKEN: $TOKEN" $GITLAB_API_URL/groups/$GROUP_ID`

### vSphere Connection Failures
- Verify `VSPHERE_SERVER` is accessible from the pod
- Check `VSPHERE_USER` credentials
- For self-signed certificates, ensure `VSPHERE_ALLOW_UNVERIFIED_SSL: true`
- Verify the service account has necessary vSphere permissions
- Test connection from pod: `curl -k https://$VSPHERE_SERVER/sdk`

### Terraform Execution Failures
- Check that default version is available: `terraform version`
- Verify required providers are installed
- Review Terraform logs in Caster API pod
- Check that workspace storage is persistent and writable
- Ensure environment variables for providers are set correctly

### Player/VM API Integration Issues
- Verify `Player__VmApiUrl` is accessible
- Check service account credentials (`Client__*` settings)
- Ensure service account has permissions in Player/VM API
- Verify scopes include `player-api` and `vm-api`

### State File Issues
- Ensure persistent storage is configured (not `emptyDir`)
- Check GitLab group has projects for state storage
- Verify Terraform backend configuration in designs
- Review GitLab project permissions for Caster token

## Security Best Practices

1. **Secrets Management**: Use Kubernetes secrets:
   ```yaml
   caster-api:
     existingSecret: "caster-secrets"
   ```

2. **GitLab Token**: Use project access tokens, not personal tokens

3. **Service Accounts**: Use dedicated service accounts with minimal permissions

4. **TLS Everywhere**: Always use HTTPS in production

5. **Terraform State**: Ensure GitLab projects have restricted access

6. **vSphere Permissions**: Grant only necessary permissions to Caster service account

7. **Network Isolation**: Consider network policies for Terraform execution

## Air-Gapped Deployment

For environments without internet access:

1. **Pre-install Terraform**:
   ```yaml
   caster-api:
     env:
       SKIP_TERRAFORM_INSTALLATION: true
   ```

2. **Provider Mirrors**: Use `terraformrc` for filesystem mirrors

3. **Container Images**: Pre-pull all required images

4. **GitLab**: Deploy internal GitLab instance

## References

- [Caster Documentation](https://cmu-sei.github.io/crucible/caster/)
- [Caster API Repository](https://github.com/cmu-sei/Caster.Api)
- [Caster UI Repository](https://github.com/cmu-sei/Caster.Ui)
- [Crucible Terraform Provider](https://registry.terraform.io/providers/cmu-sei/crucible/latest)
- [Identity Terraform Provider](https://registry.terraform.io/providers/cmu-sei/identity/latest)
