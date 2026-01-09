# Crucible Helm Chart

This Helm chart deploys the [Crucible](https://cmu-sei.github.io/crucible/) platform applications, including Keycloak identity provider and all Crucible services (Player, Caster, Alloy, Blueprint, CITE, Gallery, Gameboard, Steamfitter, TopoMojo, and Moodle).

## Overview

The crucible chart is designed to work with the `crucible-infra` chart, which provides the foundational infrastructure (PostgreSQL, ingress controller, NFS storage). The default deployed assumes you have deployed `crucible-infra` first.

**The default values file for this chart is designed as a development deployment typically used with the [Crucible Dev Container](https://github.com/cmu-sei/crucible-development).**

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
3. **Default assumes crucible-infra chart is deployed first**
   - Provides PostgreSQL database
   - Provides ingress controller
   - Provides NFS storage
   - Provides CA certificate ConfigMap

## Installation

### Install crucible-infra First

```bash
# Install the infrastructure chart
helm install crucible-infra ./crucible-infra

# Wait for infrastructure to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=crucible-infra --timeout=300s
```

### Install the Crucible Chart

```bash
# Install with default values
helm install crucible ./crucible

# Install with custom values
helm install crucible ./crucible -f my-values.yaml
```

## Configuration

### Global Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.domain` | Domain name for Crucible deployment | `crucible.local` |
| `global.namespace` | Kubernetes namespace | `default` |
| `global.version` | Version tag for Crucible components | `0.0.0` |
| `global.security.allowInsecureImages` | Allow images without security enforcement | `true` |
| `global.tls.secretName` | TLS secret used by all ingresses | `crucible-cert` |

### PostgreSQL Connection Settings

The chart references PostgreSQL from the crucible-infra chart:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.postgresql.serviceName` | PostgreSQL service name from infra chart | `crucible-infra-postgresql` |
| `global.postgresql.port` | PostgreSQL port | `5432` |
| `global.postgresql.user` | PostgreSQL username | `postgres` |
| `global.postgresql.secretName` | Secret containing password | `crucible-infra-postgresql` |
| `global.postgresql.secretKey` | Key in secret for password | `postgres-password` |

**Important**: If you used a different release name for crucible-infra, update these values accordingly.

### NFS Storage References

The chart references NFS PVCs from the crucible-infra chart:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nfs.pvcName` | General shared NFS PVC | `crucible-infra-nfs` |
| `nfs.topomojoApiPvcName` | TopoMojo NFS PVC | `crucible-infra-topomojo-api-nfs` |
| `nfs.gameboardApiPvcName` | Gameboard NFS PVC | `crucible-infra-gameboard-api-nfs` |
| `nfs.casterApiPvcName` | Caster NFS PVC | `crucible-infra-caster-api-nfs` |

### Keycloak Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `keycloak.enabled` | Enable Keycloak deployment | `true` |
| `keycloak.auth.adminUser` | Keycloak admin username | `keycloak-admin` |
| `keycloak.httpRelativePath` | URL path for Keycloak | `/keycloak/` |
| `keycloak.externalDatabase.host` | PostgreSQL host (from infra) | `{{ .Values.global.postgresql.serviceName }}` |

**Password Management**: The Keycloak admin password is automatically generated on first install and persisted. To retrieve it:

```bash
kubectl get secret crucible-keycloak-auth -o jsonpath='{.data.admin-password}' | base64 --decode
```

**Realm Import**: The chart automatically imports the Crucible realm configuration on first Keycloak startup. If the realm already exists, it will **not** be overwritten.

### Application Configuration

All applications are pre-configured with:
- Ingress routes using the nginx ingress class
- PostgreSQL connection strings (automatically generated)
- Keycloak OAuth/OIDC integration
- Shared domain and TLS certificate
- CA certificate trust (from crucible-ca-cert ConfigMap)

## Example Configurations

### Minimal Deployment

Deploy only essential applications:

```yaml
global:
  domain: crucible.dev

# Disable optional applications
gameboard:
  enabled: false

moodle:
  enabled: false
```

### External PostgreSQL

If using a PostgreSQL instance outside the crucible-infra chart:

```yaml
postgresql:
  serviceName: "my-external-postgres.example.com"
  port: 5432
  user: "crucible"
  secretName: "external-postgres-secret"
  secretKey: "password"
```

### Custom Domain

```yaml
global:
  domain: crucible.example.com
```

All applications will be accessible at:
- `https://crucible.example.com/keycloak` - Keycloak admin console
- `https://crucible.example.com/player` - Player UI
- `https://crucible.example.com/alloy` - Alloy UI
- etc.

## Accessing Services

After deployment, services are accessible at:

| Service | URL |
|---------|-----|
| Keycloak Admin | `https://{{ .Values.global.domain }}/keycloak/admin/crucible/console/` |
| Player | `https://{{ .Values.global.domain }}/player` |
| Alloy | `https://{{ .Values.global.domain }}/alloy` |
| Blueprint | `https://{{ .Values.global.domain }}/blueprint` |
| Caster | `https://{{ .Values.global.domain }}/caster` |
| CITE | `https://{{ .Values.global.domain }}/cite` |
| Gallery | `https://{{ .Values.global.domain }}/gallery` |
| Gameboard | `https://{{ .Values.global.domain }}/gameboard` |
| Steamfitter | `https://{{ .Values.global.domain }}/steamfitter` |
| TopoMojo | `https://{{ .Values.global.domain }}/topomojo` |
| Moodle | `https://{{ .Values.global.domain }}/` |

## Troubleshooting

### Cannot Connect to PostgreSQL

If applications cannot connect to the database:

1. Verify crucible-infra is deployed and PostgreSQL is running:
   ```bash
   kubectl get pods -l app.kubernetes.io/name=postgres
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

### Keycloak Database Not Created

The chart includes a Job that creates the Keycloak database. If Keycloak fails to start:

1. Check the job status:
   ```bash
   kubectl get jobs
   kubectl logs job/crucible-postgres-create-keycloak-db
   ```

2. Manually create the database if needed:
   ```bash
   kubectl exec -it <postgres-pod> -- psql -U postgres -c "CREATE DATABASE keycloak;"
   ```

### Applications Not Accessible via Ingress

1. Verify the ingress controller is running (from crucible-infra):
   ```bash
   kubectl get pods -l app.kubernetes.io/name=ingress-nginx
   ```

2. Check ingress resources:
   ```bash
   kubectl get ingress
   ```

3. Verify DNS resolution for your domain

### NFS Storage Issues

If applications report storage errors:

1. Verify PVCs exist and are bound:
   ```bash
   kubectl get pvc
   ```

2. Check NFS provisioner status (from crucible-infra):
   ```bash
   kubectl get pods -l app=nfs-server-provisioner
   ```

## Upgrading

To upgrade the chart:

```bash
helm upgrade crucible ./crucible -f my-values.yaml
```

**Note**: Secrets with `helm.sh/resource-policy: keep` annotation (Keycloak admin password, TLS cert) are preserved during upgrades.

## Uninstallation

To remove the chart:

```bash
helm uninstall crucible
```

**Important**: This will not delete:
- Secrets with the `keep` resource policy (Keycloak password, TLS cert)
- Database data in PostgreSQL (managed by crucible-infra)
- PVCs (managed by crucible-infra)

To also remove the infrastructure:

```bash
helm uninstall crucible-infra
```

## References

- [Crucible Documentation](https://cmu-sei.github.io/crucible/)
- [Crucible Helm Charts Repository](https://github.com/cmu-sei/helm-charts)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
