{{/*
Expand the name of the chart.
*/}}
{{- define "moodle.name" -}}
{{- $global := .Values.global | default dict -}}
{{- default .Chart.Name $global.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "moodle.fullname" -}}
{{- $global := .Values.global | default dict -}}
{{- if $global.fullnameOverride }}
{{- $global.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name $global.nameOverride }}
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
{{- define "moodle.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "moodle.labels" -}}
helm.sh/chart: {{ include "moodle.chart" . }}
{{ include "moodle.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "moodle.selectorLabels" -}}
app.kubernetes.io/name: {{ include "moodle.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "moodle.serviceAccountName" -}}
{{- $serviceAccount := .Values.serviceAccount | default dict -}}
{{- if $serviceAccount.create }}
{{- default (include "moodle.fullname" .) $serviceAccount.name }}
{{- else }}
{{- default "default" $serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Service name
*/}}
{{- define "moodle.serviceName" -}}
{{- include "moodle.fullname" . }}
{{- end }}

{{/*
Admin secret name
*/}}
{{- define "moodle.admin.secretName" -}}
{{- printf "%s-admin" (include "moodle.fullname" .) }}
{{- end }}

{{/*
Database secret name
*/}}
{{- define "moodle.database.secretName" -}}
{{- printf "%s-database" (include "moodle.fullname" .) }}
{{- end }}

{{/*
OIDC client secret name
*/}}
{{- define "moodle.oidc.secretName" -}}
{{- printf "%s-oidc" (include "moodle.fullname" .) }}
{{- end }}

{{/*
(Placeholder — reserved for future OIDC helpers)
*/}}

{{/*
Return the proper Moodle image name with digest support
*/}}
{{- define "moodle.image" -}}
{{- $registry := .Values.image.registry | default "" -}}
{{- $repository := .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- $digest := .Values.image.digest | default "" -}}
{{- if $registry }}
{{- $repository = printf "%s/%s" $registry $repository -}}
{{- end }}
{{- if $digest }}
{{- printf "%s@%s" $repository $digest -}}
{{- else }}
{{- printf "%s:%s" $repository $tag -}}
{{- end }}
{{- end }}

{{/*
Return the proper image pull policy
*/}}
{{- define "moodle.imagePullPolicy" -}}
{{- .Values.image.pullPolicy | default "IfNotPresent" }}
{{- end }}

{{/*
Return resource preset configuration
*/}}
{{- define "moodle.resources.preset" -}}
{{- $preset := .type -}}
{{- if eq $preset "nano" }}
requests:
  cpu: 50m
  memory: 64Mi
limits:
  cpu: 100m
  memory: 128Mi
{{- else if eq $preset "micro" }}
requests:
  cpu: 100m
  memory: 128Mi
limits:
  cpu: 200m
  memory: 256Mi
{{- else if eq $preset "small" }}
requests:
  cpu: 250m
  memory: 256Mi
limits:
  cpu: 500m
  memory: 512Mi
{{- else if eq $preset "medium" }}
requests:
  cpu: 500m
  memory: 512Mi
limits:
  cpu: 1000m
  memory: 1Gi
{{- else if eq $preset "large" }}
requests:
  cpu: 1000m
  memory: 1Gi
limits:
  cpu: 2000m
  memory: 2Gi
{{- else if eq $preset "xlarge" }}
requests:
  cpu: 2000m
  memory: 2Gi
limits:
  cpu: 4000m
  memory: 4Gi
{{- else if eq $preset "2xlarge" }}
requests:
  cpu: 4000m
  memory: 4Gi
limits:
  cpu: 8000m
  memory: 8Gi
{{- end }}
{{- end }}

{{/*
Return pod affinity preset based on type
*/}}
{{- define "moodle.affinities.pods" -}}
{{- $type := .type -}}
{{- $customLabels := .customLabels -}}
{{- $context := .context -}}
{{- if eq $type "soft" }}
preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchLabels: {{- include "moodle.selectorLabels" $context | nindent 10 }}
      topologyKey: kubernetes.io/hostname
{{- else if eq $type "hard" }}
requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector:
      matchLabels: {{- include "moodle.selectorLabels" $context | nindent 8 }}
    topologyKey: kubernetes.io/hostname
{{- end }}
{{- end }}

{{/*
Return pod anti-affinity preset based on type
*/}}
{{- define "moodle.affinities.antiPods" -}}
{{- $type := .type -}}
{{- $customLabels := .customLabels -}}
{{- $context := .context -}}
{{- if eq $type "soft" }}
preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchLabels: {{- include "moodle.selectorLabels" $context | nindent 10 }}
      topologyKey: kubernetes.io/hostname
{{- else if eq $type "hard" }}
requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector:
      matchLabels: {{- include "moodle.selectorLabels" $context | nindent 8 }}
    topologyKey: kubernetes.io/hostname
{{- end }}
{{- end }}

{{/*
Return node affinity preset based on type
*/}}
{{- define "moodle.affinities.nodes" -}}
{{- $type := .type -}}
{{- $key := .key -}}
{{- $values := .values -}}
{{- if and $type $key (gt (len $values) 0) }}
{{- if eq $type "soft" }}
preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    preference:
      matchExpressions:
        - key: {{ $key }}
          operator: In
          values:
            {{- range $values }}
            - {{ . | quote }}
            {{- end }}
{{- else if eq $type "hard" }}
requiredDuringSchedulingIgnoredDuringExecution:
  nodeSelectorTerms:
    - matchExpressions:
        - key: {{ $key }}
          operator: In
          values:
            {{- range $values }}
            - {{ . | quote }}
            {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Validate required values for Moodle deployment
*/}}
{{- define "moodle.validateValues" -}}
{{- $moodle := .Values.moodle | default dict -}}
{{- $admin := $moodle.admin | default dict -}}
{{- $site := $moodle.site | default dict -}}
{{- $database := $moodle.database | default dict -}}
{{- $secrets := .Values.secrets | default dict -}}
{{- $persistence := .Values.persistence | default dict -}}
{{- $ingress := .Values.ingress | default dict -}}

{{/* Validate SITE_URL is set */}}
{{- if not $site.url }}
{{- fail "ERROR: moodle.site.url is required. Please set it to your actual Moodle URL (e.g., https://moodle.example.com)" }}
{{- end }}

{{/* Validate Database Host */}}
{{- if not $database.host }}
{{- fail "ERROR: moodle.database.host is required. Please set it to your database service name or hostname." }}
{{- end }}

{{/* Validate Database Name */}}
{{- if not $database.name }}
{{- fail "ERROR: moodle.database.name is required. Please set it to your database name." }}
{{- end }}

{{/* Validate Database User */}}
{{- if not $database.user }}
{{- fail "ERROR: moodle.database.user is required. Please set it to your database username." }}
{{- end }}

{{/* Validate Database Password is configured */}}
{{- if and (not $database.existingSecret) (not $database.password) }}
{{- fail "ERROR: Database password must be configured.\n  Either:\n  1. Set moodle.database.password (insecure, for dev/testing)\n  2. Set moodle.database.existingSecret (recommended for production)" }}
{{- end }}

{{/* Admin Username - use default if not provided */}}
{{/* Username validation happens in deployment where default is applied */}}

{{/* Admin Email - use default if not provided */}}
{{/* Email validation happens in deployment where default is applied */}}

{{/* Validate PVC configuration consistency */}}
{{- range $name, $config := $persistence }}
{{- if and $config.enabled (eq $config.type "persistentVolumeClaim") }}
{{- if and $config.existingClaim (or $config.size $config.storageClass $config.accessMode) }}
{{- fail (printf "ERROR: persistence.%s has both 'existingClaim' and PVC creation settings (size/storageClass/accessMode).\n  When using existingClaim, remove: size, storageClass, and accessMode settings.\n  These settings are ignored when existingClaim is specified." $name) }}
{{- end }}
{{- if and (not $config.existingClaim) (not $config.size) }}
{{- fail (printf "ERROR: persistence.%s requires 'size' when creating a new PVC.\n  Either:\n  1. Set persistence.%s.size (e.g., '20Gi')\n  2. Use persistence.%s.existingClaim to reference an existing PVC" $name $name $name) }}
{{- end }}
{{- end }}
{{- end }}

{{/* Validate SMTP configuration consistency */}}
{{- $smtp := $moodle.smtp | default dict }}
{{- $smtpConfigured := false }}
{{- $smtpVars := list }}
{{- if $smtp.host }}{{ $smtpConfigured = true }}{{ $smtpVars = append $smtpVars "host" }}{{- end }}
{{- if $smtp.port }}{{ $smtpConfigured = true }}{{ $smtpVars = append $smtpVars "port" }}{{- end }}
{{- if $smtp.user }}{{ $smtpConfigured = true }}{{ $smtpVars = append $smtpVars "user" }}{{- end }}
{{- if or $smtp.password $smtp.existingSecret }}{{ $smtpConfigured = true }}{{ $smtpVars = append $smtpVars "password" }}{{- end }}
{{- if and $smtpConfigured (ne (len $smtpVars) 4) }}
{{- $allSMTP := list "host" "port" "user" "password" }}
{{- $missingVars := list }}
{{- range $allSMTP }}
{{- if not (has . $smtpVars) }}
{{- $missingVars = append $missingVars . }}
{{- end }}
{{- end }}
{{- fail (printf "ERROR: Incomplete SMTP configuration. When configuring SMTP, all variables must be set.\n  Configured: %s\n  Missing: %s\n  Either:\n  1. Set all SMTP variables (moodle.smtp.host, port, user, password or existingSecret)\n  2. Remove all SMTP variables to disable email functionality" (join ", " $smtpVars) (join ", " $missingVars)) }}
{{- end }}

{{/* Validate ingress configuration */}}
{{- if $ingress.enabled }}
{{- if not $ingress.hostname }}
{{- fail "ERROR: ingress.hostname is required when ingress.enabled=true.\n  Set ingress.hostname to your domain (e.g., 'moodle.example.com')" }}
{{- end }}
{{- end }}

{{/* Validate persistence types */}}
{{- range $name, $config := $persistence }}
{{- if $config.enabled }}
{{- $type := $config.type | default "persistentVolumeClaim" }}
{{- $validTypes := list "persistentVolumeClaim" "emptyDir" "configMap" "secret" }}
{{- if not (has $type $validTypes) }}
{{- fail (printf "ERROR: persistence.%s.type '%s' is invalid.\n  Valid types: %s" $name $type (join ", " $validTypes)) }}
{{- end }}
{{- if eq $type "configMap" }}
{{- if not $config.name }}
{{- fail (printf "ERROR: persistence.%s.name is required when type is 'configMap'" $name) }}
{{- end }}
{{- end }}
{{- if eq $type "secret" }}
{{- if not $config.name }}
{{- fail (printf "ERROR: persistence.%s.name is required when type is 'secret'" $name) }}
{{- end }}
{{- end }}
{{- $knownKeys := list "moodledata" "moodle" }}
{{- if and (not $config.mountPath) (not (has $name $knownKeys)) }}
{{- fail (printf "ERROR: persistence.%s.mountPath is required for custom volume names.\n  Standard volumes (moodledata, moodle) have default mount paths." $name) }}
{{- end }}
{{- end }}
{{- end }}

{{/* Validate autoscaling configuration */}}
{{- $autoscaling := .Values.autoscaling | default dict }}
{{- if $autoscaling.enabled }}
{{- if not (or $autoscaling.targetCPU $autoscaling.targetMemory) }}
{{- fail "ERROR: autoscaling.enabled=true requires at least one of: targetCPU or targetMemory" }}
{{- end }}
{{- if and $autoscaling.minReplicas $autoscaling.maxReplicas }}
{{- if gt ($autoscaling.minReplicas | int) ($autoscaling.maxReplicas | int) }}
{{- fail (printf "ERROR: autoscaling.minReplicas (%d) cannot be greater than autoscaling.maxReplicas (%d)" ($autoscaling.minReplicas | int) ($autoscaling.maxReplicas | int)) }}
{{- end }}
{{- end }}
{{- end }}

{{/* Validate PDB configuration */}}
{{- $pdb := .Values.pdb | default dict }}
{{- if $pdb.create }}
{{- if and $pdb.minAvailable $pdb.maxUnavailable }}
{{- fail "ERROR: pdb.minAvailable and pdb.maxUnavailable are mutually exclusive. Specify only one." }}
{{- end }}
{{- if not (or $pdb.minAvailable $pdb.maxUnavailable) }}
{{- fail "ERROR: pdb.create=true requires either pdb.minAvailable or pdb.maxUnavailable to be set" }}
{{- end }}
{{- end }}


{{/* Validate readOnlyDirroot configuration */}}
{{- $readOnlyDirroot := .Values.readOnlyDirroot | default dict }}
{{- if $readOnlyDirroot.enabled }}

{{/* Ensure volume is configured */}}
{{- $volume := $readOnlyDirroot.volume | default dict }}
{{- if not $volume }}
{{- fail "ERROR: readOnlyDirroot.volume is required when readOnlyDirroot.enabled=true.\n  Specify a Kubernetes volume configuration.\n  See values.yaml readOnlyDirroot section for examples." }}
{{- end }}

{{/* Validate ephemeral volume structure if used */}}
{{- if $volume.ephemeral }}
{{- if not $volume.ephemeral.volumeClaimTemplate }}
{{- fail "ERROR: readOnlyDirroot.volume.ephemeral.volumeClaimTemplate is required when using ephemeral volumes.\n  Example:\n    volume:\n      ephemeral:\n        volumeClaimTemplate:\n          spec:\n            accessModes: [\"ReadWriteOnce\"]\n            storageClassName: \"gp3\"\n            resources:\n              requests:\n                storage: \"5Gi\"" }}
{{- end }}
{{- if not $volume.ephemeral.volumeClaimTemplate.spec }}
{{- fail "ERROR: readOnlyDirroot.volume.ephemeral.volumeClaimTemplate.spec is required.\n  See: https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/#generic-ephemeral-volumes" }}
{{- end }}
{{- $spec := $volume.ephemeral.volumeClaimTemplate.spec }}
{{- if not $spec.accessModes }}
{{- fail "ERROR: readOnlyDirroot.volume.ephemeral.volumeClaimTemplate.spec.accessModes is required.\n  Example: accessModes: [\"ReadWriteOnce\"]" }}
{{- end }}
{{- if not $spec.resources }}
{{- fail "ERROR: readOnlyDirroot.volume.ephemeral.volumeClaimTemplate.spec.resources is required.\n  Example:\n    resources:\n      requests:\n        storage: \"5Gi\"" }}
{{- end }}
{{- if not $spec.resources.requests }}
{{- fail "ERROR: readOnlyDirroot.volume.ephemeral.volumeClaimTemplate.spec.resources.requests is required.\n  Example:\n    requests:\n      storage: \"5Gi\"" }}
{{- end }}
{{- if not $spec.resources.requests.storage }}
{{- fail "ERROR: readOnlyDirroot.volume.ephemeral.volumeClaimTemplate.spec.resources.requests.storage is required.\n  Example: storage: \"5Gi\"" }}
{{- end }}
{{- end }}

{{- end }}

{{/* Validate that PRE/POST_CONFIGURE_COMMANDS are not in extraEnvVars */}}
{{- range .Values.extraEnvVars }}
  {{- if eq .name "PRE_CONFIGURE_COMMANDS" }}
    {{- fail "ERROR: Do not set PRE_CONFIGURE_COMMANDS in extraEnvVars.\n  This variable is managed by the chart.\n  To add your own pre-configure commands, use: moodle.preConfigureCommands" }}
  {{- end }}
  {{- if eq .name "POST_CONFIGURE_COMMANDS" }}
    {{- fail "ERROR: Do not set POST_CONFIGURE_COMMANDS in extraEnvVars.\n  This variable is managed by the chart.\n  To add your own post-configure commands, use: moodle.postConfigureCommands" }}
  {{- end }}
{{- end }}

{{/* Validate OIDC configuration */}}
{{- $oidc := $moodle.oidc | default dict }}
{{- if $oidc.enabled }}
  {{- if not ($oidc.discoveryUrl | default "") }}
    {{- fail "ERROR: moodle.oidc.discoveryUrl is required when moodle.oidc.enabled=true.\n  Set this to your provider's .well-known/openid-configuration URL.\n  e.g., 'https://keycloak.example.com/realms/my-realm/.well-known/openid-configuration'" }}
  {{- end }}
  {{- if not $oidc.clientId }}
    {{- fail "ERROR: moodle.oidc.clientId is required when moodle.oidc.enabled=true" }}
  {{- end }}
  {{- if and (not $oidc.existingSecret) (not $oidc.clientSecret) }}
    {{- fail "ERROR: OIDC client secret must be configured.\n  Either:\n  1. Set moodle.oidc.clientSecret (for dev/testing)\n  2. Set moodle.oidc.existingSecret (recommended for production)" }}
  {{- end }}
  {{- if not $oidc.userFieldMappings }}
    {{- fail "ERROR: moodle.oidc.userFieldMappings is required when moodle.oidc.enabled=true.\n  At minimum, set: userFieldMappings: [\"sub:idnumber\"]" }}
  {{- end }}
{{- end }}

{{- end }}
