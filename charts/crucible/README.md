# Crucible Helm Chart

This Helm chart deploys the [Crucible](https://cmu-sei.github.io/crucible/) platform applications, including Keycloak identity provider and all Crucible services (Player, Caster, Alloy, Blueprint, CITE, Gallery, Gameboard, Steamfitter, TopoMojo, and Moodle).

## Overview

The crucible chart can be deployed with:
- **crucible-infra chart** (provides PostgreSQL, ingress controller, NFS storage provisioner, and pre-created NFS PVCs)
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
5. **Persistent storage** (crucible-infra chart provides NFS provisioner and pre-created PVCs, or use your StorageClass)
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
      # authority is auto-populated from global.domain
      clientSecret: "your-alloy-client-secret"
      userName: "admin"
      password: "your-service-account-password"

blueprint:
  blueprint-api:
    resourceOwnerAuthorization:
      clientSecret: "your-blueprint-client-secret"
      userName: "admin"
      password: "your-service-account-password"

caster:
  caster-api:
    client:
      userName: "admin"
      password: "your-service-account-password"

steamfitter:
  steamfitter-api:
    resourceOwnerAuthorization:
      clientSecret: "your-steamfitter-client-secret"
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

#### 1. Create PostgreSQL Credentials Secret

```bash
kubectl create secret generic postgres-credentials \
  --from-literal=username='crucible_admin' \
  --from-literal=password='your-postgres-password'
```

#### 2. Prepare Other Prerequisites

Follow the [Security Prerequisites](#security-prerequisites) section to create:
- TLS certificate secret
- Keycloak realm ConfigMap (optional - can configure via UI after deployment)
- OAuth client secrets configuration

#### 3. Create Your Values File

```yaml
global:
  domain: crucible.example.com
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
      # authority is auto-populated from global.domain
      clientSecret: "your-alloy-client-secret"
      userName: "admin"
      password: "your-service-account-password"

blueprint:
  blueprint-api:
    resourceOwnerAuthorization:
      clientSecret: "your-blueprint-client-secret"
      userName: "admin"
      password: "your-service-account-password"

caster:
  caster-api:
    client:
      userName: "admin"
      password: "your-service-account-password"

steamfitter:
  steamfitter-api:
    resourceOwnerAuthorization:
      clientSecret: "your-steamfitter-client-secret"
      userName: "admin"
      password: "your-service-account-password"

gameboard:
  gameboard-api:
    gameEngineClientSecret: "your-gameboard-client-secret"

# Note: You'll need to provide your own ingress controller and storage
```

#### 4. Install the Crucible Chart

```bash
helm install crucible sei/crucible -f my-values.yaml
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

Configure connection to your PostgreSQL database.

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
```

### Keycloak Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `keycloak.enabled` | Enable Keycloak deployment | `true` |
| `keycloak.auth.adminUser` | Keycloak admin username | `keycloak-admin` |
| `keycloak.httpRelativePath` | URL path for Keycloak | `/keycloak/` |
| `keycloak.postgresql.enabled` | Enable Keycloak's bundled PostgreSQL (always disabled) | `false` |

**Note**: The Keycloak subchart's bundled PostgreSQL is disabled by default. Keycloak uses the external PostgreSQL database (either from crucible-infra or your own external database) via the `keycloak.externalDatabase` configuration.

**Password Management**: The Keycloak admin password is automatically generated on first install and persisted. To retrieve it:

```bash
kubectl get secret <release-name>-keycloak-auth -o jsonpath='{.data.admin-password}' | base64 --decode
```

**Realm Import**: The chart imports the Keycloak realm configuration on first startup. If the realm already exists, it will **not** be overwritten.

### Application-Specific Secrets

Several applications require OAuth client secrets and service account credentials to be configured for inter-service communication.

**Note**: Authority URLs, authorization URLs, and token URLs are automatically populated with smart defaults based on `global.domain`. These defaults assume:
- Keycloak is accessible at `https://{{ .Values.global.domain }}/keycloak/`
- The realm name is `crucible`

If you use custom Keycloak paths or realm names, you can override these values in each application's configuration.

#### Alloy Service Account

Alloy requires a service account to communicate with other Crucible services (Player, Caster, Steamfitter).

```yaml
alloy:
  alloy-api:
    resourceOwnerAuthorization:
      authority: "https://{{ .Values.global.domain }}/keycloak/realms/crucible"  # Auto-populated
      clientId: "alloy.admin"
      clientSecret: ""  # Required: OAuth client secret from Keycloak
      userName: ""      # Required: Service account username
      password: ""      # Required: Service account password
```

#### Blueprint Service Account

Blueprint requires a service account to communicate with CITE, Gallery, Player, and Steamfitter.

```yaml
blueprint:
  blueprint-api:
    resourceOwnerAuthorization:
      authority: "https://{{ .Values.global.domain }}/keycloak/realms/crucible"  # Auto-populated
      clientId: "blueprint.admin"
      clientSecret: ""  # Required: OAuth client secret from Keycloak
      userName: ""      # Required: Service account username
      password: ""      # Required: Service account password
```

#### Caster Service Account

Caster requires a service account (client credentials) to communicate with Player and Player VM API.

```yaml
caster:
  caster-api:
    client:
      userName: ""  # Required: Service account username
      password: ""  # Required: Service account password
```

#### Steamfitter Service Account

Steamfitter requires a service account to communicate with Player and VM API.

```yaml
steamfitter:
  steamfitter-api:
    resourceOwnerAuthorization:
      authority: "https://{{ .Values.global.domain }}/keycloak/realms/crucible"  # Auto-populated
      clientId: "steamfitter.admin"
      clientSecret: ""  # Required: OAuth client secret from Keycloak
      userName: ""      # Required: Service account username
      password: ""      # Required: Service account password
```

#### Gameboard Game Engine

Gameboard requires a client secret to interact with TopoMojo for deploying challenges.

```yaml
gameboard:
  gameboard-api:
    gameEngineClientSecret: ""  # Required: TopoMojo client secret from Keycloak
```

### Hypervisor Configuration

Crucible services (Player VM API, Caster, TopoMojo) require configuration to connect to your virtualization infrastructure. Each service has different configuration requirements based on its role.

#### Player VM API - vSphere Configuration

The Player VM API manages virtual machines and requires a privileged vCenter user with read/write permissions. A dedicated datastore is required for storing Player files.

```yaml
player:
  vm-api:
    env:
      # VMware vSphere configuration
      Vsphere__Host: "vcenter.example.com"
      Vsphere__Username: "player-account@vsphere.local"
      Vsphere__Password: "your-password"
      Vsphere__DsName: "datastore1"              # DataStore name
      Vsphere__BaseFolder: "player"              # Folder inside DataStore
      # Optional: Console connection rewrite settings
      RewriteHost__RewriteHost: false
      RewriteHost__RewriteHostUrl: "connect.example.com"
      RewriteHost__RewriteHostQueryParam: "vmhost"
```

**Requirements:**
- Privileged vCenter account
- Dedicated datastore formatted as `<DATASTORE>/player/`
- Network access from Kubernetes cluster to vCenter

#### Player VM API - Proxmox Configuration

The Player VM API also supports Proxmox VE. Configure using an API token for authentication.

```yaml
player:
  vm-api:
    env:
      # Proxmox configuration
      Proxmox__Enabled: true
      Proxmox__Host: "proxmox.example.com"
      Proxmox__Port: 8006  # Default Proxmox port, use 443 if behind reverse proxy
      Proxmox__Token: "PVEAPIToken=player@pve!tokenid=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
      Proxmox__StateRefreshIntervalSeconds: 60
```

**Requirements:**
- Proxmox VE API token with appropriate permissions
- Network access from Kubernetes cluster to Proxmox host
- Token format: `PVEAPIToken=USER@REALM!TOKENID=UUID`

**Note:** Player VM API can be configured for either vSphere OR Proxmox, not both simultaneously.

#### Caster - vSphere Configuration

Caster uses Terraform with the vSphere provider to manage infrastructure-as-code deployments.

```yaml
caster:
  caster-api:
    env:
      # VMware vSphere configuration for Terraform
      VSPHERE_SERVER: "vcenter.example.com"
      VSPHERE_USER: "caster-account@vsphere.local"
      VSPHERE_PASSWORD: "your-password"
      VSPHERE_ALLOW_UNVERIFIED_SSL: true
```

**Requirements:**
- vCenter account with appropriate Terraform provider permissions
- See [Caster documentation](https://github.com/cmu-sei/caster) for required vSphere roles

#### TopoMojo - Hypervisor Pod Configuration

TopoMojo uses "Pod" terminology to refer to hypervisor connections. The Pod configuration supports **both vSphere and Proxmox** hypervisors. Specify which hypervisor type you're using with `Pod__HypervisorType`.

##### vSphere Configuration

```yaml
topomojo:
  topomojo-api:
    env:
      # Hypervisor type selection
      Pod__HypervisorType: "Vsphere"  # Options: "Vsphere" or "Proxmox"
      # VMware vSphere Pod configuration
      Pod__Url: "https://vcenter.example.com"
      Pod__User: "topomojo-account@vsphere.local"
      Pod__Password: "your-password"
      Pod__ConsoleUrl: "https://{{ .Values.global.domain }}/console"
      Pod__PoolPath: "/Datacenter/host/Cluster/Resources"
      Pod__Uplink: "vSwitch0"
      Pod__VmStore: "datastore1"
      Pod__IsoStore: "datastore1"
      Pod__DiskStore: "datastore1"
      Pod__TicketUrlHandler: "querystring"
      Pod__Vlan__Range: "1-4094"
      Pod__KeepAliveMinutes: 10
      Pod__DebugVerbose: false
```

##### Proxmox Configuration

```yaml
topomojo:
  topomojo-api:
    env:
      # Hypervisor type selection
      Pod__HypervisorType: "Proxmox"
      # Proxmox Pod configuration
      Pod__Url: "https://proxmox.example.com:8006"
      Pod__User: "topomojo@pve"
      Pod__Password: "your-password"
      Pod__ConsoleUrl: "https://{{ .Values.global.domain }}/console"
      Pod__PoolPath: ""  # Optional: Proxmox pool path
      Pod__VmStore: "local-lvm"
      Pod__IsoStore: "local"
      Pod__DiskStore: "local-lvm"
      Pod__TicketUrlHandler: "querystring"
      Pod__Vlan__Range: "1-4094"
      Pod__KeepAliveMinutes: 10
      Pod__DebugVerbose: false
```

**Proxmox Requirements:**
- Proxmox VE user account with appropriate permissions
- Storage pools for VMs, ISOs, and disks
- Network configuration (VLAN support if using VLANs)
- API access from Kubernetes cluster

##### NSX-T / VMware Cloud (VMC) Configuration

For advanced networking with NSX-T or VMware Cloud on AWS:

```yaml
topomojo:
  topomojo-api:
    env:
      # Standard Pod configuration (as above)...
      # Plus NSX/SDDC settings:
      Pod__IsNsxNetwork: true
      Pod__Sddc__ApiUrl: "https://nsx-manager.example.com"
      Pod__Sddc__MetadataUrl: "https://metadata.example.com"
      Pod__Sddc__SegmentApiPath: "policy/api/v1/infra/tier-1s/cgw/segments"
      Pod__Sddc__ApiKey: "your-api-key"
      Pod__Sddc__AuthUrl: "https://console.cloud.vmware.com"
      Pod__Sddc__CertificatePath: "/path/to/cert.pfx"
      Pod__Sddc__CertificatePassword: "cert-password"
```

**vSphere Requirements:**
- vCenter account with VM management permissions
- Storage datastores for VMs, ISOs, and disks
- Network configuration (VLAN range, uplink)

**NSX-T/VMC Additional Requirements:**
- NSX-T Manager API access with appropriate permissions
- SDDC segment management capabilities

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

## References

- [Crucible Documentation](https://cmu-sei.github.io/crucible/)
- [Crucible GitHub Organization](https://github.com/cmu-sei)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [External Secrets Operator](https://external-secrets.io/)
- [cert-manager Documentation](https://cert-manager.io/docs/)

## License

Copyright 2025 Carnegie Mellon University. See LICENSE.md in the project root for license information.
