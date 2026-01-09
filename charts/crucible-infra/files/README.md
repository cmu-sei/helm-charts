# Certificate Files Directory

This directory is used to store certificate files when deploying from a local chart with `tls.create: true` or `caCerts.create: true`.

## Security Notice

**Certificate and key files are excluded from version control** via `.gitignore` and `.helmignore`.

## Usage

### TLS Certificates

Place your certificate files here and reference them in your values file:

```yaml
tls:
  create: true
  certFile: "files/tls.crt"
  keyFile: "files/tls.key"
```

### CA Certificates

```yaml
caCerts:
  create: true
  files:
    corporate-ca.crt: "files/corporate-ca.crt"
```

## Recommended Approach

For production and most deployments, **do not** use files in this directory. Instead:

1. **Use cert-manager** for automatic certificate management
2. **Create Kubernetes secrets** before deployment using `kubectl create secret tls`

See the main [README.md](../README.md) for detailed certificate management instructions.
