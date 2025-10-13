# Gameboard Helm Chart

[Gameboard](https://cmu-sei.github.io/crucible/Gameboard/) is Crucible's application that provides game design capabilities and a competition-ready user interface for running cybersecurity games and challenges.

This Helm chart deploys Gameboard with both API and UI components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database
- Identity provider (IdentityServer/Keycloak) for OAuth2/OIDC authentication
- Game Engine (typically TopoMojo) for challenge deployment

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install gameboard sei/gameboard -f values.yaml
```

## Configuration

### Gameboard API Configuration

#### Core Settings (Required)

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `gameboard-api.env.Core__GameEngineUrl` | Base URL to the game engine API (typically TopoMojo) | **Yes** | *(not set – supply your game engine URL)* |
| `gameboard-api.env.Core__ChallengeDocUrl` | Base URL for challenge documentation and images | **Yes** | *(not set – supply your challenge doc URL)* |

**Example:**
```yaml
gameboard-api:
  env:
    Core__GameEngineUrl: https://topomojo.example.com/api
    Core__ChallengeDocUrl: https://topomojo.example.com/api
```

#### Core Settings (Optional Behavior)

The chart does not override these options; refer to the Gameboard.Api configuration for the latest defaults. Common knobs include:

| Parameter | Description |
|-----------|-------------|
| `gameboard-api.env.Core__GameEngineDeployBatchSize` | Number of challenge deployments to process concurrently |
| `gameboard-api.env.Core__NameChangeIsEnabled` | Allow users to change their display names |
| `gameboard-api.env.Core__NameChangeRequiresApproval` | Require admin approval for name changes |
| `gameboard-api.env.Core__PracticeDefaultSessionLength` | Default practice session length in minutes |
| `gameboard-api.env.Core__PracticeMaxSessionLength` | Maximum practice session length in minutes |

**Important Notes:**
- `GameEngineDeployBatchSize` controls how many VM environments are deployed simultaneously. Lower values reduce infrastructure load.
- Practice session settings control individual practice mode sessions, not competitive game sessions.

#### Database Configuration

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `gameboard-api.env.Database__ConnectionString` | PostgreSQL connection string | **Yes** | None |
| `gameboard-api.env.Database__AdminId` | Subject claim (GUID) of initial admin user | No | `""` |
| `gameboard-api.env.Database__AdminName` | Display name for initial admin user | No | `""` |

**Example:**
```yaml
gameboard-api:
  env:
    Database__ConnectionString: "Server=postgres;Port=5432;Database=gameboard;User ID=gb_user;Password=PASSWORD;"
    Database__AdminId: "f56c167f-d3f4-484a-8ee9-d230ceb5f734"
    Database__AdminName: "Admin"
```

**Notes:**
- The `AdminId` should match the subject claim from your identity provider
- Used to seed the first administrator account on initial deployment

#### Game Engine Authentication (OAuth Client Credentials)

**Modern approach using OAuth2 client credentials (recommended):**

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `gameboard-api.env.GameEngine__ClientId` | OAuth2 client ID for game engine access | **Yes** | None |
| `gameboard-api.env.GameEngine__ClientSecret` | OAuth2 client secret | **Yes** | None |

**Example:**
```yaml
gameboard-api:
  env:
    GameEngine__ClientId: gameboard-to-topomojo
    GameEngine__ClientSecret: "SECRET"
```

**Important:**
- This client must be registered in your identity provider
- The client must have an audience matching the game engine's `Oidc__Audience` setting
- **Do not use** the legacy `Core__GameEngineClientId` and `Core__GameEngineClientSecret` settings when using OAuth

#### Legacy Game Engine Authentication (Deprecated)

**⚠️ Deprecated - use OAuth client credentials instead:**

| Parameter | Description | Status |
|-----------|-------------|--------|
| `gameboard-api.env.Core__GameEngineClientId` | Legacy API key username | **Deprecated** |
| `gameboard-api.env.Core__GameEngineClientSecret` | Legacy API key | **Deprecated** |

**Migration Note:** If currently using API keys, create an OAuth client in your identity provider and switch to `GameEngine__ClientId/ClientSecret`.

#### OAuth/OIDC Configuration

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `gameboard-api.env.Oidc__Authority` | Identity provider base URL | **Yes** | *(not set – supply your IdP authority)* |
| `gameboard-api.env.Oidc__Audience` | Expected audience claim in tokens | **Yes** | *(not set – supply your audience)* |
| `gameboard-api.env.Oidc__UserRolesClaimPath` | Path to roles in JWT token | No | *(not set in chart; application default applies)* |
| `gameboard-api.env.Oidc__DefaultUserNameInferFromEmail` | Generate usernames from email | No | *(not set in chart; application default applies)* |
| `gameboard-api.env.Oidc__StoreUserEmails` | Store user emails in database | No | *(not set in chart; application default applies)* |

**Role Mapping:**

Map identity provider roles to Gameboard roles:

| Parameter | Gameboard Role | Description |
|-----------|----------------|-------------|
| `Oidc__UserRolesClaimMap__administrator` | Admin | Full system access |
| `Oidc__UserRolesClaimMap__director` | Director | Game/event management |
| `Oidc__UserRolesClaimMap__member` | Member | Standard participant |
| `Oidc__UserRolesClaimMap__support` | Support | Support staff access |
| `Oidc__UserRolesClaimMap__tester` | Tester | Testing/preview access |

**Example:**
```yaml
gameboard-api:
  env:
    Oidc__Authority: https://identity.example.com
    Oidc__Audience: gameboard-api
    Oidc__UserRolesClaimPath: realm_access.roles
    Oidc__UserRolesClaimMap__administrator: Admin
    Oidc__UserRolesClaimMap__director: Director
    Oidc__UserRolesClaimMap__member: Member
```

#### HTTP Headers & CORS

**CORS Configuration:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `gameboard-api.env.Headers__Cors__Origins__[0]` | Allowed CORS origins (array) | `""` |
| `gameboard-api.env.Headers__Cors__Methods__[0]` | Allowed HTTP methods (array) | `""` |
| `gameboard-api.env.Headers__Cors__Headers__[0]` | Allowed headers (array) | `""` |
| `gameboard-api.env.Headers__Cors__AllowAnyOrigin` | Allow any origin (`*`) | `false` |
| `gameboard-api.env.Headers__Cors__AllowAnyMethod` | Allow any HTTP method | `false` |
| `gameboard-api.env.Headers__Cors__AllowAnyHeader` | Allow any header | `false` |
| `gameboard-api.env.Headers__Cors__AllowCredentials` | Allow cookies and credentials | `false` |

**Example:**
```yaml
gameboard-api:
  env:
    Headers__Cors__Origins__0: https://gameboard.example.com
    Headers__Cors__AllowCredentials: true
```

**Forwarded Headers (for reverse proxy):**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `gameboard-api.env.Headers__Forwarding__ForwardLimit` | Max proxies in chain | `1` |
| `gameboard-api.env.Headers__Forwarding__TargetHeaders` | Which headers to process | `None` |
| `gameboard-api.env.Headers__Forwarding__KnownNetworks` | Trusted proxy networks (CIDR) | See example |
| `gameboard-api.env.Headers__Forwarding__KnownProxies` | Trusted proxy IPs | `::1` |

**Example:**
```yaml
gameboard-api:
  env:
    Headers__Forwarding__TargetHeaders: All
    Headers__Forwarding__KnownNetworks: "10.0.0.0/8 172.16.0.0/12 192.168.0.0/24"
```

**Security Headers:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `gameboard-api.env.Headers__Security__ContentSecurity` | Content-Security-Policy header | `default-src 'self' 'unsafe-inline'; img-src data: 'self'` |
| `gameboard-api.env.Headers__Security__XContentType` | X-Content-Type-Options header | `nosniff` |
| `gameboard-api.env.Headers__Security__XFrame` | X-Frame-Options header | `SAMEORIGIN` |
| `gameboard-api.env.Headers__LogHeaders` | Log all headers (debugging) | `false` |

#### Logging

| Parameter | Description | Default |
|-----------|-------------|---------|
| `gameboard-api.env.Logging__MinimumLogLevel` | Minimum log level (Trace, Debug, Information, Warning, Error, Critical) | `Information` |

For namespace-specific logging:
```yaml
gameboard-api:
  env:
    Logging__LogLevel__Default: Information
    Logging__LogLevel__Microsoft: Warning
    Logging__LogLevel__Gameboard: Debug
```

#### Storage Configuration

Static markdown documentation can be synchronized from a git repository:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `gameboard-api.giturl` | Git repository URL for markdown docs | `""` |
| `gameboard-api.gitbranch` | Branch to pull from | `""` |
| `gameboard-api.pollInterval` | Minutes between git pulls | `5` |

**Example:**
```yaml
gameboard-api:
  giturl: "https://github.com/org/gameboard-docs.git"
  gitbranch: "main"
  pollInterval: 10
```

Persistent storage for challenge docs and images:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `gameboard-api.storage.existing` | Use existing PVC | `""` |
| `gameboard-api.storage.size` | Size for new PVC (e.g., `10Gi`) | `""` |
| `gameboard-api.storage.mode` | Access mode | `ReadWriteOnce` |
| `gameboard-api.storage.class` | Storage class | `default` |

#### Certificate Trust

Trust custom CA certificates:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `gameboard-api.cacert` | Inline CA certificate content | `""` |
| `gameboard-api.cacertSecret` | Existing secret with CA cert | `""` |
| `gameboard-api.cacertSecretKey` | Key in secret containing cert | `ca.crt` |

### Gameboard UI Configuration

#### Basic Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `gameboard-ui.basehref` | Base path for UI routing | `""` |
| `gameboard-ui.openGraph` | HTML meta tags for social media previews | `""` |
| `gameboard-ui.faviconsUrl` | URL to .tgz bundle of favicons | `""` |

#### Application Settings

Configure via `settingsYaml` (recommended) or `settings` (legacy JSON string):

```yaml
gameboard-ui:
  settingsYaml:
    appname: Gameboard
    apphost: https://gameboard.example.com
    basehref: ""
    imghost: https://gameboard.example.com/img
    tochost: https://gameboard.example.com/doc
    supporthost: https://gameboard.example.com/supportfiles
    countdownStartSecondsAtMinute: 5
    custom_background: custom-bg-dark-gray

    oidc:
      client_id: gameboard-ui
      authority: https://identity.example.com
      redirect_uri: https://gameboard.example.com/oidc
      silent_redirect_uri: https://gameboard.example.com/oidc-silent.html
      response_type: code
      scope: openid profile gameboard-api
      loadUserInfo: true
      useLocalStorage: true

    consoleForgeConfig:
      defaultConsoleType: vmware  # or "proxmox"
      consoleBackgroundStyle: 'rgb(40, 40, 40)'
      showBrowserNotificationsOnConsoleEvents: true
      logThreshold: 2  # 0=trace, 1=debug, 2=warning, 3=error
      disabledFeatures:
        clipboard: false
        consoleScreenRecord: false
        manualConsoleReconnect: false
        networkDisconnection: false
      canvasRecording:
        autoDownloadCompletedRecordings: true
        frameRate: 25
        chunkLength: 1000
        maxDuration: 10000
        mimeType: 'video/webm'
      toolbar:
        component: ConsoleToolbarDefaultComponent
        disabled: false
```

**Key UI Settings:**

| Parameter | Description | Required |
|-----------|-------------|----------|
| `settingsYaml.appname` | Application display name | No |
| `settingsYaml.apphost` | Base URL for the Gameboard application | **Yes** |
| `settingsYaml.imghost` | URL for challenge images | **Yes** |
| `settingsYaml.tochost` | URL for table of contents/docs | No |
| `settingsYaml.oidc.client_id` | OAuth client ID for UI | **Yes** |
| `settingsYaml.oidc.authority` | Identity provider URL | **Yes** |
| `settingsYaml.oidc.scope` | OAuth scopes | **Yes** |
| `settingsYaml.consoleForgeConfig.defaultConsoleType` | VM console type (`vmware` or `proxmox`) | No |

## Minimal Production Configuration

```yaml
gameboard-api:
  env:
    # Core - Required
    Core__GameEngineUrl: https://topomojo.example.com/api
    Core__ChallengeDocUrl: https://topomojo.example.com/api

    # Database - Required
    Database__ConnectionString: "Server=postgres;Port=5432;Database=gameboard;User ID=gb_user;Password=PASSWORD;"
    Database__AdminId: "subject-claim-from-idp"
    Database__AdminName: "Administrator"

    # Game Engine OAuth - Required
    GameEngine__ClientId: gameboard-to-topomojo
    GameEngine__ClientSecret: "SECRET"

    # OIDC - Required
    Oidc__Authority: https://identity.example.com
    Oidc__Audience: gameboard-api
    Oidc__UserRolesClaimPath: realm_access.roles
    Oidc__UserRolesClaimMap__administrator: Admin
    Oidc__UserRolesClaimMap__member: Member

    # CORS - Required
    Headers__Cors__Origins__0: https://gameboard.example.com
    Headers__Cors__AllowCredentials: true

    # Forwarding - Required for reverse proxy
    Headers__Forwarding__TargetHeaders: All

  # Optional: Sync docs from git
  giturl: "https://github.com/org/gameboard-docs.git"
  gitbranch: "main"

gameboard-ui:
  settingsYaml:
    apphost: https://gameboard.example.com
    imghost: https://gameboard.example.com/img
    oidc:
      client_id: gameboard-ui
      authority: https://identity.example.com
      redirect_uri: https://gameboard.example.com/oidc
      silent_redirect_uri: https://gameboard.example.com/oidc-silent.html
      response_type: code
      scope: openid profile gameboard-api
```

## Ingress Configuration

The Gameboard API ingress should include paths for:
- `/api` - REST API endpoints
- `/hub` - SignalR real-time hubs
- `/img` - Challenge images
- `/docs` - Documentation files

```yaml
gameboard-api:
  ingress:
    enabled: true
    hosts:
      - host: gameboard.example.com
        paths:
          - path: /api
            pathType: ImplementationSpecific
          - path: /hub
            pathType: ImplementationSpecific
          - path: /img
            pathType: ImplementationSpecific
          - path: /docs
            pathType: ImplementationSpecific
```

For SignalR WebSocket support, ensure long timeouts:
```yaml
gameboard-api:
  ingress:
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
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
- Verify game engine (TopoMojo) is healthy and has resources
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
- [TopoMojo Documentation](https://cmu-sei.github.io/crucible/topomojo/about/) (typical game engine)
