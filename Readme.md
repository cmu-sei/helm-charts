# Helm at cmu-sei

Helm charts for deploying applications to Kubernetes.

All charts are intended for use with Helm 3.

Not all charts reference images in public repositories.  Thanks for your patience as we work to make them available.

Example usage:

```bash
# add this helm repo:
$ helm repo add foundry https://helm.cyberforce.site/charts

# grab and edit values as desired
$ helm show values foundry/identity > identity.values.yaml

# deploy
$ helm install idsrv foundry/identity -f identity.values.yaml
```
