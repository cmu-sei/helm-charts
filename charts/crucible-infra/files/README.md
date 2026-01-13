# Local Files Directory

This directory is for storing certificate files when deploying from a **local copy** of the chart. Files placed here are automatically excluded from version control and packaged charts.

## Purpose

Use this directory to store environment-specific certificate files that should not be committed to the repository or published in the Helm chart package:

- **TLS certificates and keys** (`*.crt`, `*.key`, `*.pem`)
- **CA certificates** for corporate proxies or internal CAs

## Security Notice

**All certificate and key files are excluded from version control and chart packages** via `.gitignore` and `.helmignore`. This prevents accidental exposure of private keys and certificates with sensitive domain information.

## Usage

### TLS Certificates

When deploying from a local chart copy, you can place TLS certificate files here and reference them in your values:

```yaml
tls:
  create: true
  certFile: "files/tls.crt"
  keyFile: "files/tls.key"
  secretName: "crucible-cert"
```

**Example:**
```bash
# Copy your certificates to this directory
cp /path/to/your/tls.crt /path/to/chart/files/
cp /path/to/your/tls.key /path/to/chart/files/

# Deploy from local chart
helm install crucible-infra ./crucible-infra -f values.yaml
```

### CA Certificates

For custom CA certificates (corporate proxies, internal CAs):

```yaml
caCerts:
  create: true
  configMapName: "crucible-ca-cert"
  files:
    corporate-ca.crt: "files/corporate-ca.crt"
    internal-ca.crt: "files/internal-ca.crt"
```

**Example:**
```bash
# Copy CA certificates to this directory
cp /path/to/corporate-ca.crt /path/to/chart/files/
cp /path/to/internal-ca.crt /path/to/chart/files/

# Deploy from local chart
helm install crucible-infra ./crucible-infra -f values.yaml
```

## Recommended Approach

For production and most deployments, **avoid using files in this directory**. Instead, use more secure and automated approaches:

1. **TLS Certificates:**
   - Use [cert-manager](https://cert-manager.io/) for automatic certificate management
   - Create secrets manually: `kubectl create secret tls crucible-cert --cert=tls.crt --key=tls.key`

2. **CA Certificates:**
   - Create ConfigMaps: `kubectl create configmap crucible-ca-cert --from-file=ca.crt`
   - Use cluster-wide certificate authorities

## What Gets Excluded

The `.gitignore` and `.helmignore` patterns exclude:
- `*.crt`, `*.key`, `*.pem` - Certificate and key files
- `*.env`, `*.local` - Environment-specific configuration
- `*-dev.*`, `*-local.*` - Development and local-specific files

Only `README.md` is committed to version control.

See the main [README.md](../README.md) for detailed certificate management and deployment instructions.
