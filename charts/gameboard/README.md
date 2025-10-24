# Gameboard Helm Chart

[Gameboard](https://cmu-sei.github.io/crucible/Gameboard/) is the [Crucible](https://cmu-sei.github.io/crucible/) application that provides a competition-ready user interface for running cybersecurity games and challenges.

This Helm chart deploys Gameboard with both [API](https://github.com/cmu-sei/gameboard) and [UI](https://github.com/cmu-sei/gameboard-ui) components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database
- Identity provider (e.g., [Keycloak](https://www.keycloak.org/)) for OAuth2/OIDC authentication
- Game Engine (typically [TopoMojo](https://cmu-sei.github.io/crucible/topomojo/)) for challenge deployment

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install gameboard sei/gameboard -f values.yaml
```

## Gameboard API Configuration

The following are configured via the `gameboard-api.env` settings. These Gameboard API settings reflect the application's [appsettings.conf](https://github.com/cmu-sei/Gameboard/blob/main/src/Gameboard.Api/appsettings.conf) which may contain more settings than are described here.

### Database Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `Database__ConnectionString` | PostgreSQL connection string | `Server=postgres;Port=5432;Database=gameboard;Username=gameboard;Password=PASSWORD;` |
| `Database__AdminId` | (Optional) Subject claim (GUID) of initial admin user (seeded on first deployment) | `<GUID>` |
| `Database__AdminName` | (Optional) Display name for initial admin user | `Administrator` |

### Core Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `Core__GameEngineUrl` | Base URL to the game engine (typically TopoMojo) |  `https://topomojo.example.com` |
| `Core__ChallengeDocUrl` | Base URL for challenge documentation and images (typically TopoMojo) | `https://topomojo.example.com` |
| `Core__GameEngineDeployBatchSize` | Number of challenge deployments to process concurrently.<br>Lower values can reduce infrastructure load when deploying many challenges concurrently, but may increase deploy times as challenges are queued in the next batch.<br>Default is no batching. | `6` |
| `Core__NameChangeIsEnabled` | Allow users to change their display names | `true` (Default) |
| `Core__NameChangeRequiresApproval` | Require admin approval for name changes | `true` (Default) |
| `Core__PracticeDefaultSessionLength` | Default practice session length in minutes | `60` (Default) |
| `Core__PracticeMaxSessionLength` | Maximum practice session length in minutes | `240` (Default) |

### Authentication (OIDC)

| Setting | Description | Example |
|---------|-------------|---------|
| `Oidc__Authority` | Identity provider base URL | `https://identity.example.com` |
| `Oidc__Audience` | Expected audience claim in tokens | `gameboard-api` |
| `Oidc__StoreUserEmails` | Store user emails in database | `false` (Default) |
| `Oidc__DefaultUserNameInferFromEmail` | Generate usernames from email | `false` (Default) |

#### Identity Provider Role Mapping

Gameboard can ingest roles from the identity provider (e.g. Keycloak). For example, an identity administrator can add roles like administrator, builder, or any custom role of their choosing and configure Gameboard's API to map those IDP roles to Gameboard roles.

Use the `Oidc__UserRolesClaimPath` setting to provide the JWT path to identity role assignments.

You can add any number of unique entries in this format to Gameboard API's configuration to map an identity role to a Gameboard role. For example, if you want to map users with the identity role "developer" to the Gameboard role "tester", you'd add an entry that looks like this: `Oidc__UserRolesClaimMap__developer = Tester`.

**If you specify any Oidc__UserRolesClaimMap__\* values in your application configuration, no default mappings will be applied.** If you don't specify any claim mappings, you'll automatically receive the default mappings.

| Setting | Description | Default |
|---------|-------------|---------|
| `Oidc__UserRolesClaimPath` | Path to roles in JWT | `realm_access.roles` (Keycloak default). <br> Set this to `""` to disable IDP role mapping. |
| `Oidc__UserRolesClaimMap__[identityRoleName]` | Identity role name to map to Gameboard role | Default mapping below. |

##### Default Mapping

```yaml
gameboard-api:
  env:
    Oidc__UserRolesClaimPath: "realm_access.roles"         # Keycloak default roles path
    Oidc__UserRolesClaimMap__administrator: Administrator
    Oidc__UserRolesClaimMap__director: Director
    Oidc__UserRolesClaimMap__member: Member
    Oidc__UserRolesClaimMap__support: Support
    Oidc__UserRolesClaimMap__tester: Tester
  ```

### Game Engine (TopoMojo) Integration

Gameboard requires integration with a Game Engine (typically [TopoMojo](https://cmu-sei.github.io/crucible/topomojo)) for ingesting "challenges" and managing virtual machine deployment.

#### Using OAuth2 Client Credentials (Recommended)

| Setting | Description | Example |
|---------|-------------|---------|
| `GameEngine__ClientId` | OAuth2 client ID for game engine access | `gameboard-client` |
| `GameEngine__ClientSecret` | OAuth2 client secret | `<secret>` |

**Important:**
- This client must be registered in your identity provider
- The client must have an audience matching the game engine's `Oidc__Audience` setting
- **Do not use** the legacy `Core__GameEngineClientId` and `Core__GameEngineClientSecret` settings when using OAuth

#### Legacy Game Engine Authentication (Deprecated)

**⚠️ Deprecated - use OAuth client credentials instead**

| Setting | Description | Example |
|---------|-------------|---------|
| `Core__GameEngineClientId` | Legacy Game Engine API key username | **Deprecated** |
| `Core__GameEngineClientSecret` | Legacy Game Engine API key | **Deprecated** |

##### Migration Note
If currently using API keys, create an OAuth client in your identity provider and switch to `GameEngine__ClientId/ClientSecret`.

### Helm Deployment Configuration

The following are configurations for the Gameboard API Helm Chart and application configurations that are configured outside of the `gameboard-api.env` section.

#### Static Content Settings

Static markdown documentation can be synchronized from a git repository:

| Setting | Description | Example |
|---------|-------------|---------|
| `giturl` | Git repository URL for markdown docs | `https://github.com/cmu-sei/helm-charts.git` |
| `gitbranch` | Branch to pull from | `main` |
| `pollInterval` | Minutes between git pulls | `5` |

#### Ingress
Configure the ingress to allow connections to the application (typically uses an ingress controller like [ingress-nginx](https://github.com/kubernetes/ingress-nginx)).

```yaml
gameboard-api:
  ingress:
    enabled: true
    className: nginx
    # optional ingress annotations to adjust ingress behavior
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: '3600'
      nginx.ingress.kubernetes.io/proxy-send-timeout: '3600'
      nginx.ingress.kubernetes.io/proxy-body-size: 30m

    hosts:
      - host: gameboard.example.com
        paths:
          - path: /gb/api
            pathType: ImplementationSpecific
          - path: /gb/hub
            pathType: ImplementationSpecific
          - path: /gb/img
            pathType: ImplementationSpecific
          - path: /gb/docs
            pathType: ImplementationSpecific
          - path: /gb/supportfiles
            pathType: ImplementationSpecific
    tls:
      - secretName: tls-secret-name # this tls secret should already exist
        hosts:
         - gameboard.example.com
```

#### Storage
Configure Gameboard to use a new/existing Kubernetes Persistent Volume Claim (see the Kubernetes documentation for creating [Persistent Volumes and Persistent Volume Claims](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)). The volume is used to store uploaded files and images from game configurations and support tickets.

```yaml
gameboard-api:
  storage:
    # Option 1: Use existing PVC
    existing: "gameboard-storage"

    # Option 2: Create new PVC
    size: "100Gi"
    mode: ReadWriteOnce
    class: "nfs-client"
```

#### Certificate Trust

Trust custom CA certificates.

| Setting | Description | Example |
|---------|-------------|---------|
| `cacert` | Inline CA certificate content | `<Certificate Content>` |
| `cacertSecret` | Existing secret with CA cert | `cert-secret` |
| `cacertSecretKey` | Key in secret containing cert | `ca.crt` |

## Gameboard UI Configuration

Use `settingsYaml` to configure settings for the Angular UI application.

| Setting | Description | Example |
|---------|-------------|----------|
| `appname` | Application display name shown in the UI and browser title. | `Gameboard` |
| `apphost` | Base URL for the Gameboard application | `/gb` |
| `tochost` | URL for table of contents/static markdown docs | `/gb/docs` |
| `custom_background` | Set the background color to a custom color | `custom-bg-black` |
| `unityclienthost` | Set the Unity Client Host for "External" game types that use a Unity game client (e.g., [Cubespace](https://github.com/cmu-sei/cubespace/)) | `https://gameboard.example.com/cubespace` |
| `oidc.client_id` | The OIDC client identifier used when authenticating the UI with the identity provider. | `gameboard-ui` |
| `oidc.authority` | The base URL of the identity provider (OIDC authority) that issues tokens. | `https://identity.example.com` |
| `oidc.redirect_uri` | The URL where users are redirected after a successful login via OIDC. | `https://gameboard.example.com/oidc` |
| `oidc.silent_redirect_uri` | The hidden iframe endpoint used for silently renewing tokens without user interaction. | `https://gameboard.example.com/oidc-silent.html` |
| `oidc.response_type` | The OAuth2 flow response type to request during login, typically `code` for PKCE authorization code flow. | `code` |
| `oidc.scope` | The list of identity and API scopes requested during authentication. | `openid profile gameboard-api` |
| `oidc.automaticSilentRenew` | Enables automatic background token refresh before expiration to maintain user sessions. | `true` |
| `oidc.useLocalStorage` | Stores authentication tokens in localStorage instead of sessionStorage to persist login across browser sessions. | `true` |

[ConsoleForge](https://github.com/cmu-sei/console-forge) is a shared library for interacting with Virtual Machine consoles in the web browser. As of [Gameboard version 3.33.0](https://github.com/cmu-sei/Gameboard/releases/tag/3.33.0), ConsoleForge is used for Gameboard consoles and requires additional configuration. The minimal configuration is below. Additional settings are available to view in the [ConsoleForge repository](https://github.com/cmu-sei/console-forge/blob/main/projects/console-forge/src/lib/config/console-forge-config.ts).

| Setting | Description | Example |
|---------|-------------|----------|
| `consoleForgeConfig.defaultConsoleType` | VM console type based on the hypervisor used by the Game Engine (`vmware` or `vnc` for Proxmox consoles) | `vnc` |

### Ingress

To host Gameboard from a subpath, set `basehref` and configure the ingress accordingly

```yaml
gameboard-ui:
  basehref: "/gb"
  ingress:
    enabled: true
    className: nginx
    hosts:
      - host: gameboard.example.com
        paths:
          - path: /gb
            pathType: ImplementationSpecific
    tls:
      - secretName: tls-secret-name # this tls secret should already exist
      hosts:
         - gameboard.example.com
```

### OpenGraph

You can configure OpenGraph for enhanced link preview support.

```yaml
gameboard-ui:
  openGraph: >
    <!-- Open Graph info for link previews -->
    <meta property="og:title" content="Gameboard" />
    <meta property="og:type" content="website" />
    <meta property="og:image" content="https://gameboard.example.com/gb/favicon.ico" />
    <meta property="og:url" content="https://gameboard.example.com/gb" />
    <meta property="og:description" content="Gameboard is a feature rich cyber competition platform." />
```

### Favicons

You can customize favicons using a URL to a tgz favicon bundle. The bundle's `favicon.html` will be merged into `index.html`.

```yaml
gameboard-ui:
  faviconsUrl: https://example.com/files/gameboard-favicons.tgz
```

## Troubleshooting

### Database Connection Issues
- Verify PostgreSQL is accessible from the pod
- Check connection string format and credentials
- Ensure database user has CREATE permissions for migrations

### Game Engine Connection Failures
- Verify `Core__GameEngineUrl` is accessible from the pod
- Check OAuth client credentials (`GameEngine__ClientId/ClientSecret`)
- Ensure the OAuth client has the correct audience matching the game engine
- Verify the service account has permissions in the game engine (TopoMojo)

### Authentication Issues
- Verify `Oidc__Authority` is accessible
- Check that `Oidc__Audience` matches the audience configured in the identity provider
- Ensure role mappings match your identity provider's role structure
- Verify CORS origins include the exact UI URL (protocol, domain, port)

### Challenge Deployment Problems
- Check `Core__GameEngineDeployBatchSize` - lower if overwhelming infrastructure
- Verify game engine (TopoMojo) is healthy and underlying hypervisor has resources available
- Check OAuth credentials have necessary permissions for creating gamespaces
- Review API logs for specific deployment errors

### Real-time Updates Not Working
- Verify SignalR hub path (`/hub`) is included in ingress
- Check ingress timeout settings (should be long for WebSockets)
- Ensure CORS `AllowCredentials` is `true`
- Verify WebSocket connections aren't blocked by firewall

## References

- [Gameboard Documentation](https://cmu-sei.github.io/crucible/Gameboard/)
- [Gameboard API Repository](https://github.com/cmu-sei/Gameboard)
- [Gameboard UI Repository](https://github.com/cmu-sei/Gameboard-ui)
- [ConsoleForge Repository](https://github.com/cmu-sei/console-forge)
- [TopoMojo Documentation](https://cmu-sei.github.io/crucible/topomojo) (typical game engine)
- [Cubespace Video Game](https://github.com/cmu-sei/cubespace/) (example Unity external game type)
