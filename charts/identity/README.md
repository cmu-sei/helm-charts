# Identity Helm Chart

Identity is CMU SEI's OpenID Connect / OAuth 2.0 identity provider built on IdentityServer4. It provides authentication and authorization services for the Crucible ecosystem and other applications.

This Helm chart deploys Identity with both API and UI components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL or SQL Server database (for production)
- Redis (for multi-replica deployments)
- X.509 certificate for token signing (for production)

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install identity sei/identity -f values.yaml
```

## Quick Start Configurations

### Development (In-Memory Database)

```yaml
identity-api:
  env:
    Database__Provider: InMemory
    Branding__ApplicationName: "Identity Dev"
    Account__AdminEmail: admin@example.com
    Account__AdminPassword: "ChangeMe123!"
    Account__OverrideCode: "000000"  # Bypass 2FA for initial login
```

### Production

```yaml
identity-api:
  env:
    # Database
    Database__Provider: PostgreSQL
    Database__ConnectionString: "Server=postgres;Database=identity;Username=idsrv;Password=PASSWORD;"

    # Caching (multi-replica)
    Cache__RedisUrl: "redis:6379"
    Cache__Key: "idsrv"

    # Admin Account
    Account__AdminEmail: admin@example.com
    Account__AdminPassword: "SecurePassword123!"
    Account__OverrideCode: "123456"  # Remove after email configured

    # Authentication
    Account__Authentication__SigningCertificate: conf/signer.pfx
    Account__Authentication__SigningCertificatePassword: "CERT_PASSWORD"
    Account__Authentication__Require2FA: true

    # Email (required for 2FA)
    AppMail__Url: https://mail-relay.example.com
    AppMail__Key: "API_KEY"
    AppMail__From: noreply@identity.example.com

    # Branding
    Branding__ApplicationName: "My Organization Identity"
    Branding__UiHost: "/ui"

    # CORS
    Headers__Cors__Origins__0: https://identity.example.com
    Headers__Cors__AllowCredentials: true

    # Reverse Proxy
    Headers__Forwarding__TargetHeaders: All

  conf:
    signer: |  # Base64-encoded .pfx certificate
      MIIKfAIB...
```

## Configuration Reference

### Database

| Parameter | Description | Values | Default |
|-----------|-------------|--------|---------|
| `identity-api.env.Database__Provider` | Database backend | `InMemory`, `PostgreSQL`, `SqlServer` | `InMemory` |
| `identity-api.env.Database__ConnectionString` | Connection string | Connection string | `identity_db` |
| `identity-api.env.Database__SeedFile` | Path to seed data JSON | File path | `""` |

**Important:**
- `InMemory` is for development only
- Production must use `PostgreSQL` or `SqlServer`
- Seed file can pre-populate clients and resources

### Admin Account

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `identity-api.env.Account__AdminEmail` | Admin user email | **Recommended** | `""` |
| `identity-api.env.Account__AdminPassword` | Admin password | Required if AdminEmail set | `""` |
| `identity-api.env.Account__OverrideCode` | Master 2FA bypass code | Recommended | `""` |

**Important:**
- `OverrideCode` allows initial login before email is configured
- Acts as a universal 2FA code for development/emergency access
- Remove or change after production email is working

### Authentication & Security

#### Token Signing

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `identity-api.env.Account__Authentication__SigningCertificate` | Path to .pfx certificate | **Production** | `conf/signer.pfx` |
| `identity-api.env.Account__Authentication__SigningCertificatePassword` | Certificate password | If cert has password | `""` |

**Critical for Production:**
- Without a persistent certificate, all tokens are invalidated on pod restart
- Certificate should be provided via `identity-api.conf.signer` (base64-encoded)
- Must be PKCS#12 (.pfx) format with private key

**Generate a self-signed certificate:**
```bash
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 3650 -nodes
openssl pkcs12 -export -out signer.pfx -inkey key.pem -in cert.pem
base64 signer.pfx > signer.pfx.b64
```

#### Two-Factor Authentication

| Parameter | Description | Default |
|-----------|-------------|---------|
| `identity-api.env.Account__Authentication__Require2FA` | Enforce 2FA for all users | `true` |

**Requires:**
- Email configuration (`AppMail__*` settings)
- Or `Account__OverrideCode` for bypass during setup

#### Password Policy

| Parameter | Description | Default |
|-----------|-------------|---------|
| `identity-api.env.Account__Password__History` | Number of previous passwords to remember (0=disabled) | `0` |
| `identity-api.env.Account__Password__Age` | Password expiration in days (0=never) | `0` |

### Registration & User Management

| Parameter | Description | Default |
|-----------|-------------|---------|
| `identity-api.env.Account__Registration__AllowManual` | Allow user self-registration | `false` |
| `identity-api.env.Account__Registration__AllowedDomains` | Restrict registration to email domains (space/pipe delimited) | `""` |
| `identity-api.env.Account__Registration__AutoUniqueUsernames` | Add unique suffix to usernames | `true` |
| `identity-api.env.Account__Registration__AllowMultipleUsernames` | Allow users to add additional emails | `false` |

**Example:**
```yaml
identity-api:
  env:
    Account__Registration__AllowManual: true
    Account__Registration__AllowedDomains: "example.com|example.org"
```

### Email (AppMailRelay)

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `identity-api.env.AppMail__Url` | AppMailRelay service URL | **Yes** (for 2FA) | `""` |
| `identity-api.env.AppMail__Key` | API key for AppMailRelay | If relay requires | `""` |
| `identity-api.env.AppMail__From` | Sender email address | No | Uses relay default |

**Note:** Required for 2FA codes and password resets

### Branding

| Parameter | Description | Default |
|-----------|-------------|---------|
| `identity-api.env.Branding__ApplicationName` | Application display name | `Identity` |
| `identity-api.env.Branding__UiHost` | UI location | `/ui` |
| `identity-api.env.Branding__LogoUrl` | URL to logo image | `""` |
| `identity-api.env.Branding__IncludeSwagger` | Enable Swagger UI | `true` |

### Caching (Multi-Replica)

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `identity-api.env.Cache__RedisUrl` | Redis connection string | **Yes** (multi-replica) | `""` |
| `identity-api.env.Cache__Key` | Redis key prefix | No | `idsrv` |
| `identity-api.env.Cache__SharedFolder` | Alternative to Redis for data protection keys | No | `""` |

**Important:**
- **Required for production with multiple replicas**
- Ensures session consistency across pods
- Stores ASP.NET Core data protection keys

**Example:**
```yaml
identity-api:
  env:
    Cache__RedisUrl: "redis:6379"
    Cache__Key: "idsrv:"
```

### HTTP Headers & CORS

#### CORS

| Parameter | Description | Default |
|-----------|-------------|---------|
| `identity-api.env.Headers__Cors__Origins__0` | Allowed CORS origins (array) | `""` |
| `identity-api.env.Headers__Cors__AllowCredentials` | Allow cookies/credentials | `false` |

**Example:**
```yaml
identity-api:
  env:
    Headers__Cors__Origins__0: https://identity.example.com
    Headers__Cors__Origins__1: https://app.example.com
    Headers__Cors__AllowCredentials: true
```

#### Forwarded Headers (Reverse Proxy)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `identity-api.env.Headers__Forwarding__TargetHeaders` | Which headers to process | `All` |
| `identity-api.env.Headers__Forwarding__KnownNetworks` | Trusted proxy networks (CIDR) | Private ranges |

**Important for Production:**
```yaml
identity-api:
  env:
    Headers__Forwarding__TargetHeaders: All
```

#### Security Headers

| Parameter | Description | Default |
|-----------|-------------|---------|
| `identity-api.env.Headers__Security__ContentSecurity` | Content-Security-Policy | `default-src 'self'; frame-ancestors 'self'` |
| `identity-api.env.Headers__Security__XFrame` | X-Frame-Options | `SAMEORIGIN` |
| `identity-api.env.Headers__Security__XContentType` | X-Content-Type-Options | `nosniff` |

### Logging

| Parameter | Description | Default |
|-----------|-------------|---------|
| `identity-api.env.Logging__Console__DisableColors` | Disable ANSI colors in logs | `true` |
| `identity-api.env.Logging__LogLevel__Default` | Minimum log level | `Information` |

### Database Migrations

Run migrations as a separate job:

```yaml
identity-api:
  migrations:
    enabled: true
    Database__Provider: PostgreSQL
    Database__ConnectionString: "Server=postgres;Database=identity;Username=admin;Password=PASSWORD;"
```

### Configuration Files

Provide additional configuration via ConfigMaps:

| Parameter | Description | Format |
|-----------|-------------|--------|
| `identity-api.conf.issuers` | Trusted issuer configuration | JSON |
| `identity-api.conf.notice` | Login notice HTML | HTML |
| `identity-api.conf.terms` | Terms of service HTML | HTML |
| `identity-api.conf.trouble` | Troubleshooting help HTML | HTML |
| `identity-api.conf.seed` | Database seed data | JSON |
| `identity-api.conf.signer` | Token signing certificate | Base64 .pfx |

**Example:**
```yaml
identity-api:
  conf:
    notice: |
      <div class="alert alert-warning">
        <strong>Notice:</strong> This is a test environment.
      </div>
    signer: |
      MIIKfAIBAzCCCjwGCSqGSIb3DQEHA...
```

## Identity UI Configuration

```yaml
identity-ui:
  basehref: /ui  # Must match identity-api Branding__UiHost

  settings: "{}"  # Or use settingsYaml (recommended)
```

## Minimal Production Configuration

```yaml
identity-api:
  env:
    # Database
    Database__Provider: PostgreSQL
    Database__ConnectionString: "Server=postgres;Database=identity;Username=idsrv;Password=PASSWORD;"

    # Redis
    Cache__RedisUrl: "redis:6379"
    Cache__Key: "idsrv:"

    # Admin
    Account__AdminEmail: admin@example.com
    Account__AdminPassword: "SecurePassword123!"
    Account__OverrideCode: "123456"

    # Security
    Account__Authentication__SigningCertificate: conf/signer.pfx
    Account__Authentication__SigningCertificatePassword: "CERT_PASSWORD"
    Account__Authentication__Require2FA: true

    # Email
    AppMail__Url: https://mail-relay.example.com
    AppMail__Key: "API_KEY"
    AppMail__From: noreply@identity.example.com

    # Branding
    Branding__ApplicationName: "Identity"
    Branding__UiHost: "/ui"

    # Network
    Headers__Cors__Origins__0: https://identity.example.com
    Headers__Cors__AllowCredentials: true
    Headers__Forwarding__TargetHeaders: All

  conf:
    signer: |  # Base64-encoded .pfx
      MIIKfAIBAzCCC...
```

## Advanced Configuration

### Client Certificate Authentication

For environments using client certificates (CAC/PIV):

```yaml
identity-api:
  env:
    # Reverse proxy passes cert info via headers
    Account__Authentication__ClientCertHeader: X-ARR-ClientCert
    Account__Authentication__ClientCertSubjectHeaders__0: ssl-client-subject-dn
    Account__Authentication__ClientCertIssuerHeaders__0: ssl-client-issuer-dn
```

**Note:** Certificate validation should be done by reverse proxy (nginx), not the application.

### Profile/Avatar Settings

```yaml
identity-api:
  env:
    Account__Profile__ForcePublic: false  # Make all profiles public
    Account__Profile__ImageServerUrl: https://identity.example.com
```

### Session/Cookie Settings

```yaml
identity-api:
  env:
    Authorization__CookieLifetimeMinutes: 480  # 8 hours
    Authorization__CookieSlidingExpiration: false
    Account__Authentication__AllowRememberLogin: true
    Account__Authentication__RememberMeLoginDays: 30
```

## Troubleshooting

### Authentication Issues
- Verify `Branding__UiHost` matches actual UI location (`/ui`)
- Check `Headers__Cors__Origins__0` includes exact client URL
- Ensure `Headers__Cors__AllowCredentials` is `true`
- Verify certificate is valid and password is correct

### 2FA Not Working
- Check `AppMail__*` settings are configured
- Verify AppMailRelay service is accessible
- Use `Account__OverrideCode` as temporary bypass
- Check email delivery logs in AppMailRelay

### Token/Session Issues
- Verify token signing certificate is persistent (not regenerated on restart)
- Check Redis is accessible (for multi-replica)
- Ensure `Cache__RedisUrl` is configured for production
- Verify data protection keys are being stored

### Database Connection Issues
- Check connection string format matches provider
- Verify database user has CREATE permissions for migrations
- For multi-replica, use migrations job to avoid race conditions

### Certificate Validation Issues (Client Certs)
- Ensure reverse proxy is handling cert validation
- Verify correct header names are configured
- Check that headers can't be spoofed by clients

## Security Best Practices

1. **Use Kubernetes Secrets** for sensitive values:
   ```bash
   kubectl create secret generic identity-secrets \
     --from-literal=Database__ConnectionString="..." \
     --from-literal=Account__AdminPassword="..." \
     --from-file=signer=signer.pfx
   ```

2. **Persistent Token Signing**: Always use a persistent certificate in production

3. **Enable 2FA**: Set `Account__Authentication__Require2FA: true`

4. **Restrict Registration**: Use `Account__Registration__AllowedDomains`

5. **HTTPS Only**: Always use TLS in production

6. **Remove Swagger**: Set `Branding__IncludeSwagger: false` in production

7. **Session Security**: Set appropriate cookie lifetimes

8. **Change OverrideCode**: Update or remove after initial setup

## References

- [Identity Repository](https://github.com/cmu-sei/Identity)
- [Configuration File](https://github.com/cmu-sei/Identity/blob/master/src/IdentityServer/appsettings.conf)
- [IdentityServer4 Documentation](https://identityserver4.readthedocs.io/)
