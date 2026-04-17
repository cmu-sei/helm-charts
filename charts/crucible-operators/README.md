# Crucible Operators

Helm chart that installs Kubernetes operator prerequisites for the Crucible platform.
While the Keycloak and PostgreSQL prerequisites can be installed different ways, or
provided by external services, this chart supplies a way to `helm install` these
dependencies if you choose.

## Operators

This chart deploys the following operators

| Operator | Version | Purpose |
|----------|---------|---------|
| [Keycloak Operator](https://www.keycloak.org/operator/installation) | 26.5.6 | Manages Keycloak instances via `Keycloak` and `KeycloakRealmImport` CRs |
| [CloudNative-PG](https://cloudnative-pg.io/) | 0.25.0 (chart) | Manages PostgreSQL clusters via `Cluster` CRs |

To learn more about Kubernetes Operators, see the Kubernetes documentation on the [Operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/).

## Why a Helm Chart?

CloudNative-PG [recommends installation via their official Helm chart](https://cloudnative-pg.io/documentation/current/installation_upgrade/#installation-on-kubernetes),
which handles operator deployment, RBAC, and webhook configuration. Rather than mixing
tooling (Helm for CNPG, Kustomize for Keycloak, a way to glue them together), this
chart wraps both operators into a single `helm install` so the entire stack uses
one consistent deployment tool.

The Keycloak Operator does not publish an official Helm chart -- its recommended
installation path is `kubectl apply` of raw manifests. This chart vendors those manifests
(CRDs in `crds/`, deployment resources in `templates/`) so they can be installed alongside
CNPG in a single Helm release without requiring Kustomize.

## Why Operators are Separate

Operators are **cluster-scoped infrastructure** -- they install CRDs and watch all
namespaces. Separating them from application charts provides:

- **Privilege separation**: Operator install requires cluster-admin; app charts only need namespace access
- **Independent lifecycle**: Upgrade operators without redeploying applications
- **Shared infrastructure**: Multiple namespaces/teams can share one operator installation
- **CRD safety**: Helm cannot upgrade CRDs -- they must be managed separately

## Install

```bash
helm install crucible-operators ./crucible-operators --wait
```

## Upgrade

### Keycloak Operator

The Keycloak Operator publishes raw manifests for each release on GitHub. To upgrade to
a new version (e.g., `26.5.6`):

1. **Download the updated CRDs** from the
   [keycloak/keycloak-k8s-resources](https://github.com/keycloak/keycloak-k8s-resources)
   repository. Each release tag contains the CRD files under `kubernetes/`:

   ```bash
   VERSION=26.5.6
   BASE_URL="https://raw.githubusercontent.com/keycloak/keycloak-k8s-resources/${VERSION}/kubernetes"

   curl -L "${BASE_URL}/keycloaks.k8s.keycloak.org-v1.yml"           -o crds/keycloaks.k8s.keycloak.org-v1.yml
   curl -L "${BASE_URL}/keycloakrealmimports.k8s.keycloak.org-v1.yml" -o crds/keycloakrealmimports.k8s.keycloak.org-v1.yml
   ```

   > **Tip:** You can browse available versions at
   > <https://github.com/keycloak/keycloak-k8s-resources/tags>.

2. **Update the operator deployment template** in `templates/keycloak-operator.yaml`.
   The deployment manifest is available from the same repository:

   ```bash
   curl -L "${BASE_URL}/kubernetes.yml" -o templates/keycloak-operator.yaml
   ```

   Review the downloaded file and adjust the namespace or any Helm template references
   as needed to match the existing template.

3. **Update the version** in the operator table in this README and increment the chart version number in `Chart.yaml`.

4. **Apply CRDs first** (Helm does not upgrade CRDs on `helm upgrade`):

   ```bash
   kubectl apply -f crds/
   helm upgrade crucible-operators ./crucible-operators
   ```

### CNPG Operator

To upgrade CloudNative-PG, update the subchart version in `Chart.yaml` and run:

```bash
helm dependency update
helm upgrade crucible-operators ./crucible-operators
```

## Uninstall

**Warning**: Remove all Custom Resources (Keycloak, KeycloakRealmImport, CNPG Cluster) **before**
removing operators. Deleting CRDs removes all CRs cluster-wide.

```bash
helm uninstall crucible-operators
```
