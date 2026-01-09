# Crucible Infrastructure Helm Chart

This Helm chart deploys the foundational infrastructure components for the [Crucible](https://cmu-sei.github.io/crucible/) platform, including ingress controller, PostgreSQL database, NFS storage provisioner, and pgAdmin for database management.

## Overview

The crucible-infra chart provides the core infrastructure services that the Crucible applications depend on. It is designed to be deployed before the `crucible` and `crucible-monitoring` charts.

**The default values file for this chart is designed as a development deployment typically used with the [Crucible Dev Container](https://github.com/cmu-sei/crucible-development).**

### Components

Chart components are enabled by default, but can be disabled via the values file.

- **Ingress NGINX**: Routes external traffic to services within the cluster
- **PostgreSQL**: Primary database for all Crucible applications
- **pgAdmin**: Web-based PostgreSQL management interface
- **NFS Server Provisioner**: Provides dynamic NFS-backed persistent volumes for shared storage

## Prerequisites

1. Kubernetes 1.19+
2. Helm 3.0+
3. Sufficient cluster resources for database and storage

## Quick Start

### 1. Add the Helm Repository

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm repo update
```

### 2. Configure Certificate Management

⚠️ **Required**: This chart requires TLS certificates. Choose one of these options:

- [Use cert-manager](#option-1-use-cert-manager) for automated certificate management
- [Create Kubernetes secret](#option-2-use-existing-tls-secret-recommended-for-development) from existing certificates
- [Create from files](#option-3-create-tls-secret-from-files) (requires local chart copy)

See [TLS Certificates](#tls-certificates) section below for detailed instructions.

### 3. Create Your Values File

```yaml
# my-values.yaml
global:
  domain: crucible.example.com

tls:
  create: false  # Use cert-manager or existing secret
  secretName: crucible-cert

# Optional: Custom CA certificates
caCerts:
  create: false
  configMapName: crucible-ca-cert
```

### 4. Install the Chart

```bash
# With cert-manager or existing secrets
helm install crucible-infra sei/crucible-infra -f my-values.yaml

# Or from local chart directory
helm install crucible-infra ./crucible-infra -f my-values.yaml
```

## Configuration

### Global Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.domain` | Domain name for Crucible deployment | `""` |
| `global.namespace` | Kubernetes namespace | `default` |

### NFS Server Provisioner

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nfs-server-provisioner.enabled` | Enable NFS server provisioner | `true` |
| `nfs-server-provisioner.persistence.enabled` | Enable persistent storage for NFS | `true` |
| `nfs-server-provisioner.persistence.size` | Size of NFS server storage | `10Gi` |

The NFS server provisioner creates a StorageClass named `nfs` that can be used by applications requiring `ReadWriteMany` access mode.

### Ingress NGINX

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ingress-nginx.enabled` | Enable ingress controller | `true` |
| `ingress-nginx.controller.config.hsts` | Enable HTTP Strict Transport Security | `false` |
| `ingress-nginx.controller.allowSnippetAnnotations` | Allow snippet annotations | `true` |


### PostgreSQL

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgresql.enabled` | Enable PostgreSQL database | `true` |
| `postgresql.image.tag` | PostgreSQL image version | `17` |
| `postgresql.env.vars.POSTGRES_USER` | PostgreSQL superuser name | `postgres` |
| `postgresql.env.vars.POSTGRES_DB` | Default database name | `postgres` |
| `postgresql.persistence.enabled` | Enable persistent storage | `true` |
| `postgresql.persistence.size` | Size of database storage | `10Gi` |

**Password Management**: The PostgreSQL password is automatically generated on first install and persisted using the `helm.sh/resource-policy: keep` annotation. The password will be maintained across chart upgrades. To retrieve the password:

```bash
kubectl get secret crucible-infra-postgresql -o jsonpath='{.data.postgres-password}' | base64 --decode
```

**Postgres password(s) should be properly managed by kubernetes secrets in production deployments.**

### pgAdmin

| Parameter | Description | Default |
|-----------|-------------|---------|
| `pgadmin4.enabled` | Enable pgAdmin | `true` |
| `pgadmin4.env.email` | Admin user email | `admin@crucible.local` |
| `pgadmin4.env.contextPath` | URL context path for path-based hosting | `/pgadmin` |
| `pgadmin4.ingress.enabled` | Enable ingress for pgAdmin | `true` |
| `pgadmin4.env.variables`   | List additional env vars for pgadmin4 here | `- name: PGADMIN_CONFIG_ALLOW_SPECIAL_EMAIL_DOMAINS`<br>` value: "['local']"` |

**Access pgAdmin**: After deployment, pgAdmin is accessible at `https://{{ .Values.global.domain }}/pgadmin`

The PostgreSQL server is pre-configured in pgAdmin using the connection details from the chart. To retrieve the pgAdmin password:

```bash
kubectl get secret crucible-infra-pgadmin -o jsonpath='{.data.password}' | base64 --decode
```

**Note**: If you change the TLS secret name via `tls.secretName`, you must also update the pgAdmin ingress configuration:

```yaml
tls:
  secretName: my-custom-tls-secret

pgadmin4:
  ingress:
    tls:
      - hosts:
          - "{{ .Values.global.domain }}"
        secretName: my-custom-tls-secret
```

#### Network Security
- pgAdmin is exposed via ingress by default - consider restricting access via:
  - Ingress annotations for authentication (e.g., oauth2-proxy)
  - Network policies
  - Firewall rules
- PostgreSQL is only accessible within the cluster by default

### TLS Certificates

The chart provides flexible TLS certificate management for ingress resources. **By default, TLS secret creation is disabled** (`tls.create: false`), requiring you to provide certificates via one of the methods below.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `tls.create` | Create TLS secret from certificate files | `false` |
| `tls.certFile` | Path to certificate file (e.g., `files/tls.crt`) | `""` |
| `tls.keyFile` | Path to key file (e.g., `files/tls.key`) | `""` |
| `tls.secretName` | Name of TLS secret to create/reference | `crucible-cert` |

#### Option 1: Use cert-manager

[cert-manager](https://cert-manager.io/) automates certificate issuance and renewal from certificate authorities like Let's Encrypt.

**Prerequisites:**
1. [Install cert-manager](https://cert-manager.io/docs/installation/) in your cluster
2. Create a ClusterIssuer or Issuer resource

**Example: Let's Encrypt with cert-manager**

```yaml
# values.yaml
global:
  domain: crucible.example.com

tls:
  create: false  # cert-manager will create the secret
  secretName: crucible-cert  # cert-manager will populate this secret

pgadmin4:
  ingress:
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-prod"
    tls:
      - hosts:
          - crucible.example.com
        secretName: crucible-cert
```

**ClusterIssuer example:**
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

Deploy the chart and cert-manager will automatically request and install certificates.

#### Option 2: Use Existing TLS Secret

If you already have certificates, create a Kubernetes secret before installing the chart.

**Create the TLS secret:**
```bash
# Create TLS secret from your certificate files
kubectl create secret tls crucible-cert \
  --cert=/path/to/tls.crt \
  --key=/path/to/tls.key \
  --namespace default
```

**Configure the chart to use it:**
```yaml
# values.yaml
tls:
  create: false  # Use existing secret
  secretName: crucible-cert  # Must match your secret name
```

**Deploy the chart:**
```bash
helm install crucible-infra sei/crucible-infra -f values.yaml
```

#### Option 3: Create TLS Secret from Files

If deploying from a local chart directory, you can have the chart create the secret from certificate files.

**Add certificate files to the chart:**
```bash
# Copy your certificates to the chart's files/ directory
cp /path/to/tls.crt charts/crucible-infra/files/
cp /path/to/tls.key charts/crucible-infra/files/
```

**Configure values:**
```yaml
# values.yaml
tls:
  create: true  # Chart will create the secret
  certFile: "files/tls.crt"
  keyFile: "files/tls.key"
  secretName: crucible-cert
```

**Deploy from local chart:**
```bash
helm install crucible-infra ./charts/crucible-infra -f values.yaml
```

**Note:** Certificate files are **not** included in the chart by default. See [files/README.md](files/README.md) for detailed instructions.

**⚠️ Important:** This option requires deploying from a local chart directory and cannot be used when installing from a Helm repository.

### Custom CA Certificates

The chart supports loading custom CA certificates for applications that need to trust additional certificate authorities (e.g., corporate proxies like Zscaler, internal CAs). **By default, CA ConfigMap creation is disabled** (`caCerts.create: false`).

| Parameter | Description | Default |
|-----------|-------------|---------|
| `caCerts.create` | Create ConfigMap with CA certificates | `false` |
| `caCerts.configMapName` | Name of the CA certs ConfigMap | `crucible-ca-cert` |
| `caCerts.files` | Map of cert names to file paths | `{}` |

#### Option 1: Use Existing ConfigMap (Recommended)

If you already have CA certificates, create a ConfigMap before installing the chart.

**Create the ConfigMap:**
```bash
# Create ConfigMap from your CA certificate files
kubectl create configmap crucible-ca-cert \
  --from-file=corporate-ca.crt=/path/to/corporate-ca.crt \
  --from-file=internal-ca.crt=/path/to/internal-ca.crt \
  --namespace default
```

**Configure the chart to use it:**
```yaml
# values.yaml
caCerts:
  create: false  # Use existing ConfigMap
  configMapName: crucible-ca-cert  # Must match your ConfigMap name
```

**Deploy the chart:**
```bash
helm install crucible-infra sei/crucible-infra -f values.yaml
```

#### Option 2: Create ConfigMap from Files

If deploying from a local chart directory, you can have the chart create the ConfigMap from certificate files.

**Add CA certificate files to the chart:**
```bash
# Copy CA certificates to the chart's files/ directory
cp /path/to/corporate-ca.crt charts/crucible-infra/files/
cp /path/to/internal-ca.crt charts/crucible-infra/files/
```

**Configure values:**
```yaml
# values.yaml
caCerts:
  create: true  # Chart will create the ConfigMap
  configMapName: crucible-ca-cert
  files:
    corporate-ca.crt: "files/corporate-ca.crt"
    internal-ca.crt: "files/internal-ca.crt"
```

**Deploy from local chart:**
```bash
helm install crucible-infra ./charts/crucible-infra -f values.yaml
```

**Note:** Certificate files are **not** included in the chart by default. See [files/README.md](files/README.md) for details.

**⚠️ Important:** This option requires deploying from a local chart directory and cannot be used when installing from a Helm repository.

#### Using CA Certificates in Applications

The CA certificates ConfigMap can be mounted into application pods that need to trust these certificates. Crucible applications can mount this ConfigMap when available and configure the system to trust these CAs.

## Example Configurations

### Production Setup

```yaml
global:
  domain: crucible.example.com
  security:
    allowInsecureImages: false

postgresql:
  persistence:
    size: 100Gi
    storageClass: "fast-ssd"

nfs-server-provisioner:
  persistence:
    size: 100Gi
    storageClass: "standard"

ingress-nginx:
  controller:
    replicaCount: 3
```

### External PostgreSQL

If you have an existing PostgreSQL instance:

```yaml
postgresql:
  enabled: false

# Applications will need to be configured to use external PostgreSQL
# See the crucible chart documentation for connection string configuration
```

## Accessing Services

After deployment, infrastructure services are available:

- **pgAdmin**: `https://{{ .Values.global.domain }}/pgadmin`
- **PostgreSQL**: `{release-name}-postgresql.{namespace}.svc.cluster.local:5432` (cluster-internal)
- **NFS**: via the `nfs` StorageClass

## Security Considerations

### Password Management
- PostgreSQL and pgAdmin passwords are auto-generated on first install
- Passwords are persisted across upgrades via the `helm.sh/resource-policy: keep` annotation
- **Production deployments should**:
  - Use Kubernetes Secrets management (e.g., sealed-secrets, external-secrets)
  - Rotate passwords regularly
  - Use database authentication methods appropriate for your environment

### Network Security
- pgAdmin is exposed via ingress by default - consider restricting access via:
  - Ingress annotations for authentication (e.g., oauth2-proxy)
  - Network policies
  - Firewall rules
- PostgreSQL is only accessible within the cluster by default

## Troubleshooting

### PostgreSQL Connection Issues

If applications cannot connect to PostgreSQL:

1. Verify the PostgreSQL pod is running:
   ```bash
   kubectl get pods -l app.kubernetes.io/name=postgres
   ```

2. Check the service exists:
   ```bash
   kubectl get svc | grep postgresql
   ```

3. Verify the password secret exists:
   ```bash
   kubectl get secret {release-name}-postgresql
   ```

4. Test database connection from within the cluster:
   ```bash
   kubectl run -it --rm debug --image=postgres:17 --restart=Never -- psql \
     -h {release-name}-postgresql -U postgres -d postgres
   ```

### NFS Provisioner Issues

If PVCs remain in "Pending" status:

1. Check the NFS server provisioner pod:
   ```bash
   kubectl get pods -l app=nfs-server-provisioner
   kubectl logs -l app=nfs-server-provisioner
   ```

2. Verify the StorageClass was created:
   ```bash
   kubectl get storageclass nfs
   ```

3. Check PVC status details:
   ```bash
   kubectl describe pvc {pvc-name}
   ```

### Ingress Not Working

1. Verify the ingress controller is running:
   ```bash
   kubectl get pods -l app.kubernetes.io/name=ingress-nginx
   ```

2. Check ingress resources:
   ```bash
   kubectl get ingress
   ```

3. Verify DNS resolution for your domain

4. Check ingress controller logs:
   ```bash
   kubectl logs -l app.kubernetes.io/name=ingress-nginx -n {namespace}
   ```

## Upgrading

When upgrading the chart, secrets with `helm.sh/resource-policy: keep` annotation (PostgreSQL and pgAdmin passwords) will be preserved:

```bash
helm upgrade crucible-infra ./crucible-infra -f my-values.yaml
```

## Uninstallation

To remove the chart:

```bash
helm uninstall crucible-infra
```

**Note**: Secrets and PVCs with the `keep` resource policy will not be automatically deleted. To manually clean up:

```bash
# Delete secrets
kubectl delete secret crucible-infra-postgresql
kubectl delete secret crucible-infra-pgadmin

# Delete PVCs (WARNING: This will delete all data)
kubectl delete pvc -l app.kubernetes.io/instance=crucible-infra
```

## References

- [Crucible Documentation](https://cmu-sei.github.io/crucible/)
- [Ingress NGINX Documentation](https://kubernetes.github.io/ingress-nginx/)
- [PostgreSQL Chart](https://github.com/self-hosters-by-night/helm-charts/tree/main/charts/postgres)
- [NFS Server Provisioner](https://github.com/kubernetes-sigs/nfs-ganesha-server-and-external-provisioner)
