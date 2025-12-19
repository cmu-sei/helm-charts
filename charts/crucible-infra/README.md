# Crucible Infrastructure Helm Chart

This Helm chart deploys the foundational infrastructure components for the [Crucible](https://cmu-sei.github.io/crucible/) platform, including ingress controller, PostgreSQL database, NFS storage provisioner, and pgAdmin for database management.

## Overview

The crucible-infra chart provides the core infrastructure services that the Crucible applications depend on. It is designed to be deployed before the `crucible` and `crucible-monitoring` charts.

### Components

- **Ingress NGINX**: Routes external traffic to services within the cluster
- **PostgreSQL**: Primary database for all Crucible applications
- **pgAdmin**: Web-based PostgreSQL management interface
- **NFS Server Provisioner**: Provides dynamic NFS-backed persistent volumes for shared storage

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- Sufficient cluster resources for database and storage

## Installation

### Add the Helm Repository

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm repo update
```

### Install the Chart

```bash
# Install with default values
helm install crucible-infra ./crucible-infra

# Install with custom values
helm install crucible-infra ./crucible-infra -f my-values.yaml
```

## Configuration

### Global Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.domain` | Domain name for Crucible deployment | `crucible.local` |
| `global.namespace` | Kubernetes namespace | `default` |
| `global.version` | Version tag for Crucible components | `0.0.0` |
| `global.security.allowInsecureImages` | Allow images without security enforcement | `true` |

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
| `ingress-nginx.tcp.2049` | TCP port forwarding for NFS | Configured |

**Important**: The ingress controller is configured to forward TCP port 2049 to the NFS server provisioner service, allowing NFS clients to connect through the ingress.

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

### pgAdmin

| Parameter | Description | Default |
|-----------|-------------|---------|
| `pgadmin4.enabled` | Enable pgAdmin | `true` |
| `pgadmin4.env.email` | Admin user email | `admin@crucible.local` |
| `pgadmin4.env.contextPath` | URL context path | `/pgadmin` |
| `pgadmin4.ingress.enabled` | Enable ingress for pgAdmin | `true` |

**Access pgAdmin**: After deployment, pgAdmin is accessible at `https://{{ .Values.global.domain }}/pgadmin`

The PostgreSQL server is pre-configured in pgAdmin using the connection details from the chart. To retrieve the pgAdmin password:

```bash
kubectl get secret crucible-infra-pgadmin -o jsonpath='{.data.password}' | base64 --decode
```

### NFS Persistent Volume Claims

The chart creates several PVCs for use by Crucible applications:

| PVC Name | Purpose | Default Size |
|----------|---------|--------------|
| `{release-name}-nfs` | General shared storage | `10Gi` |
| `{release-name}-topomojo-api-nfs` | TopoMojo file storage | `10Gi` |
| `{release-name}-gameboard-api-nfs` | Gameboard file storage | `5Gi` |
| `{release-name}-caster-api-nfs` | Caster file storage | `5Gi` |

Configure PVC sizes:

```yaml
nfs:
  enabled: true
  size: "20Gi"              # General shared storage
  topomojoSize: "50Gi"      # TopoMojo storage
  gameboardSize: "10Gi"     # Gameboard storage
  casterSize: "10Gi"        # Caster storage
```

### Custom CA Certificates

The chart supports loading custom CA certificates from the `files/` directory:

- `files/crucible-dev.crt` - Development certificate
- `files/zscaler-ca.crt` - Corporate proxy certificate

These certificates are made available to all pods via the `crucible-ca-cert` ConfigMap. Applications that need to trust these certificates should mount this ConfigMap.

## Example Configurations

### Minimal Development Setup

```yaml
global:
  domain: crucible.dev

postgresql:
  persistence:
    size: 5Gi

nfs-server-provisioner:
  persistence:
    size: 5Gi
```

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

nfs:
  size: "50Gi"
  topomojoSize: "200Gi"
  gameboardSize: "50Gi"
  casterSize: "50Gi"

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
