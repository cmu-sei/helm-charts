{{/*
Expand the name of the chart.
*/}}
{{- define "lrsql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "lrsql.fullname" -}}
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
{{- define "lrsql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "lrsql.labels" -}}
helm.sh/chart: {{ include "lrsql.chart" . }}
{{ include "lrsql.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "lrsql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "lrsql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "lrsql.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "lrsql.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Subpath prefix value to use for pvc mount points
*/}}
{{- define "lrsql.subpathPrefix" -}}
{{- $path := default (printf "%s-%s" (include "lrsql.fullname" .) "config") .Values.storage.overrideSubpathPrefix -}}
{{- ternary ($path | printf "%s/" ) "" .Values.storage.existingSubpathPrefix -}}
{{- end }}

{{/*
SQL LRS Command to execute based on value of .Values.dbMode */}}
{{- define "lrsql.containerCommand" -}}
{{- $dbmode := default "SQLite" .Values.dbMode -}}
{{- if eq "SQLite" $dbmode -}}
/lrsql/bin/run_sqlite.sh
{{- else if eq "Postgres" $dbmode -}}
/lrsql/bin/run_postgres.sh
{{- else if eq "SQLite-In-Memory" $dbmode -}}
/lrsql/bin/run_sqlite_ephemeral.sh
{{- else -}}
{{- fail "The value for .Values.dbMode must be one of Postgres, SQLite, SQLite-In-Memory." }}
{{- end -}}
{{- end }}
