{{/*
Expand the name of the chart.
*/}}
{{- define "caster-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "caster-api.fullname" -}}
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
{{- define "caster-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "caster-api.labels" -}}
helm.sh/chart: {{ include "caster-api.chart" . }}
{{ include "caster-api.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "caster-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "caster-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "caster-api.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "caster-api.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
  Shared environment configuration for containers
*/}}
{{- define "caster-api.env" }}
envFrom:
  - secretRef:
      name: {{ include "caster-api.fullname" . }}
{{- if .Values.existingSecret }}
  - secretRef:
      name: {{ (tpl .Values.existingSecret .) }}
{{- end }}
{{- end }}

{{/*
Collect and merge ConfigMaps - user env vars override chart defaults by Name
*/}}
{{- define "caster-api.k8sJobConfigMaps" -}}
{{- $configMapsByName := dict -}}

{{- /* Add chart defaults */ -}}
{{- if .Values.certificateMap }}
  {{- $_ := set $configMapsByName .Values.certificateMap "/usr/local/share/ca-certificates" }}
{{- end }}
{{- if .Values.gitcredentials }}
  {{- $name := printf "%s-gitcredentials" (include "caster-api.fullname" .) }}
  {{- $_ := set $configMapsByName $name "/app/.git-credentials" }}
{{- end }}
{{- if .Values.terraformrc.enabled }}
  {{- $name := printf "%s-terraformrc" (include "caster-api.fullname" .) }}
  {{- $_ := set $configMapsByName $name "/app/.terraformrc" }}
{{- end }}

{{- /* Add/override with user values */ -}}
{{- range $key, $val := .Values.env }}
  {{- if hasPrefix "Terraform__KubernetesJobs__ConfigMaps__" $key }}
    {{- if hasSuffix "__Name" $key }}
      {{- $mountKey := regexReplaceAll "__Name$" $key "__MountPath" }}
      {{- $mountPath := index $.Values.env $mountKey | default "" }}
      {{- $_ := set $configMapsByName $val $mountPath }}
    {{- end }}
  {{- end }}
{{- end }}

{{- /* Output with sequential indexing */ -}}
{{- $index := 0 }}
{{- range $name, $mountPath := $configMapsByName }}
{{ printf "Terraform__KubernetesJobs__ConfigMaps__%d__Name" $index }}: {{ $name | quote }}
{{ printf "Terraform__KubernetesJobs__ConfigMaps__%d__MountPath" $index }}: {{ $mountPath | quote }}
  {{- $index = add1 $index }}
{{- end }}
{{- end }}
