# Material for MkDocs Helm Chart

## Introduction

[Material for MkDocs](https://squidfunk.github.io/mkdocs-material/) is a static site generator for technical documentation. This chart is inspired by [staticweb](https://github.com/cmu-sei/helm-charts/tree/master/charts/staticweb) and allows for deployment via static files or a Git repository. Both modes use [Nginx](https://hub.docker.com/_/nginx) to serve the site.

## Storage Options

Because this chart uses a [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) in Git mode, you must specify either `storage.existing` or `storage.size` to store the MkDocs build output outside of the Pod. This also means that Git mode requires Kubernetes v1.21+.

If both `storage.existing` and `storage.size` are both empty, an [emptyDir](https://kubernetes.io/docs/concepts/storage/volumes/#emptydir) volume is used to store the MkDocs site.

## Custom Parameters

| Name | Description | Default |
| ---- | ----------- | ----- |
| `storage.existing` | The name of an existing PVC to store the site | `""` |
| `storage.size` | The size of a new PVC to store the site | `""` |
| `storage.mode` | The [Access Mode](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes) of the new PVC (requires `storage.size`) | `ReadWriteOnce` |
| `storage.class` | Sets the [StorageClass](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#class) of the new PVC (requires `storage.size`) | `default` |
| `giturl` | URL of an MkDocs Git repository | `""` |
| `branch` | Git branch that contains repository to publish | `""` |
| `pollInterval` | Delay between git pull (minutes) | `5` |
| `cacert` | Custom CA certificate to trust for Git server | `nil` |
| `mkdocs` | YAML configuration for MkDocs (static mode) | `{}` |
| `files` | Dictionary of text files (usually Markdown) to include as a configmap (static mode) | `{}` |
| `binaryFiles` | Dictionary of binary files to include as a configmap (static mode) | `{}` |
