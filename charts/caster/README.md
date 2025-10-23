# Caster Helm Chart

[Caster](https://cmu-sei.github.io/crucible/caster/) is the [Crucible](https://cmu-sei.github.io/crucible/) application that enables the coded design and deployment of cyber topologies. Using Caster Designs, content developers can avoid scripting Terraform/OpenTofu code by defining variables within pre-configured modules. Caster supports deployment to VMware vSphere, Proxmox, and Azure.

This Helm chart deploys Caster with both [API](https://github.com/cmu-sei/Caster.Api) and [UI](https://github.com/cmu-sei/Caster.Ui) components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (e.g., [Keycloak](https://www.keycloak.org/)) for OAuth2/OIDC authentication
- Internet access for Terraform plugin installation (or pre-cached plugins)

## Recommended Infrastructure Backends

VMware vSphere, Proxmox, or AWS/Azure cloud infrastructure are all supported options for infrastructure backends for Caster to target deploying workloads.

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install caster sei/caster -f values.yaml
```

## Caster API Configuration

The following settings are applied through `caster-api.env`. These Caster API settings reflect the application's [appsettings.conf](https://github.com/cmu-sei/Caster.Api/blob/main/src/Caster.Api/appsettings.json) which may contain more settings than are described here.

### Database Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `ConnectionStrings__PostgreSQL` | PostgreSQL connection string for the Caster API | `"Server=postgres;Port=5432;Database=caster_api;Username=caster_dbu;Password=PASSWORD;"` |

**Important:** Ensure the database has the `uuid-ossp` extension installed:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

### Authentication (OIDC)

| Setting | Description | Example |
|---------|-------------|---------|
| `Authorization__Authority` | Identity provider base URL | `https://identity.example.com` |
| `Authorization__AuthorizationUrl` | Authorization endpoint | `https://identity.example.com/connect/authorize` |
| `Authorization__TokenUrl` | Token endpoint | `https://identity.example.com/connect/token` |
| `Authorization__AuthorizationScope` | OAuth scope requested by the API | `caster-api` |
| `Authorization__ClientId` | OAuth client ID for the API (Swagger or interactive clients) | `caster-api` |

### Service Account (Player / VM API Integration)

| Setting | Description | Example |
|---------|-------------|---------|
| `Client__TokenUrl` | Token endpoint for the service account | `https://identity.example.com/connect/token` |
| `Client__ClientId` | Service account client ID | `caster-admin` |
| `Client__UserName` | Service account username | `"caster-sa"` |
| `Client__Password` | Service account password | `"PASSWORD"` |
| `Client__Scope` | Space-delimited scopes required for downstream APIs | `player-api vm-api` |

**Note:**

You can store sensitive credentials in a Kubernetes Secret and reference it via `caster-api.existingSecret`.

### Player Integration

The preferred way to integrate Caster with [Player](https://cmu-sei.github.io/crucible/player/) is by using the [Crucible Terraform Provider](https://github.com/cmu-sei/terraform-provider-crucible). However, you can also configure the integration via these settings.

| Setting | Description | Example |
|---------|-------------|---------|
| `Player__VmApiUrl` | Base URL to the VM API | `https://vm.example.com` |
| `Player__VmConsoleUrl` | URL pattern for VM console access | `https://console.example.com/vm/{id}/console` |

### Terraform Configuration

| Setting | Description | Example |
|---------|-------------|---------|
| `Terraform__DefaultVersion` | Default Terraform/OpenTofu version used for plans | `1.5.7` |
| `Terraform__GitlabApiUrl` | GitLab API endpoint for state projects | `https://gitlab.example.com/api/v4/` |
| `Terraform__GitlabToken` | GitLab access token with `api` scope | `glpat-xxxxxxxxxxxxxxxxxxxx` |
| `Terraform__GitlabGroupId` | GitLab group ID that will hold Terraform modules | `42` |
| `Terraform__PluginDirectory` | Optional path containing pre-staged providers (set to `""` when using `terraformrc`) | `""` |

> **GitLab prerequisites:** create a dedicated group for Caster projects, generate a token with `api` scope, and confirm the token has access to the group.

#### Terraform Installation

| Setting | Description | Example |
|---------|-------------|---------|
| `SKIP_TERRAFORM_INSTALLATION` | Skip automatic Terraform download and rely on pre-installed binaries | `true` |

- Default value is `false`. When `false`, Caster downloads Terraform and providers at startup and requires internet access.
- For air-gapped environments, set to `true` and provide binaries via a mounted volume.

#### Terraform RC Configuration

Provide a custom Terraform RC file (e.g., for provider mirrors or caching).

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

When enabling a mirror, set `Terraform__PluginDirectory` to an empty string to avoid conflicting paths.

#### Terraform Providers

The following Terraform Providers are supported if you choose to use them.

##### [Crucible Terraform Provider (cmu-sei/crucible)](https://registry.terraform.io/providers/cmu-sei/crucible/latest)

| Setting | Description | Example |
|---------|-------------|---------|
| `SEI_CRUCIBLE_USERNAME` | Service account username for the provider | `caster-service` |
| `SEI_CRUCIBLE_PASSWORD` | Service account password | `"SECRET"` |
| `SEI_CRUCIBLE_AUTH_URL` | Authorization endpoint | `https://identity.example.com/connect/authorize` |
| `SEI_CRUCIBLE_TOK_URL` | Token endpoint | `https://identity.example.com/connect/token` |
| `SEI_CRUCIBLE_CLIENT_ID` | OAuth client ID | `player.provider` |
| `SEI_CRUCIBLE_CLIENT_SECRET` | OAuth client secret | `"SECRET"` |
| `SEI_CRUCIBLE_VM_API_URL` | VM API base URL | `https://vm.example.com/api/` |
| `SEI_CRUCIBLE_PLAYER_API_URL` | Player API base URL | `https://player.example.com/` |

##### [Azure Terraform Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)

| Setting | Description | Example |
|---------|-------------|---------|
| `ARM_CLIENT_ID` | Azure service principal client ID | `00000000-0000-0000-0000-000000000000` |
| `ARM_CLIENT_CERTIFICATE_PATH` | Path to service principal certificate mounted in the container | `/certs/azure-client.pem` |
| `ARM_TENANT_ID` | Azure tenant ID | `00000000-0000-0000-0000-000000000000` |
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID | `00000000-0000-0000-0000-000000000000` |
| `ARM_ENVIRONMENT` | Azure environment name | `AzurePublicCloud` |
| `ARM_SKIP_PROVIDER_REGISTRATION` | Skip automatic provider registration (`true` for restricted environments) | `false` |

Use `caster-api.certificateMap` to mount CA certificates required for Azure or other providers.

##### [VMware vSphere Provider](https://registry.terraform.io/providers/vmware/vsphere/latest)

| Setting | Description | Example |
|---------|-------------|---------|
| `VSPHERE_SERVER` | vCenter hostname | `vcenter.example.com` |
| `VSPHERE_USER` | vCenter username | `caster-service@vsphere.local` |
| `VSPHERE_PASSWORD` | vCenter password | `"PASSWORD"` |
| `VSPHERE_ALLOW_UNVERIFIED_SSL` | Allow self-signed certificates (prefer adding [CA certificates](#certificate-trust)) | `false` |

### Git Credentials

| Setting | Description | Example |
|---------|-------------|---------|
| `gitcredentials` | Credential helper entry written to `/root/.git-credentials` for Git operations | `https://git-access-token:glpat-xxxxxxxxxxxxxxxxxxxx@gitlab.example.com` |

### File Version Management

| Setting | Description | Example |
|---------|-------------|---------|
| `FileVersions__DaysToSaveAllUntaggedVersions` | Number of days to keep every untagged Terraform state version | `7` |
| `FileVersions__DaysToSaveDailyUntaggedVersions` | Number of days to retain daily snapshots of untagged versions | `31` |

### Proxy Settings

For environments with outbound proxies:

```yaml
caster-api:
  env:
    http_proxy: proxy.example.com:9000
    https_proxy: proxy.example.com:9000
    HTTP_PROXY: proxy.example.com:9000
    HTTPS_PROXY: proxy.example.com:9000
    NO_PROXY: .local
```

### Seed Data

Bootstrap initial users and roles at startup:

```yaml
caster-api:
  env:
    SeedData__Roles__0__name: "Rangetech Admin"
    SeedData__Roles__0__allPermissions: false
    SeedData__Roles__0__permissions__0: "CreateProjects"
    SeedData__Roles__0__permissions__1: "ViewProjects"
    SeedData__Roles__0__permissions__2: "EditProjects"
    SeedData__Roles__0__permissions__3: "ManageProjects"
    SeedData__Roles__0__permissions__4: "ImportProjects"
    SeedData__Roles__0__permissions__5: "LockFiles"
    SeedData__Users__0__id: "user-guid-1"
    SeedData__Users__0__name: "Rangetech Admin"
    SeedData__Users__0__role__name: "Rangetech Admin"
```

### Helm Deployment Configuration

#### Ingress
Configure the ingress to allow connections to the application (typically uses an ingress controller like [ingress-nginx](https://github.com/kubernetes/ingress-nginx)).

```yaml
caster-api:
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
      nginx.ingress.kubernetes.io/use-regex: "true"
    hosts:
      - host: caster.example.com
        paths:
          - path: /(api|swagger|hubs)
            pathType: ImplementationSpecific
```

#### Storage
Configure Caster to use a new Kubernetes Persistent Volume Claim to store uploaded files and application working directories (see the Kubernetes documentation for creating [Persistent Volumes and Persistent Volume Claims](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)).

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

- Without storage, an `emptyDir` volume is used and data is lost on restart.

#### Certificate Trust

Mount custom CA certificates to the container trust store:

```yaml
caster-api:
  certificateMap: "custom-ca-certs"
```

Certificates are mounted to `/usr/local/share/ca-certificates`.

## Caster UI Configuration

| Setting | Description | Example |
|---------|-------------|---------|
| `APP_BASEHREF` | Set when hosting the UI from a subpath | `"/caster"` |

Use `settingsYaml` to configure settings for the Angular UI application.

| Setting | Description | Example |
|---------|-------------|---------|
| `ApiUrl` | Base URL for the Caster API | `https://caster.example.com` |
| `OIDCSettings.authority` | OIDC authority URL | `https://identity.example.com/` |
| `OIDCSettings.client_id` | OAuth client ID for the Caster UI | `caster-ui` |
| `OIDCSettings.redirect_uri` | Callback URL after login | `https://caster.example.com/auth-callback/` |
| `OIDCSettings.post_logout_redirect_uri` | URL users return to after logout | `https://caster.example.com/` |
| `OIDCSettings.response_type` | OAuth response type | `code` |
| `OIDCSettings.scope` | Space-delimited scopes requested during login | `openid profile email caster-api` |
| `OIDCSettings.automaticSilentRenew` | Enables background token renewal | `true` |
| `OIDCSettings.silent_redirect_uri` | URI for silent token renewal callbacks | `https://caster.example.com/auth-callback-silent/` |
| `UseLocalAuthStorage` | Persist auth state in browser local storage | `true` |


## Troubleshooting

### Terraform Installation Failures
- Confirm outbound internet access when `SKIP_TERRAFORM_INSTALLATION` is `false`.
- Configure proxy variables when operating behind a firewall.
- For air-gapped environments, pre-install Terraform binaries and providers, then set `SKIP_TERRAFORM_INSTALLATION: true`.
- Review pod startup logs for download errors.

### GitLab Connection Issues
- Verify the API endpoint in `Terraform__GitlabApiUrl` is reachable from the pod.
- Test connectivity manually: `curl -H "PRIVATE-TOKEN: $TOKEN" $GITLAB_API_URL/groups/$GROUP_ID`.
- Ensure the GitLab token includes the `api` scope and has access to the target group.
- Confirm `Terraform__GitlabGroupId` matches the GitLab group where projects are created.
- Check the `gitcredentials` value for correct formatting (`https://user:token@gitlab...`).

### vSphere Connection Failures
- Confirm `VSPHERE_SERVER` is reachable from the pod.
- Test connectivity from a pod: `curl -k https://$VSPHERE_SERVER/sdk`.
- Validate the credentials supplied in `VSPHERE_USER` and `VSPHERE_PASSWORD`.
- For self-signed certificates, set `VSPHERE_ALLOW_UNVERIFIED_SSL: true`.

### Terraform Execution Failures
- Verify the specified Terraform version exists: `terraform version`.
- Ensure required providers are available via direct download or mirrors.
- Inspect Caster API pod logs for execution errors.
- Confirm the storage volume is persistent and writable.
- Validate provider environment variables (e.g., Azure, Crucible) are set correctly.

### Player / VM API Integration Issues
- Verify the URLs provided in `Player__VmApiUrl` (and `Player__VmConsoleUrl`, if used) are reachable.
- Confirm the service account credentials (`Client__*`) are correct and scoped appropriately.
- Ensure the requested scopes include the APIs you intend to call (`player-api`, `vm-api`).

### State File Issues
- Configure persistent storage to avoid data loss (avoid `emptyDir` for production).
- Check GitLab permissions for the token used by Caster.
- Review Terraform backend configuration within designs.

## Air-Gapped Deployment

To operate without external network access:

1. Set `SKIP_TERRAFORM_INSTALLATION: true` and mount pre-installed Terraform binaries and providers.
2. Use `terraformrc` to point to filesystem mirrors for providers and modules.
3. Preload container images and publish them to an internal registry.
4. Provide an internal GitLab instance for state storage and repository cloning.

## References

- [Caster Documentation](https://cmu-sei.github.io/crucible/caster/)
- [Caster API Repository](https://github.com/cmu-sei/Caster.Api)
- [Caster UI Repository](https://github.com/cmu-sei/Caster.Ui)
- [Crucible Terraform Provider](https://registry.terraform.io/providers/cmu-sei/crucible/latest)
