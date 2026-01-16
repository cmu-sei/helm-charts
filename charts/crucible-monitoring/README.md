# Crucible Monitoring Helm Chart

This Helm chart deploys the monitoring and observability stack for the [Crucible](https://cmu-sei.github.io/crucible/) platform, including Prometheus, Grafana, Loki, Tempo, and Grafana Alloy for comprehensive metrics, logs, and traces collection.

**The default values file for this chart is designed as a development deployment typically used with the [Crucible Dev Container](https://github.com/cmu-sei/crucible-development).**

## Overview

The crucible-monitoring chart provides a complete observability solution for Crucible applications, implementing the LGTM stack (Loki for logs, Grafana for visualization, Tempo for traces, and Mimir/Prometheus for metrics).

### Components

Chart components are enabled by default, but can be disabled via the values file.

- [Prometheus](https://prometheus.io/docs/introduction/overview/): Metrics collection and storage with remote-write receiver
- [Grafana](https://grafana.com/docs/grafana/latest/): Visualization dashboards with Keycloak OAuth integration
- [Grafana Loki](https://grafana.com/docs/loki/latest/): Log aggregation and querying
- [Grafana Tempo](https://grafana.com/docs/tempo/latest/): Distributed tracing with OpenTelemetry support
- [Grafana Alloy](https://grafana.com/docs/alloy/latest/): OpenTelemetry collector for routing logs, metrics, and traces

## Prerequisites

1. Kubernetes 1.19+
2. Helm 3.0+
3. **Ingress Controller** - Required for Grafana access
4. **TLS Certificate** - Required for ingress (see [TLS Configuration](#tls-configuration))
5. **Keycloak** - Optional for Grafana OAuth

## Installation

### Quick Start

```bash
# 1. Create a TLS secret for ingress
kubectl create secret tls my-tls-secret \
  --cert=/path/to/tls.crt \
  --key=/path/to/tls.key

# 2. Create a values file with your TLS secret name
cat > my-values.yaml <<EOF
global:
  tlsSecretName: my-tls-secret
EOF

# 3. Install monitoring stack
helm install crucible-monitoring ./crucible-monitoring -f my-values.yaml

# 4. Access Grafana
# Navigate to https://<your-domain>/grafana
```

## Configuration

### Global Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.domain` | Domain name for Crucible deployment | `""` |
| `global.namespace` | Kubernetes namespace | `default` |
| `global.tlsSecretName` | TLS secret name for Grafana ingress | `""` (required) |

### TLS Configuration

The chart requires a TLS certificate secret for the Grafana ingress. You **must** provide a TLS secret name via `global.tlsSecretName`.

You can either:
- Create the secret before deployment using `kubectl create secret tls`
- Reference an existing secret
- Use cert-manager to automatically provision certificates

To configure the TLS secret name, set it in your values file:
```yaml
global:
  tlsSecretName: my-tls-secret  # Your TLS secret name
```

The TLS secret will be automatically used by the Grafana ingress via the template `{{ .Values.global.tlsSecretName }}`.

### Custom CA Certificates

| Parameter | Description | Default |
|-----------|-------------|---------|
| `caCerts.enabled` | Enable custom CA certificate mounting | `false` |
| `caCerts.configMapName` | Name of ConfigMap containing CA certificates | `""` (must be set if enabled) |

**When to enable**: Set `caCerts.enabled: true` if your environment requires trusting additional CA certificates (e.g., corporate proxy, internal PKI).

**How it works**:
- **All** certificate files in the ConfigMap are automatically mounted and trusted
- No specific key names are required - any certificate files will work
- Supports `.crt`, `.pem`, `.cer` file extensions
- Certificates are mounted into Grafana, Loki, and Grafana Alloy pods

**Example**:
```yaml
# values.yaml
caCerts:
  enabled: true
  configMapName: my-ca-certs

# Create ConfigMap with any number of certificate files
kubectl create configmap my-ca-certs \
  --from-file=corporate-ca.crt=/path/to/corporate-ca.crt \
  --from-file=proxy-ca.crt=/path/to/proxy-ca.crt \
  --from-file=internal-ca.pem=/path/to/internal-ca.pem
```

### Prometheus

| Parameter | Description | Default |
|-----------|-------------|---------|
| `prometheus.enabled` | Enable Prometheus deployment | `true` |
| `prometheus.server.extraArgs` | Additional server arguments | `web.enable-remote-write-receiver: ""` |

**Remote Write Receiver**: Enabled by default to accept metrics from Grafana Alloy.

### Grafana

| Parameter | Description | Default |
|-----------|-------------|---------|
| `grafana.enabled` | Enable Grafana deployment | `true` |
| `grafana.ingress.enabled` | Enable ingress | `true` |
| `grafana.grafana.ini.auth.disable_login_form` | Disable login form (OAuth only) | `true` |
| `grafana.env.GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET` | Keycloak OAuth client secret |  |

**Datasources**: Grafana is pre-configured with datasources for:
- Prometheus (metrics)
- Loki (logs)
- Tempo (traces)

**Access**: `https://{{ .Values.global.domain }}/grafana`

### Loki

| Parameter | Description | Default |
|-----------|-------------|---------|
| `loki.enabled` | Enable Loki deployment | `true` |
| `loki.deploymentMode` | Deployment mode | `SingleBinary` |
| `loki.singleBinary.persistence.size` | Storage size | `5Gi` |

**SingleBinary Mode**: Simplified deployment suitable for development and small-scale production. All Loki components run in a single pod.

### Tempo

| Parameter | Description | Default |
|-----------|-------------|---------|
| `tempo.enabled` | Enable Tempo deployment | `true` |
| `tempo.persistence.size` | Storage size | `5Gi` |
| `tempo.tempo.receivers.otlp` | OTLP receiver config | Enabled on ports 4317/4318 |

**OpenTelemetry**: Applications can send traces directly to Tempo but via Grafana Alloy is preferred.

### Grafana Alloy

| Parameter | Description | Default |
|-----------|-------------|---------|
| `grafana-alloy.enabled` | Enable Grafana Alloy | `true` |
| `grafana-alloy.controller.type` | Controller type | `daemonset` |

When enabled, Alloy:
- Collects logs from all pods and sends to Loki
- Scrapes Prometheus metrics from pods
- Receives OTLP telemetry on ports 4317 (gRPC) and 4318 (HTTP)
- Routes traces to Tempo
- Routes metrics to Prometheus


## Accessing Services

After deployment:

| Service | URL | Purpose |
|---------|-----|---------|
| Grafana | `https://{{ .Values.global.domain }}/grafana` | Dashboards and visualization |
| Prometheus | `http://{release-name}-prometheus-server` (cluster-internal) | Metrics API |
| Loki | `http://{release-name}-loki:3100` (cluster-internal) | Logs API |
| Tempo | `http://{release-name}-tempo:3100` (cluster-internal) | Traces API |

## Integrating Applications

Grafana Alloy serves at the Open Telemetry Collector in this deployment. Applications should be configured to send OTLP to Alloy via the Kubernetes service address.

```yaml
OTEL_EXPORTER_OTLP_ENDPOINT: http://crucible-grafana-alloy:4317
```

## Troubleshooting

### Grafana Not Accessible

1. Verify ingress controller is running (from crucible-infra):
   ```bash
   kubectl get pods -l app.kubernetes.io/name=ingress-nginx
   ```

2. Check Grafana pod status:
   ```bash
   kubectl get pods -l app.kubernetes.io/name=grafana
   ```

3. Check ingress resource:
   ```bash
   kubectl get ingress -l app.kubernetes.io/instance=crucible-monitoring
   ```

### Grafana OAuth Not Working

1. Verify Keycloak is running:
   ```bash
   kubectl get pods -l app.kubernetes.io/name=keycloak
   ```

2. Check OAuth client secret matches Keycloak configuration

3. Verify redirect URI in Keycloak: `https://<domain>/grafana/login/generic_oauth`

### No Metrics in Grafana

1. Verify Prometheus is running and receiving metrics:
   ```bash
   kubectl port-forward svc/crucible-monitoring-prometheus-server 9090:80
   # Navigate to http://localhost:9090/targets
   ```

2. Check datasource configuration in Grafana

3. If using Grafana Alloy, check the logs:
   ```bash
   kubectl logs -l app.kubernetes.io/name=alloy
   ```

### No Logs in Grafana

1. Verify Loki is running:
   ```bash
   kubectl get pods -l app.kubernetes.io/name=loki
   ```

2. Check Loki logs for errors:
   ```bash
   kubectl logs -l app.kubernetes.io/name=loki
   ```

3. If using Grafana Alloy, verify it is collecting logs:
   ```bash
   kubectl logs -l app.kubernetes.io/name=alloy | grep loki
   ```

### Storage Issues

If PVCs remain in "Pending" status:

1. Verify storage class is available:
   ```bash
   kubectl get storageclass
   ```

2. Check PVC details:
   ```bash
   kubectl describe pvc -l app.kubernetes.io/instance=crucible-monitoring
   ```

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/grafana/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Tempo Documentation](https://grafana.com/docs/tempo/)
- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)

## License

Copyright 2025 Carnegie Mellon University. See LICENSE.md in the project root for license information.
