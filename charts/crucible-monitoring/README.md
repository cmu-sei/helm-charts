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
3. **Default values assume crucible-infra chart is deployed first**
   - Provides ingress controller
   - Provides CA certificate ConfigMap
4. **Default values assume crucible chart is deployed first for Keycloak OAuth integration with Grafana. You can optionally disable Keycloak auth.**

## Installation

### Quick Start

```bash
# Install monitoring stack
helm install crucible-monitoring ./crucible-monitoring

# Access Grafana
# Navigate to https://<your-domain>/grafana
```

## Configuration

### Global Settings

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.domain` | Domain name for Crucible deployment | `crucible.local` |
| `global.namespace` | Kubernetes namespace | `default` |

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
| `grafana.env.GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET` | Keycloak OAuth client secret | `516aea1d...` |

**Important**: Change the OAuth client secret in production deployments.

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

**OpenTelemetry**: Applications can send traces directly to Tempo or via Grafana Alloy.

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

## Example Configurations

### Enable Grafana Alloy

```yaml
grafana-alloy:
  enabled: true
```

### Custom Storage Sizes

```yaml
loki:
  singleBinary:
    persistence:
      size: 50Gi

tempo:
  persistence:
    size: 100Gi
```

### Disable Components

```yaml
# Only deploy Prometheus and Grafana
loki:
  enabled: false

tempo:
  enabled: false

grafana-alloy:
  enabled: false
```

### Production Configuration

```yaml
global:
  domain: crucible.example.com

grafana:
  env:
    # Use a strong, unique client secret
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET: "your-secure-secret-here"

loki:
  singleBinary:
    replicas: 1
    persistence:
      enabled: true
      size: 100Gi
      storageClass: "fast-ssd"

tempo:
  replicas: 1
  persistence:
    enabled: true
    size: 50Gi
    storageClass: "fast-ssd"

prometheus:
  server:
    persistentVolume:
      enabled: true
      size: 50Gi
      storageClass: "fast-ssd"
```

## Accessing Services

After deployment:

| Service | URL | Purpose |
|---------|-----|---------|
| Grafana | `https://{{ .Values.global.domain }}/grafana` | Dashboards and visualization |
| Prometheus | `http://{release-name}-prometheus-server` (cluster-internal) | Metrics API |
| Loki | `http://{release-name}-loki:3100` (cluster-internal) | Logs API |
| Tempo | `http://{release-name}-tempo:3100` (cluster-internal) | Traces API |

## Integrating Applications

### Sending Metrics

Applications can expose Prometheus metrics and will be automatically scraped if Grafana Alloy is enabled. Alternatively, use remote-write:

```yaml
# Example: Prometheus remote-write configuration
remote_write:
  - url: http://crucible-monitoring-prometheus-server/api/v1/write
```

### Sending Logs

Applications can send logs to Loki:

```yaml
# Example: Loki endpoint
url: http://crucible-monitoring-loki:3100/loki/api/v1/push
```

### Sending Traces

Applications can send OpenTelemetry traces:

```yaml
# Via Grafana Alloy (if enabled)
OTEL_EXPORTER_OTLP_ENDPOINT: http://crucible-grafana-alloy:4317

# Or directly to Tempo
OTEL_EXPORTER_OTLP_ENDPOINT: http://crucible-monitoring-tempo:4317
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

3. If using Grafana Alloy, check its logs:
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

3. If using Grafana Alloy, verify it's collecting logs:
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

## Upgrading

To upgrade the chart:

```bash
helm upgrade crucible-monitoring ./crucible-monitoring -f my-values.yaml
```

## Uninstallation

To remove the chart:

```bash
helm uninstall crucible-monitoring
```

**Warning**: This will delete all collected metrics, logs, and traces if persistent volumes are not configured to retain data.

## References

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/grafana/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Tempo Documentation](https://grafana.com/docs/tempo/)
- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
