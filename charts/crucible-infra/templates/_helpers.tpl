{{/*
Expand the name of the chart.
*/}}
{{- define "crucible-infra.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "crucible-infra.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "crucible-infra.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "crucible-infra.labels" -}}
helm.sh/chart: {{ include "crucible-infra.chart" . }}
{{ include "crucible-infra.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "crucible-infra.selectorLabels" -}}
app.kubernetes.io/name: {{ include "crucible-infra.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Return the expected Kubernetes service name for the postgresql dependency.
This is used by the crucible chart to reference the database.
*/}}
{{- define "crucible-infra.postgresql.serviceName" -}}
{{- if .Values.postgresql.fullnameOverride }}
{{- .Values.postgresql.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "postgresql" .Values.postgresql.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Return the name of the secret that stores the postgresql password.
*/}}
{{- define "crucible-infra.postgresql.secretName" -}}
{{- printf "%s-postgresql" (include "crucible-infra.fullname" . ) -}}
{{- end }}

{{/*
Return the name of the TLS secret for ingress resources.
*/}}
{{- define "crucible-infra.tls.secretName" -}}
{{- .Values.tls.secretName | default "crucible-cert" -}}
{{- end }}

{{/*
Return the name of the CA certificates ConfigMap.
*/}}
{{- define "crucible-infra.caCerts.configMapName" -}}
{{- .Values.caCerts.configMapName | default "crucible-ca-cert" -}}
{{- end }}
