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

{{/*
  Shared yaml for the git containers
*/}}
{{- define "mkdocs-material.git-container" }}
{{- if .Values.giturl }}
- name: git-pull
  image: "bitnami/git"
  command: ["/entry.d/git-pull.sh"]
  env:
    - name: DOCS_GIT_URL
      value: {{ (tpl .Values.giturl .) }}
    - name: DOCS_GIT_BRANCH
      value: {{ .Values.gitbranch }}
  {{- if .Values.gitCredentialsSecret }}
    - name: DOCS_GIT_CRED_FILE
      value: {{ default ".git-credentials" .Values.gitCredentialsSecretKey }}
  {{- end }}
  {{- if .Values.gitPath }}
    - name: DOCS_GIT_PATH
      value: {{ .Values.gitPath | trimPrefix "/" }}
  {{- end }}
  {{- if .Values.mkdocs.site_url }}
    - name: DOCS_SITE_URL
      value: {{ .Values.mkdocs.site_url }}
  {{- end }}
  volumeMounts:
    - mountPath: /entry.d
      name: {{ include "mkdocs-material.fullname" . }}-entry
    - mountPath: /docs
      name: {{ include "mkdocs-material.fullname" . }}-vol
      subPath: {{ include "mkdocs-material.subpathPrefix" . }}docs
    - mountPath: /git
      name: {{ include "mkdocs-material.fullname" . }}-vol
      subPath: {{ include "mkdocs-material.subpathPrefix" . }}git
  {{- if .Values.gitCredentialsSecret }}
    - mountPath: /git-credentials
      name: {{ include "mkdocs-material.fullname" . }}-git-creds
  {{- end }}
  {{- if or .Values.certificateMap .Values.cacert }}
    - mountPath: /usr/local/share/ca-certificates
      name: certificates
  {{- end }}
{{- end }}
{{- end }}

{{/*
  Shared yaml for the mkdocs containers
*/}}
{{- define "mkdocs-material.mkdocs-container" }}
- name: mkdocs-build
  image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  {{- if .Values.giturl }}
  command: ["/entry.d/mkdocs-build.sh"]
  {{- else }}
  args: ["build"]
  {{- end }}
  env:
    - name: MKDOCS_ADD_MACROS
      value: {{ default "false" .Values.macroPlugin.enabled | toString | quote }}
    - name: MKDOCS_MACROS_VERSION
      value: {{ default "1.3.9" .Values.macroPlugin.version | toString | quote }}
  {{- if .Values.gitPath }}
    - name: DOCS_GIT_PATH
      value: {{ .Values.gitPath | trimPrefix "/" }}
  {{- end }}
  volumeMounts:
  {{- if and .Values.macroPlugin.enabled .Values.macroPlugin.extraYamlConfig }}
    - mountPath: {{ default "/mkdocs-vars" .Values.macroPlugin.extraYamlConfigMount }}
      name: {{ include "mkdocs-material.fullname" . }}-macro-vars
  {{- end }}
  {{- if .Values.giturl }}
    - mountPath: /entry.d
      name: {{ include "mkdocs-material.fullname" . }}-entry
    - mountPath: /docs
      name: {{ include "mkdocs-material.fullname" . }}-vol
      subPath: {{ include "mkdocs-material.subpathPrefix" . }}docs
    - mountPath: /git
      name: {{ include "mkdocs-material.fullname" . }}-vol
      subPath: {{ include "mkdocs-material.subpathPrefix" . }}git
    {{- else }}
    - mountPath: /docs/mkdocs.yml
     name: {{ include "mkdocs-material.fullname" . }}
     subPath: mkdocs.yml
    - mountPath: /docs/docs
      name: {{ include "mkdocs-material.fullname" . }}-files
    - mountPath: /docs/site
      name: {{ include "mkdocs-material.fullname" . }}-vol
      subPath: {{ include "mkdocs-material.subpathPrefix" . }}docs/site
    {{- end }}
{{- end }}
