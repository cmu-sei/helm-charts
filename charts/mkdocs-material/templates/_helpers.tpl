{{/*
Expand the name of the chart.
*/}}
{{- define "mkdocs-material.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "mkdocs-material.fullname" -}}
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
{{- define "mkdocs-material.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mkdocs-material.labels" -}}
helm.sh/chart: {{ include "mkdocs-material.chart" . }}
{{ include "mkdocs-material.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mkdocs-material.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mkdocs-material.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "mkdocs-material.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mkdocs-material.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Subpath prefix value to use for pvc mount points
*/}}
{{- define "mkdocs-material.subpathPrefix" -}}
{{- $path := default (include "mkdocs-material.fullname" .) .Values.storage.overrideSubpathPrefix -}}
{{- ternary ($path | printf "%s/" ) "" .Values.storage.existingSubpathPrefix -}}
{{- end }}