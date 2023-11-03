{{/*
Expand the name of the chart.
*/}}
{{- define "alloy-ui.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "alloy-ui.fullname" -}}
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
{{- define "alloy-ui.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "alloy-ui.labels" -}}
helm.sh/chart: {{ include "alloy-ui.chart" . }}
{{ include "alloy-ui.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "alloy-ui.selectorLabels" -}}
app.kubernetes.io/name: {{ include "alloy-ui.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "alloy-ui.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "alloy-ui.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resolve extraVolumeMounts value
*/}}
{{- define "alloy-ui.extraVolumeMounts" -}}
{{ tpl (default "" .Values.extraVolumeMounts) . }}
{{- end -}}

{{/*
Resolve extraVolumes value
*/}}
{{- define "alloy-ui.extraVolumes" -}}
{{ tpl (default "" .Values.extraVolumes) . }}
{{- end -}}
