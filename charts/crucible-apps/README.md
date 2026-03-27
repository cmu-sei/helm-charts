# Crucible Apps Helm Chart

This Helm chart deploys the [Crucible](https://cmu-sei.github.io/crucible/) platform applications, including Keycloak identity provider and all Crucible services (Player, Caster, Alloy, Blueprint, CITE, Gallery, Gameboard, Steamfitter, TopoMojo, and Moodle).

## Overview

The crucible-apps chart can be deployed with:

- **crucible-infra chart** - provides PostgreSQL, ingress controller, NFS storage provisioner, and pre-created NFS PVCs
- **External PostgreSQL** - RDS, Cloud SQL, Azure Database, or any PostgreSQL service
- **Custom infrastructure** - bring your own PostgreSQL, ingress, and storage

### Components

Chart components are enabled by default, but can be disabled via the values file.

#### Crucible Framework

- **Alloy**: Exercise event orchestration
- **Blueprint**: Exercise design and templating
- **Caster**: Infrastructure-as-Code orchestration
- **CITE**: Collaborative incident threat evaluator
- **Gallery**: Content library and exhibit management
- **Gameboard**: Competitive cyber exercise platform
- **Player**: Exercise player interface and VM management
- **Steamfitter**: Scenario automation and simulation
- **TopoMojo**: Virtual machine lab management

#### Third Party Apps

- **Keycloak**: Identity and access management for all Crucible applications (deployed via the Keycloak Operator)
- **Moodle**: Learning management system integration

## Prerequisites

1. **Kubernetes 1.19+**
2. **Helm 3.0+**
3. **[Keycloak Operator](https://www.keycloak.org/operator/installation)** installed in the cluster (provides the `Keycloak` and `KeycloakRealmImport` CRDs)
4. **PostgreSQL database** provided by the crucible-infra chart, cloud database, or another cluster-accessible PostgreSQL source
5. **Ingress controller** provided by the crucible-infra chart (nginx) or use your own
6. **Persistent storage** provided by the crucible-infra chart (NFS provisioner and pre-created PVCs) or use your StorageClass
7. **TLS certificate** created as a Kubernetes secret
8. **Keycloak realm configuration** (optional - can be configured via UI after deployment)
9. **OAuth client secrets** generated and configured

The [crucible-operators chart](../crucible-operators) can be used to install the Keycloak Operator (and PostgreSQL Operator) before deploying this chart.

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

### 2. Keycloak Realm Configuration

The chart supports three mutually exclusive modes for realm configuration:

**Option A: Auto-Generated Realm (Recommended for Dev/Eval)**

Set `keycloak.createRealm: true` in your values. The chart will:

- Generate unique OIDC client secrets for each confidential client
- Persist secrets in a `crucible-oidc-client-secrets` Kubernetes Secret (survives upgrades)
- Create a `KeycloakRealmImport` custom resource with the generated secrets injected

```yaml
keycloak:
  createRealm: true
  realmAdminUsername: "admin"        # optional, defaults to "admin"
  realmAdminEmail: "admin@crucible.dev"  # optional
  realmAdminPassword: ""             # optional, random if empty
```

To retrieve generated secrets after deployment:

```bash
kubectl get secret crucible-oidc-client-secrets -o jsonpath='{.data.grafana}' | base64 --decode
```

**Option B: Import User-Provided Realm**

Set `keycloak.importRealmSecret` to a pre-existing Secret name containing a `realm.json` key. The chart mounts this Secret into the Keycloak pod at `/opt/keycloak/data/import`:

```yaml
keycloak:
  importRealmSecret: "my-custom-realm"
```

**Option C: Manual Configuration (UI-Based, Chart Default)**

Leave both `createRealm` and `importRealmSecret` unset. Configure Keycloak manually via the admin UI at `https://<domain>/keycloak/admin` after deployment.

### 3. OAuth Client Secrets

When `keycloak.createRealm` is true, OIDC client secrets are automatically generated and injected into service Secrets. No manual configuration is needed.

When using `importRealmSecret` or manual configuration, you must configure OAuth client secrets in your values file (or via K8s secrets) to match the secrets in your Keycloak realm:

```yaml
alloy:
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

#### 1. Install crucible-operators First

```bash
# Install the operators chart (provides Keycloak Operator and PostgreSQL Operator)
helm install crucible-operators oci://registry.example.com/crucible-operators

# Wait for operators to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak-operator --timeout=300s
```

#### 2. Install crucible-infra

```bash
# Install the infrastructure chart (provides PostgreSQL, Ingress, NFS storage)
helm install crucible-infra oci://registry.example.com/crucible-infra

# Wait for infrastructure to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql --timeout=300s
```

#### 3. Prepare Security Prerequisites

Follow the [Security Prerequisites](#security-prerequisites) section to create:

- TLS certificate secret
- Keycloak realm Secret (optional - can configure via UI after deployment)
- OAuth client secrets configuration

#### 4. Create Your Values File

```yaml
global:
  domain: crucible.example.com
  ingress:
    className: nginx
  postgresql:
    serviceName: "crucible-infra-postgresql"
    secretName: "crucible-infra-postgresql"
    usernameKey: "username"
    passwordKey: "password"

keycloak:
  externalDatabase:
    host: "crucible-infra-postgresql"
    existingSecret: "crucible-infra-postgresql"
    existingSecretUserKey: "username"
    existingSecretPasswordKey: "password"

# Optional: Auto-generate realm with OIDC secrets
# keycloak:
#   createRealm: true

alloy:
  alloy-api:
    resourceOwnerAuthorization:
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

#### 5. Install the crucible-apps Chart

```bash
helm install crucible-apps sei/crucible-apps -f my-values.yaml
```

### Option B: Using External PostgreSQL (RDS, Cloud SQL, etc.)

If you're using an external PostgreSQL service:

#### 1. Install crucible-operators

```bash
helm install crucible-operators sei/crucible-operators
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak-operator --timeout=300s
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
- Keycloak realm Secret (optional - can configure via UI after deployment)
- OAuth client secrets configuration

#### 4. Create Your Values File

```yaml
global:
  domain: crucible.example.com
  ingress:
    className: nginx
  postgresql:
    # AWS RDS example
    serviceName: "my-db.abc123.us-east-1.rds.amazonaws.com"
    port: 5432
    secretName: "postgres-credentials"
    usernameKey: "username"
    passwordKey: "password"

keycloak:
  externalDatabase:
    host: "my-db.abc123.us-east-1.rds.amazonaws.com"
    existingSecret: "postgres-credentials"
    existingSecretUserKey: "username"
    existingSecretPasswordKey: "password"

alloy:
  alloy-api:
    resourceOwnerAuthorization:
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

#### 5. Install the crucible-apps Chart

```bash
helm install crucible-apps sei/crucible-apps -f my-values.yaml
```

**Note**: When using external PostgreSQL, you must also provide:

- An ingress controller (nginx, traefik, etc.)
- Persistent storage (StorageClass for PVCs)

## Configuration

### Global Settings

| Parameter                    | Description                         | Default   | Required |
| ---------------------------- | ----------------------------------- | --------- | -------- |
| `global.domain`              | Domain name for Crucible deployment | `""`      | **Yes**  |
| `global.namespace`           | Kubernetes namespace                | `default` | No       |
| `global.version`             | Version tag for Crucible components | `0.0.0`   | No       |
| `global.ingress.className`   | Ingress controller class name       | `""`      | **Yes**  |
| `global.ingress.annotations` | Common annotations for all ingress  | `{}`      | No       |

### Keycloak Configuration

Configure Keycloak identity provider settings used by all Crucible applications:

| Parameter                  | Description                                 | Default     | Required |
| -------------------------- | ------------------------------------------- | ----------- | -------- |
| `global.keycloak.basePath` | Base path for Keycloak (relative to domain) | `/keycloak` | No       |
| `global.keycloak.realm`    | Keycloak realm name                         | `crucible`  | No       |

These settings are used to construct Keycloak URLs for OIDC authentication across all applications. Changing these values will update the authority, authorization, and token URLs for all integrated services.

#### Realm Import Configuration

| Parameter                       | Description                                                                       | Default            |
| ------------------------------- | --------------------------------------------------------------------------------- | ------------------ |
| `keycloak.createRealm`          | Auto-generate OIDC secrets and `admin` user password to create a `KeycloakRealmImport` CR | `false`  |
| `keycloak.realmAdminPassword`   | Password for realm `admin` user (random if empty, only with `createRealm`)        | `""`               |
| `keycloak.realmAdminUsername`   | Username for the default admin user in the realm (only with `createRealm`)        | `admin`            |
| `keycloak.realmAdminEmail`      | Email for the default admin user in the realm (only with `createRealm`)           | `admin@crucible.dev` |
| `keycloak.importRealmSecret`    | Import realm from an existing Secret name (must contain a `realm.json` key)       | `""`               |

These two options are mutually exclusive. See [Security Prerequisites](#security-prerequisites) for details on each mode.

When `createRealm` is true, the chart generates a `crucible-oidc-client-secrets` Secret (with `helm.sh/resource-policy: keep`) and a `KeycloakRealmImport` custom resource. The Keycloak Operator handles the actual realm import — no extra `extraEnvVars`, `extraVolumes`, or `extraVolumeMounts` configuration is needed.

**All OIDC client secrets and the default admin password are randomly generated when using `createRealm`.**

#### Operator & Instance Configuration

| Parameter            | Description                                   | Default |
| -------------------- | --------------------------------------------- | ------- |
| `keycloak.enabled`   | Enable Keycloak deployment                    | `true`  |
| `keycloak.instances` | Number of Keycloak replicas                   | `1`     |

**Password Management**: The Keycloak Operator automatically creates an initial admin secret named `<release-name>-keycloak-initial-admin`. To retrieve the admin credentials:

```bash
kubectl get secret <release-name>-keycloak-initial-admin -o jsonpath='{.data.username}' | base64 --decode
kubectl get secret <release-name>-keycloak-initial-admin -o jsonpath='{.data.password}' | base64 --decode
```

**Realm Import**: When `createRealm` is true, a `KeycloakRealmImport` CR is created. The Operator imports the realm on first startup. If the realm already exists, it will **not** be overwritten.

#### Keycloak Ingress Configuration

| Parameter                           | Description                              | Default |
| ----------------------------------- | ---------------------------------------- | ------- |
| `keycloak.ingress.enabled`          | Enable ingress for Keycloak              | `true`  |
| `keycloak.ingress.ingressClassName` | Ingress class (defaults to `global.ingress.className`) | `""` |
| `keycloak.ingress.tlsSecretName`    | TLS secret name (defaults to `crucible-cert`) | `""` |
| `keycloak.ingress.annotations`      | Additional ingress annotations           | `{}`    |

#### Keycloak Database Configuration

| Parameter                                          | Description                              | Default    |
| -------------------------------------------------- | ---------------------------------------- | ---------- |
| `keycloak.externalDatabase.host`                   | PostgreSQL hostname or service name      | `""`       |
| `keycloak.externalDatabase.port`                   | PostgreSQL port                          | `5432`     |
| `keycloak.externalDatabase.database`               | Database name for Keycloak               | `keycloak` |
| `keycloak.externalDatabase.existingSecret`         | Secret name containing DB credentials   | `""`       |
| `keycloak.externalDatabase.existingSecretUserKey`  | Key in secret for username               | `username` |
| `keycloak.externalDatabase.existingSecretPasswordKey` | Key in secret for password            | `password` |

### PostgreSQL Connection Settings

Configure connection to your PostgreSQL database.

| Parameter                       | Description                         | Default    | Required |
| ------------------------------- | ----------------------------------- | ---------- | -------- |
| `global.postgresql.serviceName` | PostgreSQL service name or hostname | `""`       | **Yes**  |
| `global.postgresql.port`        | PostgreSQL port                     | `5432`     | No       |
| `global.postgresql.secretName`  | Secret containing credentials       | `""`       | **Yes**  |
| `global.postgresql.usernameKey` | Key in secret containing username   | `username` | No       |
| `global.postgresql.passwordKey` | Key in secret containing password   | `password` | No       |

**Examples:**

```yaml
# Using crucible-infra chart
global:
  postgresql:
    serviceName: "crucible-infra-postgresql"
    secretName: "crucible-infra-postgresql"
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
```

### Application-Specific Secrets

Several applications require OAuth client secrets and service account credentials for inter-service communication. When `keycloak.createRealm` is true, these are auto-generated and injected — no manual configuration required.

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
      authority: "https://{{ .Values.global.domain }}/keycloak/realms/crucible" # Auto-populated
      clientId: "alloy.admin"
      clientSecret: "" # Required: OAuth client secret from Keycloak
      userName: "" # Required: Service account username
      password: "" # Required: Service account password
```

#### Blueprint Service Account

Blueprint requires a service account to communicate with CITE, Gallery, Player, and Steamfitter.

```yaml
blueprint:
  blueprint-api:
    resourceOwnerAuthorization:
      authority: "https://{{ .Values.global.domain }}/keycloak/realms/crucible" # Auto-populated
      clientId: "blueprint.admin"
      clientSecret: "" # Required: OAuth client secret from Keycloak
      userName: "" # Required: Service account username
      password: "" # Required: Service account password
```

#### Caster Service Account

Caster requires a service account (client credentials) to communicate with Player and Player VM API.

```yaml
caster:
  caster-api:
    client:
      userName: "" # Required: Service account username
      password: "" # Required: Service account password
```

#### Steamfitter Service Account

Steamfitter requires a service account to communicate with Player and VM API.

```yaml
steamfitter:
  steamfitter-api:
    resourceOwnerAuthorization:
      authority: "https://{{ .Values.global.domain }}/keycloak/realms/crucible" # Auto-populated
      clientId: "steamfitter.admin"
      clientSecret: "" # Required: OAuth client secret from Keycloak
      userName: "" # Required: Service account username
      password: "" # Required: Service account password
```

#### Gameboard Game Engine

Gameboard requires a client secret to interact with TopoMojo for deploying challenges.

```yaml
gameboard:
  gameboard-api:
    gameEngineClientSecret: "" # Required: TopoMojo client secret from Keycloak
```

### Hypervisor Configuration

Some Crucible applications (Player VM API, Caster, TopoMojo) require configuration to connect to your virtualization infrastructure. Each service has different configuration requirements based on its role.

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
      Vsphere__DsName: "datastore1" # DataStore name
      Vsphere__BaseFolder: "player" # Folder inside DataStore
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
      Proxmox__Port: 8006 # Default Proxmox port, use 443 if behind reverse proxy
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
      Pod__HypervisorType: "Vsphere" # Options: "Vsphere" or "Proxmox"
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
      Pod__PoolPath: "" # Optional: Proxmox pool path
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

### OIDC Client Secrets

When `keycloak.createRealm` is true, the chart creates a `crucible-oidc-client-secrets` Secret with `helm.sh/resource-policy: keep`. This Secret persists across `helm upgrade` and `helm uninstall`. To remove it manually:

```bash
kubectl delete secret crucible-oidc-client-secrets
```

To retrieve a generated secret:

```bash
kubectl get secret crucible-oidc-client-secrets -o jsonpath='{.data.<key>}' | base64 --decode
# Keys: alloy-admin, gameboard-api, player-vm-webhooks, grafana, moodle-client
```

### Keycloak Operator Not Installed

If you see errors about unknown CRDs (`keycloaks.k8s.keycloak.org`, `keycloakrealmimports.k8s.keycloak.org`), the Keycloak Operator is not installed:

```bash
# Check if CRDs are present
kubectl get crd keycloaks.k8s.keycloak.org

# Install via crucible-operators chart or follow the operator installation guide:
# https://www.keycloak.org/operator/installation
```

### Keycloak Admin Credentials

The Keycloak Operator creates an initial admin secret automatically:

```bash
# Retrieve operator-managed admin credentials
kubectl get secret <release-name>-keycloak-initial-admin -o jsonpath='{.data.username}' | base64 --decode
kubectl get secret <release-name>-keycloak-initial-admin -o jsonpath='{.data.password}' | base64 --decode
```

### Realm Secret Not Found

If you see an error about the realm Secret not being found:

```bash
# When using createRealm, a KeycloakRealmImport CR is auto-generated
kubectl get keycloakrealmimport <release-name>-realm

# When using importRealmSecret, verify the source Secret exists
kubectl get secret <your-secret-name>
kubectl describe secret <your-secret-name>
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
   kubectl get keycloakrealmimport <release-name>-realm -o jsonpath='{.status}'
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
- [CMU SEI GitHub Organization](https://github.com/cmu-sei)
- [Keycloak Operator Documentation](https://www.keycloak.org/operator/installation)
- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [External Secrets Operator](https://external-secrets.io/)
- [cert-manager Documentation](https://cert-manager.io/docs/)

## License

Copyright 2025 Carnegie Mellon University. See LICENSE.md in the project root for license information.
