{{/*
Expand the name of the chart.
*/}}
{{- define "crucible-operators.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "crucible-operators.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "crucible-operators.labels" -}}
helm.sh/chart: {{ include "crucible-operators.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
