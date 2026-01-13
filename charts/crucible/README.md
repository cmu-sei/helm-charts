# Crucible Helm Chart

This Helm chart deploys the [Crucible](https://cmu-sei.github.io/crucible/) platform applications, including Keycloak identity provider and all Crucible services (Player, Caster, Alloy, Blueprint, CITE, Gallery, Gameboard, Steamfitter, TopoMojo, and Moodle).

## Overview

The crucible chart can be deployed with:
- **crucible-infra chart** (provides PostgreSQL, ingress controller, NFS storage)
- **External PostgreSQL** (RDS, Cloud SQL, Azure Database, or any PostgreSQL service)
- **Custom infrastructure** (bring your own PostgreSQL, ingress, and storage)

### Components

Chart components are enabled by default, but can be disabled via the values file.

- **Keycloak**: Identity and access management for all Crucible applications
- **Player**: Exercise player interface and VM management
- **Caster**: Infrastructure-as-Code orchestration
- **Alloy**: Exercise event orchestration
- **Blueprint**: Exercise design and templating
- **CITE**: Collaborative incident threat evaluator
- **Gallery**: Content library and exhibit management
- **Gameboard**: Competitive cyber exercise platform
- **Steamfitter**: Scenario automation and simulation
- **TopoMojo**: Virtual machine lab management
- **Moodle**: Learning management system integration

## Prerequisites

1. **Kubernetes 1.19+**
2. **Helm 3.0+**
3. **PostgreSQL database** (crucible-infra chart, external PostgreSQL, or cloud database)
4. **Ingress controller** (crucible-infra chart provides nginx, or use your own)
5. **Persistent storage** (crucible-infra chart provides NFS, or use your StorageClass)
6. **TLS certificate** created as a Kubernetes secret
7. **Keycloak realm configuration** (optional - can be configured via UI after deployment)
8. **OAuth client secrets** generated and configured

## Security Prerequisites

Before installing this chart, you **must** prepare the following:

### 1. TLS Certificate

Create a TLS secret for ingress:

```bash
# Using cert-manager (recommended for production)
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: crucible-tls
  namespace: default
spec:
  secretName: crucible-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - crucible.example.com
EOF

# OR using a self-signed certificate (development only)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj "/CN=crucible.example.com"
kubectl create secret tls crucible-tls --cert=tls.crt --key=tls.key
```

### 2. Keycloak Realm Configuration (Optional)

You have two options for configuring the Keycloak realm:

**Option A: Automatic Import (Recommended for Repeatable Deployments)**

Prepare a realm configuration file and create it as a ConfigMap for automatic import on deployment:

```bash
# Create or customize your realm.json file
# IMPORTANT: Generate unique OAuth client secrets for production
# Do not use example secrets from development configurations

kubectl create configmap crucible-realm-config \
  --from-file=realm.json=path/to/your-realm.json
```

Then in your `values.yaml`, uncomment the Keycloak realm import configuration:

```yaml
keycloak:
  extraEnvVars:
    - name: KEYCLOAK_EXTRA_ARGS
      value: "--import-realm"
  extraVolumes:
    - name: realm-import
      configMap:
        name: crucible-realm-config  # Your ConfigMap name
  extraVolumeMounts:
    - name: realm-import
      mountPath: /opt/bitnami/keycloak/data/import
      readOnly: true
```

**Option B: Manual Configuration (UI-Based)**

Skip the ConfigMap creation and configure Keycloak manually after deployment:
- Leave the `keycloak.extraEnvVars`, `extraVolumes`, and `extraVolumeMounts` commented out (default)
- After deployment, access the Keycloak admin UI at `https://<domain>/keycloak/admin`
- Create and configure the realm manually through the UI

**Security Considerations for Realm Configuration:**

- Generate unique, strong OAuth client secrets for each client
- Remove or disable any test/demo user accounts
- Configure appropriate password policies
- Enable brute force protection
- Set `sslRequired: "all"` for production environments
- Configure appropriate session timeouts
- Review and restrict client redirect URIs (no wildcards)

Example command to generate a secure client secret:

```bash
openssl rand -hex 32
```

### 3. OAuth Client Secrets

Configure OAuth client secrets in your `values.yaml`. These secrets must match the secrets in your Keycloak realm configuration:

```yaml
crucible-alloy:
  alloy-api:
    resourceOwnerAuthorization:
      clientSecret: "your-generated-secret-here"
      userName: "service-account-username"
      password: "service-account-password"

gameboard:
  gameboard-api:
    gameEngineClientSecret: "your-generated-secret-here"
```

**Never commit secrets to version control.** Use one of these approaches:

- **Recommended**: External secret management (HashiCorp Vault, AWS Secrets Manager, Azure Key Vault)
- Alternative: Separate values file with restricted access, not committed to git
- Alternative: Helm secrets plugin with encryption

## Installation

### Option A: Using crucible-infra Chart (Recommended for Getting Started)

If you're deploying the full Crucible infrastructure:

#### 1. Install crucible-infra First

```bash
# Install the infrastructure chart (provides PostgreSQL, Ingress, NFS storage)
helm install crucible-infra oci://registry.example.com/crucible-infra

# Wait for infrastructure to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql --timeout=300s
```

#### 2. Prepare Security Prerequisites

Follow the [Security Prerequisites](#security-prerequisites) section to create:
- TLS certificate secret
- Keycloak realm ConfigMap (optional - can configure via UI after deployment)
- OAuth client secrets configuration

#### 3. Create Your Values File

```yaml
global:
  domain: crucible.example.com
  tlsSecretName: crucible-tls
  postgresql:
    serviceName: "crucible-infra-postgresql"
    secretName: "crucible-infra-postgresql"
    usernameKey: "username"
    passwordKey: "postgres-password"

# Optional: Enable Keycloak realm import
# keycloak:
#   extraEnvVars:
#     - name: KEYCLOAK_EXTRA_ARGS
#       value: "--import-realm"
#   extraVolumes:
#     - name: realm-import
#       configMap:
#         name: crucible-realm-config
#   extraVolumeMounts:
#     - name: realm-import
#       mountPath: /opt/bitnami/keycloak/data/import
#       readOnly: true

crucible-alloy:
  alloy-api:
    resourceOwnerAuthorization:
      clientSecret: "your-alloy-client-secret"
      userName: "admin"
      password: "your-service-account-password"

gameboard:
  gameboard-api:
    gameEngineClientSecret: "your-gameboard-client-secret"
```

#### 4. Install the Crucible Chart

```bash
helm install crucible oci://registry.example.com/crucible -f my-values.yaml
```

### Option B: Using External PostgreSQL (RDS, Cloud SQL, etc.)

If you're using an external PostgreSQL service:

#### 1. Prepare PostgreSQL Database

Ensure your PostgreSQL instance is accessible from your Kubernetes cluster and create the required databases:

```sql
-- Connect to your PostgreSQL instance and create databases
CREATE DATABASE keycloak;
CREATE DATABASE alloy;
CREATE DATABASE blueprint;
CREATE DATABASE caster;
CREATE DATABASE cite;
CREATE DATABASE gallery;
CREATE DATABASE gameboard;
CREATE DATABASE player;
CREATE DATABASE steamfitter;
CREATE DATABASE topomojo;
CREATE DATABASE vm;
-- Optional: CREATE DATABASE moodle;
```

#### 2. Create PostgreSQL Credentials Secret

```bash
kubectl create secret generic postgres-credentials \
  --from-literal=username='crucible_admin' \
  --from-literal=password='your-postgres-password'
```

#### 3. Prepare Other Prerequisites

Follow the [Security Prerequisites](#security-prerequisites) section to create:
- TLS certificate secret
- Keycloak realm ConfigMap (optional - can configure via UI after deployment)
- OAuth client secrets configuration

#### 4. Create Your Values File

```yaml
global:
  domain: crucible.example.com
  tlsSecretName: crucible-tls
  postgresql:
    # AWS RDS example
    serviceName: "my-db.abc123.us-east-1.rds.amazonaws.com"
    port: 5432
    secretName: "postgres-credentials"
    usernameKey: "username"
    passwordKey: "password"

crucible-alloy:
  alloy-api:
    resourceOwnerAuthorization:
      clientSecret: "your-alloy-client-secret"
      userName: "admin"
      password: "your-service-account-password"

gameboard:
  gameboard-api:
    gameEngineClientSecret: "your-gameboard-client-secret"

# Note: You'll need to provide your own ingress controller and storage
```

#### 5. Install the Crucible Chart

```bash
helm install crucible oci://registry.example.com/crucible -f my-values.yaml
```

**Note**: When using external PostgreSQL, you must also provide:
- An ingress controller (nginx, traefik, etc.)
- Persistent storage (StorageClass for PVCs)

## Configuration

### Global Settings

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `global.domain` | Domain name for Crucible deployment | `""` | **Yes** |
| `global.namespace` | Kubernetes namespace | `default` | No |
| `global.version` | Version tag for Crucible components | `0.0.0` | No |
| `global.security.allowInsecureImages` | Allow unsigned container images (dev only) | `false` | No |
| `global.tlsSecretName` | TLS secret for all ingresses | `""` | **Yes** |

### Keycloak Configuration

Configure Keycloak identity provider settings used by all Crucible applications:

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `global.keycloak.basePath` | Base path for Keycloak (relative to domain) | `/keycloak` | No |
| `global.keycloak.realm` | Keycloak realm name | `crucible` | No |

These settings are used to construct Keycloak URLs for OIDC authentication across all applications. Changing these values will update the authority, authorization, and token URLs for all integrated services.

**Realm Import Configuration:**

By default, Keycloak deploys without automatically importing a realm. To enable automatic realm import:

1. Create a ConfigMap with your realm configuration (see [Security Prerequisites](#security-prerequisites))
2. Uncomment the `keycloak.extraEnvVars`, `keycloak.extraVolumes`, and `keycloak.extraVolumeMounts` sections in values.yaml
3. Set the ConfigMap name in `keycloak.extraVolumes[0].configMap.name`

If you don't configure realm import, you can configure Keycloak manually via the admin UI after deployment.

**Example custom configuration:**

```yaml
global:
  keycloak:
    basePath: "/auth"  # Custom Keycloak path
    realm: "production"  # Custom realm name

# Optional: Enable realm import
keycloak:
  extraEnvVars:
    - name: KEYCLOAK_EXTRA_ARGS
      value: "--import-realm"
  extraVolumes:
    - name: realm-import
      configMap:
        name: production-realm-config
  extraVolumeMounts:
    - name: realm-import
      mountPath: /opt/bitnami/keycloak/data/import
      readOnly: true
```

### PostgreSQL Connection Settings

Configure connection to your PostgreSQL database. The chart supports multiple PostgreSQL deployment options:
- **crucible-infra chart** - PostgreSQL deployed via the infra chart
- **External PostgreSQL** - Self-hosted PostgreSQL server
- **Cloud databases** - AWS RDS, Google Cloud SQL, Azure Database for PostgreSQL
- **Managed services** - Any PostgreSQL-compatible service

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `global.postgresql.serviceName` | PostgreSQL service name or hostname | `""` | **Yes** |
| `global.postgresql.port` | PostgreSQL port | `5432` | No |
| `global.postgresql.secretName` | Secret containing credentials | `""` | **Yes** |
| `global.postgresql.usernameKey` | Key in secret containing username | `username` | No |
| `global.postgresql.passwordKey` | Key in secret containing password | `password` | No |

**Examples:**

```yaml
# Using crucible-infra chart
global:
  postgresql:
    serviceName: "crucible-infra-postgresql"
    secretName: "crucible-infra-postgresql"
    usernameKey: "username"
    passwordKey: "postgres-password"

# Using AWS RDS
global:
  postgresql:
    serviceName: "my-db.abc123.us-east-1.rds.amazonaws.com"
    port: 5432
    secretName: "rds-postgres-credentials"
    usernameKey: "username"
    passwordKey: "password"

# Using external PostgreSQL
global:
  postgresql:
    serviceName: "postgres.example.com"
    port: 5432
    secretName: "external-postgres-secret"
    usernameKey: "username"
    passwordKey: "password"
```

**Creating the credentials secret:**

```bash
# Standard approach (both username and password in one secret)
kubectl create secret generic postgres-credentials \
  --from-literal=username='postgres' \
  --from-literal=password='your-secure-password'

# For RDS or external PostgreSQL
kubectl create secret generic postgres-credentials \
  --from-literal=username='crucible_admin' \
  --from-literal=password='your-secure-password'

# From environment variables
kubectl create secret generic postgres-credentials \
  --from-literal=username="${POSTGRES_USER}" \
  --from-literal=password="${POSTGRES_PASSWORD}"

# For crucible-infra chart compatibility (username in secret)
kubectl create secret generic crucible-infra-postgresql \
  --from-literal=username='postgres' \
  --from-literal=postgres-password='your-password'
```

### Keycloak Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `keycloak.enabled` | Enable Keycloak deployment | `true` |
| `keycloak.auth.adminUser` | Keycloak admin username | `keycloak-admin` |
| `keycloak.httpRelativePath` | URL path for Keycloak | `/keycloak/` |

**Password Management**: The Keycloak admin password is automatically generated on first install and persisted. To retrieve it:

```bash
kubectl get secret <release-name>-keycloak-auth -o jsonpath='{.data.admin-password}' | base64 --decode
```

**Realm Import**: The chart imports the Keycloak realm configuration on first startup. If the realm already exists, it will **not** be overwritten.

### Application-Specific Secrets

Several applications require OAuth client secrets to be configured:

#### Alloy Service Account

```yaml
crucible-alloy:
  alloy-api:
    resourceOwnerAuthorization:
      # Authority URL is automatically constructed from global.keycloak settings
      authority: "https://{{ .Values.global.domain }}{{ .Values.global.keycloak.basePath }}/realms/{{ .Values.global.keycloak.realm }}"
      clientId: "alloy.admin"
      clientSecret: ""  # Required: OAuth client secret from Keycloak
      userName: ""      # Required: Service account username
      password: ""      # Required: Service account password
```

#### Gameboard Game Engine

```yaml
gameboard:
  gameboard-api:
    gameEngineClientSecret: ""  # Required: TopoMojo client secret
```

## Example Configurations

### Production Deployment

```yaml
global:
  domain: crucible.example.com
  tlsSecretName: crucible-tls
  security:
    allowInsecureImages: false
  # Optional: Customize Keycloak configuration
  # keycloak:
  #   basePath: "/auth"
  #   realm: "production"

crucible-alloy:
  alloy-api:
    resourceOwnerAuthorization:
      clientSecret: "{{ .Values.secrets.alloyClientSecret }}"
      userName: "crucible-admin"
      password: "{{ .Values.secrets.alloyPassword }}"

gameboard:
  gameboard-api:
    gameEngineClientSecret: "{{ .Values.secrets.gameboardClientSecret }}"

# Disable optional components if not needed
moodle:
  enabled: false
```

### Development Deployment

For local development only:

```yaml
global:
  domain: crucible.local
  tlsSecretName: crucible-dev-tls
  security:
    allowInsecureImages: true  # Only for development

crucible-alloy:
  alloy-api:
    resourceOwnerAuthorization:
      clientSecret: "dev-secret-change-me"
      userName: "admin"
      password: "admin"

gameboard:
  gameboard-api:
    gameEngineClientSecret: "dev-secret-change-me"
```

**⚠️ WARNING**: Never use development secrets in production environments.

### Minimal Deployment

Deploy only essential applications:

```yaml
global:
  domain: crucible.example.com
  tlsSecretName: crucible-tls

# Disable optional applications
gameboard:
  enabled: false

moodle:
  enabled: false
```

### External PostgreSQL / Cloud Database

Using AWS RDS, Google Cloud SQL, Azure Database, or external PostgreSQL:

```yaml
global:
  domain: crucible.example.com
  tlsSecretName: crucible-tls
  postgresql:
    # AWS RDS example
    serviceName: "crucible-db.abc123.us-west-2.rds.amazonaws.com"
    port: 5432
    secretName: "rds-postgres-secret"
    usernameKey: "username"
    passwordKey: "password"

# Configure OAuth secrets as needed
crucible-alloy:
  alloy-api:
    resourceOwnerAuthorization:
      clientSecret: "your-secret"
      userName: "admin"
      password: "your-password"

gameboard:
  gameboard-api:
    gameEngineClientSecret: "your-secret"
```

**Prerequisites for external PostgreSQL:**
- Databases must be pre-created (see [Option B Installation](#option-b-using-external-postgresql-rds-cloud-sql-etc))
- Network connectivity from Kubernetes to PostgreSQL
- Secret containing database password
- Your own ingress controller
- Your own persistent storage (StorageClass)

## Accessing Services

After deployment, services are accessible at:

| Service | URL |
|---------|-----|
| Keycloak Admin | `https://<domain>/keycloak/admin/crucible/console/` |
| Player | `https://<domain>/player` |
| Alloy | `https://<domain>/alloy` |
| Blueprint | `https://<domain>/blueprint` |
| Caster | `https://<domain>/caster` |
| CITE | `https://<domain>/cite` |
| Gallery | `https://<domain>/gallery` |
| Gameboard | `https://<domain>/gameboard` |
| Steamfitter | `https://<domain>/steamfitter` |
| TopoMojo | `https://<domain>/topomojo` |
| Moodle | `https://<domain>/` |

## Security Best Practices

### Secret Management

**Do not store secrets in values files committed to version control.**

Recommended approaches:

1. **External Secret Operators** (Recommended)
   - [External Secrets Operator](https://external-secrets.io/)
   - [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
   - Cloud provider secret managers (AWS Secrets Manager, Azure Key Vault, GCP Secret Manager)

2. **Helm Secrets Plugin**
   ```bash
   helm secrets install crucible ./crucible -f secrets.yaml
   ```

3. **CI/CD Pipeline Injection**
   - Store secrets in CI/CD secret stores (GitHub Secrets, GitLab CI Variables)
   - Inject at deployment time

### OAuth Client Configuration

- Generate unique secrets for each environment (dev, staging, prod)
- Use strong random strings (minimum 32 characters)
- Rotate secrets periodically
- Restrict client redirect URIs (no wildcards)
- Use confidential clients for backend services
- Review and minimize client scopes

### TLS Configuration

- Use cert-manager with Let's Encrypt for automatic certificate renewal
- Never commit TLS private keys to git
- Use strong cipher suites
- Enable HSTS (HTTP Strict Transport Security)
- Consider mutual TLS (mTLS) for service-to-service communication

### Database Security

- Use strong PostgreSQL passwords
- Restrict database network access
- Enable SSL/TLS for database connections
- Regular database backups
- Implement database access auditing

## Troubleshooting

### Realm ConfigMap Not Found

If you see an error about the realm ConfigMap not being found:

```bash
# Verify the ConfigMap exists
kubectl get configmap crucible-realm-config

# Check the ConfigMap has the realm.json key
kubectl describe configmap crucible-realm-config

# Recreate if needed
kubectl create configmap crucible-realm-config \
  --from-file=realm.json=path/to/realm.json
```

### TLS Certificate Issues

If applications show certificate errors:

```bash
# Verify the TLS secret exists
kubectl get secret crucible-tls

# Check certificate validity
kubectl get secret crucible-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 --decode | openssl x509 -noout -dates

# Check certificate details
kubectl get secret crucible-tls -o jsonpath='{.data.tls\.crt}' | \
  base64 --decode | openssl x509 -noout -text
```

### Cannot Connect to PostgreSQL

If applications cannot connect to the database:

1. Verify crucible-infra is deployed and PostgreSQL is running:
   ```bash
   kubectl get pods -l app.kubernetes.io/name=postgresql
   ```

2. Check that the service name matches:
   ```bash
   kubectl get svc | grep postgresql
   ```

3. Verify the password secret exists:
   ```bash
   kubectl get secret crucible-infra-postgresql
   ```

4. Check application logs for connection errors:
   ```bash
   kubectl logs -l app.kubernetes.io/name=<app-name>
   ```

### Keycloak Authentication Failures

If applications cannot authenticate with Keycloak:

1. Verify OAuth client secrets match between values and Keycloak realm
2. Check client redirect URIs in Keycloak match application URLs
3. Verify the realm was imported correctly:
   ```bash
   kubectl logs -l app.kubernetes.io/name=keycloak
   ```

### Applications Not Accessible via Ingress

1. Verify the ingress controller is running:
   ```bash
   kubectl get pods -l app.kubernetes.io/name=ingress-nginx
   ```

2. Check ingress resources:
   ```bash
   kubectl get ingress
   ```

3. Verify DNS resolution for your domain

4. Check TLS certificate is valid and matches domain

## Upgrading

To upgrade the chart:

```bash
helm upgrade crucible oci://registry.example.com/crucible -f my-values.yaml
```

**Note**: Secrets with `helm.sh/resource-policy: keep` annotation are preserved during upgrades.

## Uninstallation

To remove the chart:

```bash
helm uninstall crucible
```

**Important**: This will not delete:
- Secrets with the `keep` resource policy
- Database data in PostgreSQL (managed by crucible-infra)
- PVCs (managed by crucible-infra)
- ConfigMaps (realm configuration, certificates)

To clean up secrets:

```bash
kubectl delete secret <release-name>-keycloak-auth
kubectl delete configmap crucible-realm-config
```

To also remove the infrastructure:

```bash
helm uninstall crucible-infra
```

## References

- [Crucible Documentation](https://cmu-sei.github.io/crucible/)
- [Crucible GitHub Organization](https://github.com/cmu-sei)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [External Secrets Operator](https://external-secrets.io/)
- [cert-manager Documentation](https://cert-manager.io/docs/)

## License

Copyright 2025 Carnegie Mellon University. See LICENSE.md in the project root for license information.
