#!/bin/bash
# Adds the Helm repositories that the charts' remote dependencies come from, so
# `helm dependency build` can fetch them. Shared by the CI jobs that render charts.

set -euo pipefail

helm repo add sei https://cmu-sei.github.io/helm-charts
helm repo add kvaps https://kvaps.github.io/charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add runix https://helm.runix.net
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add cloudnative-pg https://cloudnative-pg.github.io/charts
helm repo add bitnami https://charts.bitnami.com/bitnami
