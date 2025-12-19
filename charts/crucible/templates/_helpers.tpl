{{/*
Expand the name of the chart.
*/}}
{{- define "crucible.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "crucible.fullname" -}}
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
{{- define "crucible.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "crucible.labels" -}}
helm.sh/chart: {{ include "crucible.chart" . }}
{{ include "crucible.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "crucible.selectorLabels" -}}
app.kubernetes.io/name: {{ include "crucible.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Return the expected Kubernetes service name for the postgresql from crucible-infra.
This allows applications to reference the external database.
*/}}
{{- define "crucible.postgresql.serviceName" -}}
{{- $postgresConfig := .Values.global.postgresql | default dict -}}
{{- if $postgresConfig.serviceName }}
{{- tpl $postgresConfig.serviceName . }}
{{- else if .Values.postgresql.serviceName }}
{{- tpl .Values.postgresql.serviceName . }}
{{- else }}
{{- printf "%s-postgresql" .Release.Name }}
{{- end }}
{{- end }}

{{/*
Return the name of the secret that stores the postgresql password from crucible-infra.
*/}}
{{- define "crucible.postgresql.secretName" -}}
{{- $postgresConfig := .Values.global.postgresql | default dict -}}
{{- if $postgresConfig.secretName }}
{{- tpl $postgresConfig.secretName . }}
{{- else if .Values.postgresql.secretName }}
{{- tpl .Values.postgresql.secretName . }}
{{- else }}
{{- printf "%s-postgresql" .Release.Name }}
{{- end }}
{{- end }}

{{/*
Return the name of the TLS certificate secret.
*/}}
{{- define "crucible.tlsSecretName" -}}
{{- $tls := .Values.global.tls | default dict -}}
{{- if $tls.secretName }}
{{- $tls.secretName -}}
{{- else }}
{{- "crucible-cert" -}}
{{- end }}
{{- end }}
