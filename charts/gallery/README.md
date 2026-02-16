# Gallery Helm Chart

[Gallery](https://cmu-sei.github.io/crucible/gallery/) is the [Crucible](https://cmu-sei.github.io/crucible/) application that enables participants to review cyber incident data by source type. Information is grouped by critical infrastructure sector or organizational categories, with support for multiple source types including intelligence, reporting, orders, news, social media, telephone, and email.

This Helm chart deploys Gallery with both [API](https://github.com/cmu-sei/Gallery.Api) and [UI](https://github.com/cmu-sei/Gallery.Ui) components.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database with `uuid-ossp` extension installed
- Identity provider (e.g., [Keycloak](https://www.keycloak.org/)) for OAuth2/OIDC authentication

## Installation

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm install gallery sei/gallery -f values.yaml
```

## Gallery API Configuration

The following are configured via the `gallery-api.env` settings. These Gallery API settings reflect the application's [appsettings.json](https://github.com/cmu-sei/Gallery.Api/blob/development/Gallery.Api/appsettings.json) which may contain more options than are described here.

### Database Settings

| Setting | Description | Example |
|---------|-------------|---------|
| `ConnectionStrings__PostgreSQL` | PostgreSQL connection string | `Server=postgres;Port=5432;Database=gallery;Username=gallery;Password=PASSWORD;` |

**Important:** The PostgreSQL database must include the `uuid-ossp` extension:

```sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
```

### Authentication (OIDC)

| Setting | Description | Example |
|---------|-------------|---------|
| `Authorization__Authority` | Identity provider base URL | `https://identity.example.com` |
| `Authorization__AuthorizationUrl` | Authorization endpoint | `https://identity.example.com/connect/authorize` |
| `Authorization__TokenUrl` | Token endpoint | `https://identity.example.com/connect/token` |
| `Authorization__AuthorizationScope` | OAuth scope requested by the API | `gallery-api` |
| `Authorization__ClientId` | OAuth client ID used by Swagger and other interactive clients | `gallery-api` |
| `Authorization__ClientName` | Display name for the client (optional) | `Gallery` |

### Certificate Trust

Trust custom certificate authorities by referencing a Kubernetes ConfigMap that contains the CA bundle.

```yaml
gallery-api:
  certificateMap: "custom-ca-certs"
```

### Helm Deployment Configuration

The following are configurations for the Gallery API Helm Chart and application configurations that are configured outside of the `gallery-api.env` section.

#### Ingress

Configure the ingress to allow connections to the application (typically uses an ingress controller like [ingress-nginx](https://github.com/kubernetes/ingress-nginx)).

```yaml
gallery-api:
  ingress:
    enabled: true
    className: "nginx"
    annotations:
      nginx.ingress.kubernetes.io/proxy-read-timeout: "86400"
      nginx.ingress.kubernetes.io/proxy-send-timeout: "86400"
      nginx.ingress.kubernetes.io/use-regex: "true"
    hosts:
      - host: gallery.example.com
        paths:
          - path: /(api|swagger|hubs)
            pathType: ImplementationSpecific
```

### OpenTelemetry

Gagllery.Api is wired with [Crucible.Common.ServiceDefaults](https://github.com/cmu-sei/crucible-common-dotnet/tree/main/src/Crucible.Common.ServiceDefaults), which auto-enables [OpenTelemetry](https://opentelemetry.io/) logs/traces/metrics. Configure the OTLP exporter endpoint and service name for Gallery to send OTLP to an OpenTelemetry Collector (e.g., [Otel Collector](https://opentelemetry.io/docs/collector/) or [Grafana Alloy](https://grafana.com/docs/alloy/latest/)):

```yaml
gallery-api:
  env:
    # This can be a kubernetes service address if the collector is running in the cluster
    OTEL_EXPORTER_OTLP_ENDPOINT: http://otel-collector:4317

    # Optional: force HTTP instead of the default gRPC protocol
    # OTEL_EXPORTER_OTLP_PROTOCOL: http/protobuf
    # Optional: override the service name reported to collectors
    # OTEL_SERVICE_NAME: gallery-api

    # These settings toggle ServiceDefaults configurations for Otel
    # The values listed here are the defaults
    # OpenTelemetry__AddAlwaysOnTracingSampler: false
    # OpenTelemetry__AddConsoleExporter: false
    # OpenTelemetry__AddPrometheusExporter: false
    # OpenTelemetry__IncludeDefaultActivitySources: true
    # OpenTelemetry__IncludeDefaultMeters: true
```

#### Default metrics from ServiceDefaults
- Instrumentations: ASP.NET Core, HttpClient, Entity Framework Core, .NET runtime, and process resource metrics.
- Built-in meters: `Microsoft.AspNetCore.Hosting`, `Microsoft.AspNetCore.Server.Kestrel`, `System.Net.Http`, `System.Net.NameResolution`, `Microsoft.EntityFrameworkCore`, plus runtime/process meters.
- Resource attribute `service_name` defaults to `gallery-api` (or your `OTEL_SERVICE_NAME` override).

## Gallery UI Configuration

Use `settingsYaml` to configure the Angular UI application. The table below highlights common settings.

| Setting | Description | Example |
|---------|-------------|---------|
| `ApiUrl` | Base URL for the Gallery API | `https://gallery.example.com` |
| `AppTitle` | Browser/application title | `Gallery` |
| `AppTopBarHexColor` | Hex color for the top bar background | `#2d69b4` |
| `AppTopBarHexTextColor` | Hex color for the top bar text | `#FFFFFF` |
| `AppTopBarText` | Banner text displayed in the top bar | `Gallery - Exercise Information Sharing` |
| `AppTopBarImage` | Path to the banner image | `/assets/img/monitor-dashboard-white.png` |
| `OIDCSettings.authority` | OIDC authority URL | `https://identity.example.com/` |
| `OIDCSettings.client_id` | OAuth client ID for the Gallery UI | `gallery-ui` |
| `OIDCSettings.redirect_uri` | Callback URL after login | `https://gallery.example.com/auth-callback` |
| `OIDCSettings.post_logout_redirect_uri` | URL users return to after logout | `https://gallery.example.com` |
| `OIDCSettings.response_type` | OAuth response type | `code` |
| `OIDCSettings.scope` | Space-delimited scopes requested during login | `openid profile gallery` |
| `OIDCSettings.automaticSilentRenew` | Enables background token renewal | `true` |
| `OIDCSettings.silent_redirect_uri` | URI for silent token renewal callbacks | `https://gallery.example.com/auth-callback-silent` |
| `UseLocalAuthStorage` | Persist auth state in browser local storage | `true` |


## References

- [Gallery Documentation](https://cmu-sei.github.io/crucible/gallery/)
- [Gallery API Repository](https://github.com/cmu-sei/Gallery.Api)
- [Gallery UI Repository](https://github.com/cmu-sei/Gallery.Ui)
