# Moodle Helm Chart

[Moodle](https://moodle.org/) is a learning platform designed to provide educators, administrators and learners with a single robust, secure and integrated system to create personalized learning environments.

This Helm chart deploys Moodle using the lightweight [Alpine Linux based Moodle image](https://github.com/erseco/alpine-moodle).

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL or MariaDB/MySQL database
- Persistent storage (recommended for production deployments)

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install moodle sei/moodle -f values.yaml
```

## Moodle Configuration

The following settings configure the Moodle application via environment variables. Most settings correspond to the [alpine-moodle image configuration](https://github.com/erseco/alpine-moodle#configuration).

### Administrator Account

| Setting | Description | Default |
|---------|-------------|---------|
| `moodle.admin.username` | Initial admin username | `admin` |
| `moodle.admin.email` | Admin email address | `admin@example.com` |
| `moodle.admin.password` | Admin password (leave empty to auto-generate) | `""` (auto-generated) |
| `moodle.admin.existingSecret` | Use existing secret for admin password | `crucible-moodle-secret` |
| `moodle.admin.existingSecretKey` | Key in existing secret containing the password | `admin-password` |

**Important:**
- If `moodle.admin.password` is empty (default) and no `existingSecret` is provided, a random password will be automatically generated
- The default configuration uses `crucible-moodle-secret` with key `admin-password`
- For production, create the secret manually before deployment or leave the default configuration to auto-generate credentials

### Site Configuration

| Setting | Description | Example |
|---------|-------------|---------|
| `moodle.site.url` | Full URL where Moodle will be accessed | `https://moodle.example.com` |
| `moodle.site.name` | Site name displayed in Moodle | `Moodle` (default) |
| `moodle.site.language` | Default site language | `en` (default) |

**Important:**
- `moodle.site.url` must match your actual domain or ingress hostname. Moodle uses this for generating links and redirects.

### Proxy Configuration

Configure proxy settings when Moodle is behind a reverse proxy or load balancer.

| Setting | Description | Example |
|---------|-------------|---------|
| `moodle.proxy.reverseProxy` | Enable reverse proxy support | `false` (default) |
| `moodle.proxy.sslProxy` | Trust SSL headers from proxy | `true` (default) |

**Note:** Enable `sslProxy` if SSL/TLS is terminated at the load balancer or ingress controller.

### Database Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| `moodle.database.type` | Database type (`pgsql`, `mysqli`, or `mariadb`) | `pgsql` |
| `moodle.database.host` | Database hostname | `pg-postgresql` |
| `moodle.database.port` | Database port | `5432` |
| `moodle.database.name` | Database name | `moodledb` |
| `moodle.database.user` | Database username | `moodle` |
| `moodle.database.prefix` | Table prefix (do not use numeric values) | `mdl_` |
| `moodle.database.password` | Database password (leave empty if using existingSecret) | `""` |
| `moodle.database.existingSecret` | Secret containing database password | `crucible-moodle-secret` |
| `moodle.database.existingSecretKey` | Key in secret containing password | `database-password` |
| `moodle.database.create_database` | Automatically create database if it doesn't exist (runs as a Kubernetes Job) | `true` |

**Important:**

- The default configuration uses `crucible-moodle-secret` with key `database-password`
- Database credentials must be provided via `existingSecret` or `password` field (required for deployment)
- When `moodle.database.create_database` is `true` (default), the chart deploys a Kubernetes Job that:
  - Waits for PostgreSQL to be ready using `pg_isready`
  - Creates the database only if it doesn't exist (idempotent)
- If `moodle.database.create_database` is `false`, you must manually create the database before deploying
- Ensure database character set is UTF-8

**Example PostgreSQL Database Setup:**

If using the option `moodle.database.create_database`, the Moodle database will be created automatically if it does not already exist. If you choose, you can manually configure the Moodle database before deploying Moodle.

```sql
CREATE DATABASE moodledb WITH ENCODING 'UTF8';
CREATE USER moodle WITH PASSWORD 'your-password';
GRANT ALL PRIVILEGES ON DATABASE moodledb TO moodle;
```

### PHP and Upload Configuration

| Setting | Description | Default |
|---------|-------------|---------|
| `moodle.php.postMaxSize` | Maximum POST data size | `50M` |
| `moodle.php.uploadMaxFilesize` | Maximum file upload size | `50M` |
| `moodle.php.clientMaxBodySize` | Nginx client body size limit | `50M` |
| `moodle.php.maxInputVars` | Maximum input variables | `5000` |

**Note:** Increase these values if users need to upload large course files or assignments. The defaults are suitable for most standard Moodle deployments.

### SMTP Configuration (Optional)

Configure email sending via SMTP. **All SMTP settings must be configured together** - if you set any SMTP variable, you must set all of them (host, port, user, password/existingSecret).

| Setting | Description | Default | Recommended Value |
|---------|-------------|---------|-------------------|
| `moodle.smtp.host` | SMTP server hostname | `""` (not configured) | e.g., `smtp.gmail.com` |
| `moodle.smtp.port` | SMTP port | `""` (not configured) | `587` (TLS standard) |
| `moodle.smtp.user` | SMTP username | `""` (not configured) | Your SMTP username |
| `moodle.smtp.password` | SMTP password (leave empty if using existingSecret) | `""` | - |
| `moodle.smtp.existingSecret` | Secret containing SMTP password | `""` (not configured) | `crucible-moodle-secret` |
| `moodle.smtp.existingSecretKey` | Key in secret | `smtp-password` | - |
| `moodle.smtp.protocol` | SMTP protocol (`tls` or `ssl`) | `""` (not configured) | `tls` |
| `moodle.mail.noreplyAddress` | No-reply email address | `""` (not configured) | e.g., `noreply@example.com` |
| `moodle.mail.prefix` | Email subject prefix | `[Crucible Moodle]` | - |

**Important Notes:**
- SMTP is **disabled by default**. Email functionality will only work if ALL required SMTP settings are configured
- When configuring SMTP, you must set: `host`, `port`, `user`, and either `password` or `existingSecret`
- Recommended: Use `existingSecret` for the SMTP password in production instead of `password`
- Standard SMTP configuration uses TLS on port 587

### Redis Configuration (Optional)

Configure Redis for session storage. Required for multi-replica deployments.

| Setting | Description | Default | Recommended Value |
|---------|-------------|---------|-------------------|
| `moodle.redis.host` | Redis server hostname | `""` (not configured) | Your Redis service hostname |
| `moodle.redis.port` | Redis port | `""` (not configured) | `6379` (standard) |

**Important:**
- Redis is **disabled by default** and only required for multi-replica deployments to share sessions across pods
- If `moodle.redis.host` is not configured, Redis session storage will be disabled
- Standard Redis port is 6379

### Advanced Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `moodle.autoUpdateMoodle` | Automatically update Moodle at startup | `false` (default) |
| `moodle.debug` | Enable debug mode | `false` (default) |

## Helm Deployment Configuration

The following settings are specific to the Helm chart deployment and Kubernetes resources.

### Persistence Configuration

Configure storage for Moodle data directory (user uploads, course files, etc.).

#### Using EmptyDir (Testing Only)

**Default Configuration:**
```yaml
persistence:
  moodledata:
    enabled: true
    type: emptyDir
    sizeLimit: "5Gi"
```

**Warning:** Data is lost when pod is deleted or restarted.

#### Using PersistentVolumeClaim (Recommended)

```yaml
persistence:
  moodledata:
    enabled: true
    type: persistentVolumeClaim
    existingClaim: ""           # Leave empty or omit to create new PVC
    accessMode: ReadWriteMany   # Required for multi-replica
    size: 20Gi
    storageClass: "efs-sc"      # EFS, NFS, Azure Files, etc.
    retain: true                # Keep PVC on helm uninstall
```

**Note:** Multi-replica deployments require `ReadWriteMany` access mode (EFS, NFS, Azure Files, etc.). You can either leave `existingClaim` as an empty string or omit it entirely to create a new PVC dynamically.

#### Using Existing PVC

```yaml
persistence:
  moodledata:
    enabled: true
    type: persistentVolumeClaim
    existingClaim: "my-moodle-data-pvc"
```

### Read-Only Dirroot Configuration

Enable read-only Moodle code directory for security and multi-replica support.

| Setting | Description | Default |
|---------|-------------|---------|
| `readOnlyDirroot.enabled` | Enable read-only application directory | `false` |
| `readOnlyDirroot.volume` | Kubernetes volume configuration (emptyDir, PVC, etc.) | `emptyDir` with 1Gi size limit |
| `readOnlyDirroot.secret.name` | Secret containing config.php (leave empty to auto-generate) | `""` (auto-generated) |
| `readOnlyDirroot.secret.key` | Key in secret containing config.php | `config.php` |

**Why Enable Read-Only Dirroot:**

Read-only dirroot is **disabled by default** but provides several important benefits when enabled:

1. **Security Hardening**: Prevents runtime modifications to application code
2. **Multi-Replica Support**: Allows multiple pods to safely share the same Moodle codebase without conflicts
3. **Immutable Infrastructure**: Ensures all pods run identical code, making deployments more predictable and easier to debug
4. **Compliance**: Helps meet security requirements that mandate separation of code and data

When enabled, an init container seeds the Moodle code directory on pod startup from the container image. The `config.php` file is mounted separately from a secret, allowing for environment-specific configuration while keeping the codebase immutable.

**⚠️ Important Limitation with existingSecret:**

When using `database.existingSecret` that is created in the same Helm release (e.g., from a PostgreSQL subchart), **readOnlyDirroot must be disabled on first deploy**. This is because the auto-generated config.php uses Helm's `lookup` function to read the database password, but the secret doesn't exist yet during template rendering, resulting in an empty password.

**Workarounds:**
1. **Recommended**: Leave `readOnlyDirroot.enabled: false` (default) - the alpine-moodle image generates config.php at runtime from environment variables
2. Create the database secret manually before deploying Moodle
3. Provide your own config secret via `readOnlyDirroot.secret.name`

**Example with EmptyDir:**

```yaml
readOnlyDirroot:
  enabled: true  # Only enable if database secret exists before deployment
  volume:
    emptyDir:
      sizeLimit: "1Gi"
  secret:
    name: ""  # Auto-generate config.php
```

**Example with PVC:**

```yaml
readOnlyDirroot:
  enabled: true
  volume:
    persistentVolumeClaim:
      claimName: "moodle-code-pvc"
  secret:
    name: "moodle-config"
    key: "config.php"
```

### Ingress Configuration

```yaml
ingress:
  enabled: true # Default
  className: "nginx"
  hostname: "moodle.example.com"
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "512m"  # Default - match or exceed clientMaxBodySize
    # Optional: Add cert-manager annotation if using TLS with cert-manager
    # cert-manager.io/cluster-issuer: "letsencrypt-prod"
  tls:
    - secretName: moodle-tls
      hosts:
        - moodle.example.com
```

**Important:**
- Set `proxy-body-size` to match or exceed `moodle.php.clientMaxBodySize` for large file uploads (default: 512m)
  - **Automatic Validation**: The chart will fail installation if `proxy-body-size` is smaller than `clientMaxBodySize`, preventing upload failures
- TLS/SSL configuration is optional - add cert-manager annotations only if you're using cert-manager for TLS certificates

### Resource Configuration

Configure resource requests and limits using presets or custom values.

**Default Configuration:**

The chart uses the `small` preset by default, which allocates:
- CPU Request: 250m, Limit: 500m
- Memory Request: 256Mi, Limit: 512Mi

This is suitable for development and small production deployments. Adjust based on your workload.

**Using Presets:**

```yaml
resourcesPreset: "small"  # Default - Options: nano, micro, small, medium, large, xlarge, 2xlarge
```

| Preset | CPU Request | Memory Request | CPU Limit | Memory Limit |
|--------|-------------|----------------|-----------|--------------|
| `nano` | 50m | 64Mi | 100m | 128Mi |
| `micro` | 100m | 128Mi | 200m | 256Mi |
| `small` | 250m | 256Mi | 500m | 512Mi |
| `medium` | 500m | 512Mi | 1000m | 1Gi |
| `large` | 1000m | 1Gi | 2000m | 2Gi |
| `xlarge` | 2000m | 2Gi | 4000m | 4Gi |
| `2xlarge` | 4000m | 4Gi | 8000m | 8Gi |

**Custom Resources:**

```yaml
resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2000m
    memory: 2Gi
```

### Probes Configuration

Health check probes are enabled by default with sensible values.

| Setting | Default | Description |
|---------|---------|-------------|
| `startupProbe.enabled` | `true` | Enable startup probe |
| `startupProbe.failureThreshold` | `30` | Number of failures before restart |
| `livenessProbe.enabled` | `true` | Enable liveness probe |
| `livenessProbe.initialDelaySeconds` | `120` | Delay before first check |
| `readinessProbe.enabled` | `true` | Enable readiness probe |
| `readinessProbe.initialDelaySeconds` | `30` | Delay before first check |

All probes use `/login/index.php` as the health check endpoint.

### Scaling Configuration

#### Horizontal Pod Autoscaling

Autoscaling is **disabled by default** since the default deployment uses a single replica.

```yaml
autoscaling:
  enabled: false   # Default - set to true to enable
  minReplicas: 1
  maxReplicas: 10
  targetCPU: 80
  targetMemory: 80
```

**Important:** Multi-replica deployments require:

- Redis for session storage
- ReadWriteMany storage for moodledata
- Read-only dirroot for shared Moodle code (enabled by default)

#### Pod Disruption Budget

Pod Disruption Budget is **disabled by default** since single-replica deployments don't benefit from PDB protection.

```yaml
pdb:
  create: false    # Default - set to true for multi-replica deployments
  minAvailable: 1
```

**Note:** Enable PDB only when running 2 or more replicas to ensure availability during voluntary disruptions (node drains, cluster upgrades, etc.).

### Security Context

Configure pod and container security contexts. The chart uses secure defaults following Kubernetes security best practices.

**Default Configuration:**

```yaml
podSecurityContext:
  enabled: true
  fsGroupChangePolicy: Always
  sysctls: []
  supplementalGroups: []
  fsGroup: 65534                     # nobody/nogroup
  runAsUser: 65534                   # nobody user
  runAsGroup: 65534                  # nogroup
  runAsNonRoot: true                 # runs as non-root user

containerSecurityContext:
  enabled: true
  seLinuxOptions: {}
  runAsUser: 65534                   # nobody user
  runAsGroup: 65534                  # nogroup
  runAsNonRoot: true                 # runs as non-root user
  privileged: false                  # no privileged mode
  readOnlyRootFilesystem: false      # writable filesystem needed for Moodle
  allowPrivilegeEscalation: false    # prevents privilege escalation
  capabilities:
    drop: ["ALL"]                    # drops all Linux capabilities
  seccompProfile:
    type: RuntimeDefault             # uses runtime default seccomp profile
```

**Security Best Practices:**

- Runs as non-root user (UID 65534 - nobody) by default
- Uses dedicated group (GID 65534 - nogroup)
- Drops all Linux capabilities
- Prevents privilege escalation
- Uses seccomp runtime default profile
- Compatible with restricted Pod Security Standards
- FSGroup ownership changes applied to volumes

### Network Policy

Network policies provide network-level security by controlling pod-to-pod and external communication.

**Default Configuration:**

```yaml
networkPolicy:
  enabled: false               # Disabled by default
  policyTypes:
    - Ingress
    - Egress
  allowExternal: true          # Allow external ingress traffic
  allowExternalEgress: true    # Allow all egress traffic
  databaseSelector: {}         # No database pod selector
```

**Enabling Network Policies:**

```yaml
networkPolicy:
  enabled: true
  allowExternal: false         # Restrict ingress to specific namespaces
  allowExternalEgress: false   # Restrict egress to specific services
  databaseSelector:
    app: postgres              # Allow egress to database pods
  ingressNSMatchLabels:
    name: ingress-nginx        # Allow ingress from nginx namespace
```

**Note:** Network policies require a CNI plugin that supports NetworkPolicy (e.g., Calico, Cilium, Weave Net). The default configuration allows all traffic, making it suitable for testing and development environments. For production, enable and configure policies based on your security requirements.

## Troubleshooting

### Database Connection Issues

- Verify database is accessible from Moodle pods
- Check database credentials in secret
- Ensure database character set is UTF-8
- Verify network policies allow connection to database

### File Upload Issues

- Verify `moodle.php.uploadMaxFilesize` is sufficient
- Check ingress `proxy-body-size` annotation matches or exceeds `moodle.php.clientMaxBodySize`
  - The chart will automatically validate this and fail installation if misconfigured
  - If you see a validation error, update `ingress.annotations["nginx.ingress.kubernetes.io/proxy-body-size"]`
- Ensure moodledata volume has sufficient space
- Check permissions on moodledata directory (should be writable by user 65534)

### Multi-Replica Issues

- Verify Redis is configured and accessible
- Ensure moodledata uses ReadWriteMany storage
- Check that all pods can write to shared storage
- Verify read-only dirroot is configured if enabled
- Review pod logs for leader election messages

### Performance Issues

- Increase resource limits and requests
- Enable Redis for session storage
- Verify database performance and connection pooling
- Check if read-only dirroot is enabled for multi-replica

### Pod Crashes or Restarts

- Check resource limits are sufficient
- Verify startup probe timeout is adequate for Moodle initialization
- Check for database connection limits
- Review pod logs for errors
- Ensure persistent storage is properly mounted

### Read-Only Dirroot Issues

- Verify init container completed successfully
- Check config.php secret is mounted correctly
- Ensure dirroot volume is writable by init container
- Review init container logs: `kubectl logs <pod> -c seed-dirroot`
- For multi-replica, verify only one pod performs database installation (leader election)

## References

- [Moodle Documentation](https://docs.moodle.org/)
- [Alpine Moodle Image](https://github.com/erseco/alpine-moodle)
- [Moodle System Requirements](https://docs.moodle.org/en/Installing_Moodle#Requirements)
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Helm Documentation](https://helm.sh/docs/)
