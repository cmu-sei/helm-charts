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

The following settings configure the Moodle application via environment variables. These correspond to the [alpine-moodle image configuration](https://github.com/erseco/alpine-moodle#configuration).

### Administrator Account

| Setting | Description | Example |
|---------|-------------|---------|
| `moodle.admin.username` | Initial admin username | `admin` |
| `moodle.admin.email` | Admin email address | `admin@example.com` |
| `moodle.admin.password` | Admin password (leave empty to auto-generate) | `SecurePassword123!` |
| `moodle.admin.existingSecret` | Use existing secret for admin password (recommended for production) | `moodle-admin-secret` |
| `moodle.admin.existingSecretKey` | Key in existing secret containing the password | `admin-password` |

**Security Note:** Use `existingSecret` for production deployments instead of storing passwords in values files.

### Site Configuration

| Setting | Description | Example |
|---------|-------------|---------|
| `moodle.site.url` | Full URL where Moodle will be accessed | `https://moodle.example.com` |
| `moodle.site.name` | Site name displayed in Moodle | `My Learning Platform` |
| `moodle.site.language` | Default site language | `en` |

**Important:** `moodle.site.url` must match your actual domain or ingress hostname. Moodle uses this for generating links and redirects.

### Proxy Configuration

Configure proxy settings when Moodle is behind a reverse proxy or load balancer.

| Setting | Description | Example |
|---------|-------------|---------|
| `moodle.proxy.reverseProxy` | Enable reverse proxy support | `true` |
| `moodle.proxy.sslProxy` | Trust SSL headers from proxy | `true` |

**Note:** Enable `sslProxy` if SSL/TLS is terminated at the load balancer or ingress controller.

### Database Configuration

| Setting | Description | Example |
|---------|-------------|---------|
| `moodle.database.type` | Database type (`pgsql`, `mysqli`, or `mariadb`) | `pgsql` |
| `moodle.database.host` | Database hostname | `postgres` |
| `moodle.database.port` | Database port | `5432` |
| `moodle.database.name` | Database name | `moodledb` |
| `moodle.database.user` | Database username | `moodle` |
| `moodle.database.prefix` | Table prefix (do not use numeric values) | `mdl_` |
| `moodle.database.password` | Database password (leave empty if using existingSecret) | `MyDBPassword` |
| `moodle.database.existingSecret` | Secret containing database password (recommended for production) | `postgres-secret` |
| `moodle.database.existingSecretKey` | Key in secret containing password | `password` |
| `moodle.database.create_database` | Automatically create database if it doesn't exist (runs as pre-install/pre-upgrade hook) | `true` |

**Important:**

- When `moodle.database.create_database` is `true` (default), the chart will automatically create the database if it doesn't exist
- If `moodle.database.create_database` is `false`, you must manually create the database before deploying
- Ensure database character set is UTF-8

**Example PostgreSQL Database Setup:**

```sql
CREATE DATABASE moodledb WITH ENCODING 'UTF8';
CREATE USER moodle WITH PASSWORD 'your-password';
GRANT ALL PRIVILEGES ON DATABASE moodledb TO moodle;
```

### PHP and Upload Configuration

| Setting | Description | Example |
|---------|-------------|---------|
| `moodle.php.postMaxSize` | Maximum POST data size | `100M` |
| `moodle.php.uploadMaxFilesize` | Maximum file upload size | `100M` |
| `moodle.php.clientMaxBodySize` | Nginx client body size limit | `100M` |
| `moodle.php.maxInputVars` | Maximum input variables | `5000` |

**Note:** Increase these values if users need to upload large course files or assignments.

### SMTP Configuration (Optional)

Configure email sending via SMTP.

| Setting | Description | Example |
|---------|-------------|---------|
| `moodle.smtp.host` | SMTP server hostname | `smtp.gmail.com` |
| `moodle.smtp.port` | SMTP port | `587` |
| `moodle.smtp.user` | SMTP username | `moodle@example.com` |
| `moodle.smtp.password` | SMTP password (leave empty if using existingSecret) | `SMTPPassword123` |
| `moodle.smtp.existingSecret` | Secret containing SMTP password (recommended) | `smtp-credentials` |
| `moodle.smtp.existingSecretKey` | Key in secret | `password` |
| `moodle.smtp.protocol` | SMTP protocol (`tls` or `ssl`) | `tls` |
| `moodle.mail.noreplyAddress` | No-reply email address | `noreply@example.com` |
| `moodle.mail.prefix` | Email subject prefix | `[Moodle]` |

### Redis Configuration (Optional)

Configure Redis for session storage. Required for multi-replica deployments.

| Setting | Description | Example |
|---------|-------------|---------|
| `moodle.redis.host` | Redis server hostname | `redis-master` |
| `moodle.redis.port` | Redis port | `6379` |

**Important:** Redis is required for multi-replica deployments to share sessions across pods.

### Advanced Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `moodle.autoUpdateMoodle` | Automatically update Moodle at startup | `false` |
| `moodle.debug` | Enable debug mode | `false` |

## Helm Deployment Configuration

The following settings are specific to the Helm chart deployment and Kubernetes resources.

### Persistence Configuration

Configure storage for Moodle data directory (user uploads, course files, etc.).

#### Using EmptyDir (Testing Only)

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
    existingClaim: ""           # Leave empty to create new PVC
    accessMode: ReadWriteMany   # Required for multi-replica
    size: 20Gi
    storageClass: "efs-sc"      # EFS, NFS, Azure Files, etc.
    retain: true                # Keep PVC on helm uninstall
```

**Note:** Multi-replica deployments require `ReadWriteMany` access mode (EFS, NFS, Azure Files, etc.).

#### Using Existing PVC

```yaml
persistence:
  moodledata:
    enabled: true
    existingClaim: "my-moodle-data-pvc"
```

### Read-Only Dirroot Configuration

Enable read-only Moodle code directory for security and multi-replica support.

| Setting | Description |
|---------|-------------|
| `readOnlyDirroot.enabled` | Enable read-only application directory |
| `readOnlyDirroot.volume` | Kubernetes volume configuration (emptyDir, PVC, etc.) |
| `readOnlyDirroot.secret.name` | Secret containing config.php (leave empty to auto-generate) |
| `readOnlyDirroot.secret.key` | Key in secret containing config.php |

When enabled, an init container seeds the Moodle code directory on pod startup. The config.php file is mounted separately from a secret.

**Example with EmptyDir:**

```yaml
readOnlyDirroot:
  enabled: true
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
  enabled: true
  className: "nginx"
  hostname: "moodle.example.com"
  annotations:
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
  tls:
    - secretName: moodle-tls
      hosts:
        - moodle.example.com
```

**Important:** Set `proxy-body-size` to match or exceed `moodle.php.clientMaxBodySize` for large file uploads.

### Resource Configuration

Configure resource requests and limits using presets or custom values.

**Using Presets:**

```yaml
resourcesPreset: "large"  # Options: nano, small, medium, large, xlarge, 2xlarge
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

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPU: 80
  targetMemory: 80
```

**Important:** Multi-replica deployments require:

- Redis for session storage
- ReadWriteMany storage for moodledata
- Read-only dirroot for shared Moodle code

#### Pod Disruption Budget

```yaml
pdb:
  create: true
  minAvailable: 1
```

### Security Context

Configure pod and container security contexts.

```yaml
podSecurityContext:
  enabled: true
  fsGroup: 65534
  runAsUser: 65534
  runAsGroup: 65534
  runAsNonRoot: true

containerSecurityContext:
  enabled: true
  runAsUser: 65534
  runAsNonRoot: true
  readOnlyRootFilesystem: false
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault
```

### Network Policy

Enable network policies for security.

```yaml
networkPolicy:
  enabled: true
  allowExternal: false
  databaseSelector:
    app: postgres
```

## Troubleshooting

### Database Connection Issues

- Verify database is accessible from Moodle pods
- Check database credentials in secret
- Ensure database character set is UTF-8
- Verify network policies allow connection to database

### File Upload Issues

- Verify `moodle.php.uploadMaxFilesize` is sufficient
- Check ingress `proxy-body-size` annotation matches PHP limits
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
