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
{{ include "moodle.tplvalues.render" (dict "value" . "context" $) }}
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
SMTP secret name
*/}}
{{- define "moodle.smtp.secretName" -}}
{{- $moodle := .Values.moodle | default dict -}}
{{- $admin := $moodle.admin | default dict -}}
{{- if $admin.existingSecret }}
{{- printf "%s-smtp" (include "moodle.fullname" .) }}
{{- else }}
{{- include "moodle.admin.secretName" . }}
{{- end }}
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
Secret holding moodle.config.
*/}}
{{- define "moodle.settings.secretName" -}}
{{- printf "%s-settings" (include "moodle.fullname" .) }}
{{- end }}

{{/*
ConfigMap holding the chart's scripts and the manifests they read.
*/}}
{{- define "moodle.scripts.configMapName" -}}
{{- printf "%s-scripts" (include "moodle.fullname" .) }}
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
Return the web root for the image tag, which moved under public/ in Moodle 5.1
*/}}
{{- define "moodle.webRoot" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- $version := $tag | trimPrefix "v" | splitList "-" | first -}}
{{- if and (regexMatch "^[0-9]+\\.[0-9]+\\.[0-9]+$" $version) (semverCompare "<5.1.0" $version) -}}
/var/www/html
{{- else -}}
/var/www/html/public
{{- end }}
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
{{- $proxy := $moodle.proxy | default dict -}}
{{- $database := $moodle.database | default dict -}}
{{- $secrets := .Values.secrets | default dict -}}
{{- $persistence := .Values.persistence | default dict -}}
{{- $ingress := .Values.ingress | default dict -}}

{{/* Validate Persistence Shape */}}
{{- range $name, $config := $persistence }}
{{- if not (kindIs "map" $config) }}
{{- fail (printf "ERROR: persistence.%s is not a volume. persistence is a map of named volumes and each one carries its own enabled flag, so there is no top level persistence.%s to set.\n  Either:\n  1. Set persistence.moodledata.enabled=false to run with no dataroot volume at all\n  2. Set persistence.moodledata.type=emptyDir for a volume that does not outlive the pod" $name $name) }}
{{- end }}
{{- end }}

{{/* Validate Web Plugin Installation */}}
{{- if $moodle.allowWebPluginInstall }}
{{- $rod := .Values.readOnlyDirroot | default dict -}}
{{- $auto := .Values.autoscaling | default dict -}}
{{- if $rod.enabled }}
{{- fail "ERROR: moodle.allowWebPluginInstall=true with readOnlyDirroot.enabled=true. The code tree is mounted readOnly, so Moodle cannot write a plugin into it and the installer fails partway, after it has already written the database rows.\n  Either:\n  1. Declare the plugin in moodle.plugins, which is how a read-only tree takes new code\n  2. Set readOnlyDirroot.enabled=false and run one pod" }}
{{- end }}
{{- if or (gt (.Values.replicaCount | default 1 | int) 1) $auto.enabled }}
{{- fail "ERROR: moodle.allowWebPluginInstall=true with more than one pod. Each pod holds its own code tree, so an install through the web reaches the one pod that served the request. The database then reports a plugin the other pods cannot find, and they answer with a missing-plugin error while that one works.\n  Either:\n  1. Declare the plugin in moodle.plugins, which every pod installs on boot\n  2. Set replicaCount=1 and disable autoscaling" }}
{{- end }}
{{- end }}

{{/* Validate Preset Source */}}
{{- $preset := $moodle.preset | default dict -}}
{{- if not (kindIs "map" $preset) }}
{{- fail (printf "ERROR: moodle.preset is a map, not a %s. Name the source of the preset.\n  Either:\n  1. Set moodle.preset.name to a preset already on the site (starter, full)\n  2. Set moodle.preset.xml to the preset XML itself\n  3. Set moodle.preset.existingConfigMap to a ConfigMap holding it" (kindOf $preset)) }}
{{- end }}
{{- $presetKnown := list "name" "xml" "existingConfigMap" "key" -}}
{{- range $k, $v := $preset }}
{{- if not (has $k $presetKnown) }}
{{- fail (printf "ERROR: moodle.preset.%s is not a preset key, so it would be ignored and no preset applied.\n  Either:\n  1. Use moodle.preset.name, moodle.preset.xml or moodle.preset.existingConfigMap to name the source\n  2. Use moodle.preset.key to name the key inside that ConfigMap" $k) }}
{{- end }}
{{- end }}
{{- $presetSources := list -}}
{{- range $k := list "name" "xml" "existingConfigMap" }}
{{- if get $preset $k }}
{{- $presetSources = append $presetSources $k }}
{{- end }}
{{- end }}
{{- if and $preset (eq (len $presetSources) 0) }}
{{- fail "ERROR: moodle.preset is set but names no preset, so none would be applied. A .Files.Get reading a path outside the chart returns empty, which lands here.\n  Either:\n  1. Set moodle.preset.name to a preset already on the site (starter, full)\n  2. Set moodle.preset.xml to the preset XML, or pass it with --set-file moodle.preset.xml=<path>\n  3. Set moodle.preset.existingConfigMap to a ConfigMap holding it" }}
{{- end }}
{{- if gt (len $presetSources) 1 }}
{{- fail (printf "ERROR: moodle.preset takes one source, but %s are set. The chart cannot tell which one you meant.\n  Either:\n  1. Keep moodle.preset.name for a preset already on the site\n  2. Keep moodle.preset.xml to ship the XML in the release\n  3. Keep moodle.preset.existingConfigMap to read it from a ConfigMap" (join ", " $presetSources)) }}
{{- end }}
{{- if and $preset.key (not $preset.existingConfigMap) }}
{{- fail "ERROR: moodle.preset.key names a key inside moodle.preset.existingConfigMap, and none is set.\n  Either:\n  1. Set moodle.preset.existingConfigMap to the ConfigMap holding the preset\n  2. Remove moodle.preset.key" }}
{{- end }}

{{/* Validate SITE_URL is set */}}
{{- if not $site.url }}
{{- fail "ERROR: moodle.site.url is required. Please set it to your actual Moodle URL (e.g., https://moodle.example.com)" }}
{{- end }}

{{/* Validate SSL Proxy */}}
{{- if and (ternary $proxy.sslProxy true (hasKey $proxy "sslProxy")) (hasPrefix "http://" (tpl ($site.url | default "") .)) }}
{{- fail "ERROR: moodle.proxy.sslProxy=true requires an https moodle.site.url. Moodle answers every page with 'Must use https address in wwwroot when ssl proxy enabled!' while the pod stays Ready.\n  Either:\n  1. Set moodle.site.url to an https URL\n  2. Set moodle.proxy.sslProxy=false" }}
{{- end }}

{{/* Validate Reverse Proxy */}}
{{- if and $proxy.reverseProxy $ingress.enabled }}
{{- fail "ERROR: moodle.proxy.reverseProxy=true with ingress.enabled=true. The chart's ingress passes the original Host header through, so Moodle sees no proxy hop, answers reverseproxyabused on every page and leaves every pod Ready.\n  Either:\n  1. Set moodle.proxy.reverseProxy=false and keep this chart's ingress\n  2. Set ingress.enabled=false and send traffic to the service from the proxy you run yourself" }}
{{- end }}

{{/* Validate Site Url Port */}}
{{- if not $proxy.reverseProxy }}
{{- $siteHost := (urlParse (tpl (($moodle.site).url | default "") $)).host }}
{{- if regexMatch ":[0-9]+$" $siteHost }}
{{- fail (printf "ERROR: moodle.site.url names the port in %s and moodle.proxy.reverseProxy is false.\n  Moodle compares the port in wwwroot against the port the request arrived on (lib/setuplib.php, initialise_fullme), and requests reach this container on 8080 whatever port the client used. The ports never match, so every page answers 303 to itself and a browser gives up on the redirect loop. The pod stays Ready throughout, because a 303 satisfies the probe, and helm reports the release deployed.\n  Either:\n  1. Remove the port from moodle.site.url and publish the site on 80 or 443\n  2. Set moodle.proxy.reverseProxy=true with ingress.enabled=false, which is the one case Moodle skips the comparison" $siteHost) }}
{{- end }}
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

{{/* Validate Database Password Is Read */}}
{{- if and $database.existingSecret $database.password }}
{{- fail (printf "ERROR: moodle.database.password is set while moodle.database.existingSecret is %s, so the password is never read.\n  The chart passes DB_PASS from the secret, and moodle.database.password is silently ignored. The pod then answers 'We could not connect to the database you specified' with credentials the values never mention. moodle.database.existingSecret is not empty by default, so setting only the password reaches this.\n  Either:\n  1. Set moodle.database.existingSecret to \"\" to use moodle.database.password\n  2. Remove moodle.database.password and keep the secret" (quote $database.existingSecret)) }}
{{- end }}

{{/* Admin Username - use default if not provided */}}
{{/* Username validation happens in deployment where default is applied */}}

{{/* Admin Email - use default if not provided */}}
{{/* Email validation happens in deployment where default is applied */}}

{{/* Validate Localcache Is Node-Local */}}
{{- $lc := $persistence.localcache | default dict }}
{{- $lcMultiPod := or (gt (.Values.replicaCount | default 1 | int) 1) (.Values.autoscaling | default dict).enabled }}
{{- if and $lc.enabled $lcMultiPod (or (eq ($lc.type | default "emptyDir") "persistentVolumeClaim") (eq ($lc.accessMode | default "") "ReadWriteMany")) }}
{{- fail "ERROR: persistence.localcache must stay node-local above one pod.\n  Moodle intends localcachedir for local node caching, and a claim shared between pods corrupts it.\n  Either:\n  1. Leave persistence.localcache unset, so the chart mounts a per-pod emptyDir\n  2. Set persistence.localcache.type=emptyDir" }}
{{- end }}
{{- if and $lc.enabled $lc.mountPath (ne $lc.mountPath "/var/www/moodledata/localcache") }}
{{- fail "ERROR: persistence.localcache.mountPath must be /var/www/moodledata/localcache.\n  The chart renders $CFG->localcachedir there and does not read this value." }}
{{- end }}

{{/* Validate PVC configuration consistency */}}
{{- range $name, $config := $persistence }}
{{- if and $config.enabled (eq $config.type "persistentVolumeClaim") }}
{{- if and $config.existingClaim (or $config.size $config.storageClass) }}
{{- fail (printf "ERROR: persistence.%s has both 'existingClaim' and PVC creation settings (size/storageClass).\n  When using existingClaim, remove: size and storageClass settings.\n  These settings are ignored when existingClaim is specified." $name) }}
{{- end }}
{{- if and (not $config.existingClaim) (not $config.size) }}
{{- fail (printf "ERROR: persistence.%s requires 'size' when creating a new PVC.\n  Either:\n  1. Set persistence.%s.size (e.g., '20Gi')\n  2. Use persistence.%s.existingClaim to reference an existing PVC" $name $name $name) }}
{{- end }}
{{- end }}
{{- end }}

{{/* Validate SMTP configuration consistency */}}
{{- $smtp := $moodle.smtp | default dict }}
{{- $smtpConfigured := or $smtp.host $smtp.port $smtp.user $smtp.password $smtp.existingSecret $smtp.protocol }}
{{- if and $smtpConfigured (not $smtp.host) (not (and $smtp.existingSecret $smtp.existingSecretHostKey)) }}
{{- fail "ERROR: moodle.smtp.host is required when any other moodle.smtp setting is configured.\n  Either:\n  1. Set moodle.smtp.host to the relay hostname\n  2. Set moodle.smtp.existingSecret and moodle.smtp.existingSecretHostKey to read it from a Secret\n  3. Remove every moodle.smtp setting to leave email unconfigured" }}
{{- end }}
{{- if and (or $smtp.password $smtp.existingSecret) (not $smtp.user) (not (and $smtp.existingSecret $smtp.existingSecretUserKey)) }}
{{- fail "ERROR: moodle.smtp.user is required when moodle.smtp.password or moodle.smtp.existingSecret is set.\n  Either:\n  1. Set moodle.smtp.user to the account the relay authenticates\n  2. Set moodle.smtp.existingSecretUserKey to read it from the same Secret\n  3. Remove the password settings, for a relay that authenticates by address" }}
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
{{- $knownKeys := list "moodledata" "moodle" "localcache" }}
{{- if and (not $config.mountPath) (not (has $name $knownKeys)) }}
{{- fail (printf "ERROR: persistence.%s.mountPath is required for custom volume names.\n  Standard volumes (moodledata, moodle, localcache) have default mount paths." $name) }}
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


{{/* Validate Image Digest */}}
{{- $image := .Values.image | default dict }}
{{- if and $image.digest (not $image.tag) }}
{{- fail "ERROR: image.digest is set and image.tag is empty. The chart reads the Moodle 5.0 and 5.1 public directory split from image.tag, and a digest carries no version, so the web root renders for the wrong layout and every page answers 404.\n  Set image.tag to the version the digest names. The digest still selects the image." }}
{{- end }}

{{/* Validate readOnlyDirroot configuration */}}
{{- $readOnlyDirroot := .Values.readOnlyDirroot | default dict }}
{{- $volume := $readOnlyDirroot.volume | default dict }}
{{- $perPodDirroot := or (not $volume) (hasKey $volume "emptyDir") (hasKey $volume "ephemeral") }}
{{- $multiPod := or (gt (.Values.replicaCount | default 1 | int) 1) $autoscaling.enabled }}
{{- $moodledata := $persistence.moodledata | default dict }}
{{- $updateStrategy := .Values.updateStrategy | default dict }}
{{- if $readOnlyDirroot.enabled }}

{{/* Validate Ephemeral Volume */}}
{{- if hasKey $volume "ephemeral" }}
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

{{/* Validate Shared Dataroot */}}
{{- if and $multiPod (not $moodledata.enabled) }}
{{- fail "ERROR: replicaCount > 1 (or autoscaling.enabled) with persistence.moodledata.enabled=false.\n  dataroot then lands on each pod's own container layer, so no replica shares it and every replica installs the schema at once.\n  Example: persistence.moodledata.type=persistentVolumeClaim with accessMode ReadWriteMany." }}
{{- end }}
{{- if and $multiPod $moodledata.enabled }}
{{- if eq ($moodledata.type | default "persistentVolumeClaim") "emptyDir" }}
{{- fail "ERROR: replicaCount > 1 (or autoscaling.enabled) with persistence.moodledata.type=emptyDir.\n  Moodle requires dataroot to be a shared directory that every cluster node accesses directly.\n  cachedir, tempdir and backuptempdir default inside it and must be shared too.\n  Example: persistence.moodledata.type=persistentVolumeClaim with accessMode ReadWriteMany." }}
{{- end }}
{{- if eq ($moodledata.accessMode | default "") "ReadWriteOnce" }}
{{- fail "ERROR: replicaCount > 1 with persistence.moodledata.accessMode=ReadWriteOnce. dataroot must be shared; use ReadWriteMany." }}
{{- end }}
{{- end }}

{{/* Validate Rollout Dataroot */}}
{{- if and (eq ($updateStrategy.type | default "RollingUpdate") "RollingUpdate") (not $multiPod) }}
{{- if not $moodledata.enabled }}
{{- fail "ERROR: updateStrategy.type=RollingUpdate with persistence.moodledata.enabled=false.\n  A rollout overlaps a second pod, and dataroot on each pod's own container layer is not shared between them.\n  Moodle enables maintenance mode by writing climaintenance.html into dataroot, so the pod still serving never sees it and keeps taking writes while the schema is upgraded.\n  Either:\n  1. Set updateStrategy.type=Recreate, which replaces the one pod instead of overlapping two.\n     A release already on RollingUpdate needs the strategy Kubernetes defaulted in cleared in the same patch:\n     kubectl patch deploy RELEASE-moodle -p '{\"spec\":{\"strategy\":{\"type\":\"Recreate\",\"rollingUpdate\":null}}}'\n  2. Set persistence.moodledata.type=persistentVolumeClaim, so both pods share dataroot" }}
{{- end }}
{{- if eq ($moodledata.type | default "persistentVolumeClaim") "emptyDir" }}
{{- fail "ERROR: updateStrategy.type=RollingUpdate with persistence.moodledata.type=emptyDir.\n  A rollout overlaps a second pod, and an emptyDir gives each of them its own dataroot.\n  Moodle enables maintenance mode by writing climaintenance.html into dataroot, so the pod still serving never sees it and keeps answering 200 and taking writes while the schema is upgraded.\n  Either:\n  1. Set updateStrategy.type=Recreate, which replaces the one pod instead of overlapping two.\n     A release already on RollingUpdate needs the strategy Kubernetes defaulted in cleared in the same patch:\n     kubectl patch deploy RELEASE-moodle -p '{\"spec\":{\"strategy\":{\"type\":\"Recreate\",\"rollingUpdate\":null}}}'\n  2. Set persistence.moodledata.type=persistentVolumeClaim, so both pods share dataroot" }}
{{- end }}
{{- end }}

{{/* Validate Dataroot Mount Path */}}
{{- if and $moodledata.enabled $moodledata.mountPath (ne $moodledata.mountPath "/var/www/moodledata") }}
{{- fail "ERROR: persistence.moodledata.mountPath is outside /var/www/moodledata, which is where dataroot is fixed.\n  The chart renders config.php with dataroot /var/www/moodledata, so the claim mounts where Moodle never reads, dataroot falls back to each pod's container layer, and every uploaded file and install record goes with the pod.\n  Set persistence.moodledata.mountPath to /var/www/moodledata." }}
{{- end }}

{{/* Validate Per-Pod Dirroot */}}
{{- if and $readOnlyDirroot.enabled (not $perPodDirroot) }}
{{- if $multiPod }}
{{- fail "ERROR: readOnlyDirroot.volume is a shared volume and more than one pod is requested.\n  Moodle recommends a local dirroot per node, and a shared one buys nothing here: every pod seeds the same tree, so on an image change several pods run a full rsync --delete over one another concurrently. Measured: two of three pods each re-synced the whole tree. It also forces updateStrategy.type=Recreate, giving up rolling updates, because a surge pod would re-seed the tree the live pod is serving from.\n  A per-pod dirroot avoids all of it and cannot diverge, since every pod seeds from the same image.\n  Either:\n  1. Set readOnlyDirroot.volume to {} for a per-pod emptyDir\n  2. Set readOnlyDirroot.volume.ephemeral.volumeClaimTemplate for a per-pod PVC" }}
{{- end }}
{{- if ne ($updateStrategy.type | default "RollingUpdate") "Recreate" }}
{{- fail "ERROR: readOnlyDirroot.volume is a shared volume and requires updateStrategy.type=Recreate.\n  With RollingUpdate the surge pod re-seeds the tree the live pod is serving from. Measured here: the live pod stopped serving login and began redirecting to /login/install.php, offering to install over a database that already holds the site, and it never recovered. The surge pod cannot finish either, because the live pod holds the files it is trying to replace open.\n  Either:\n  1. Set updateStrategy.type=Recreate\n  2. Set readOnlyDirroot.volume.ephemeral.volumeClaimTemplate for a per-pod PVC" }}
{{- end }}
{{- end }}

{{/* Validate Redis For Multiple Pods */}}
{{- if and $multiPod (not ($moodle.redis | default dict).host) }}
{{- fail "ERROR: replicaCount > 1 (or autoscaling.enabled) with no moodle.redis.host.\n  Moodle then keeps sessions as files in the shared dataroot, and PHP locks each session file while it is in use. Concurrent requests for one session across pods then serialise on that lock: measured here, 21 of 30 such requests stalled to the 60 second proxy timeout and were served as 404, against 30 of 30 answering 200 once Redis was configured. The site looks intermittently broken under load and the cause is not visible in the response.\n  Either:\n  1. Set moodle.redis.host to a Redis reachable from every pod\n  2. Run a single replica" }}
{{- end }}

{{/* Validate Supplied Config Is Read */}}
{{- if and (not $readOnlyDirroot.enabled) ($readOnlyDirroot.secret | default dict).name }}
{{- fail "ERROR: readOnlyDirroot.secret.name supplies a config.php, and with readOnlyDirroot.enabled=false the chart never mounts it: the image generates its own config.php instead, so your file is silently ignored.\n  Either:\n  1. Set readOnlyDirroot.enabled=true, where the chart mounts the file you supply\n  2. Unset readOnlyDirroot.secret.name and configure the site through the values below it" }}
{{- end }}

{{/* Validate Redis Password */}}
{{- if and (not $readOnlyDirroot.enabled) ($moodle.redis | default dict).password (or (regexMatch "['\\\\&|;]" (($moodle.redis | default dict).password | toString)) (hasPrefix "[" (($moodle.redis | default dict).password | toString)) (has (($moodle.redis | default dict).password | toString) (list "true" "false"))) }}
{{- fail "ERROR: moodle.redis.password contains a character the image cannot write into config.php. At readOnlyDirroot.enabled=false it is written with sed, so a quote breaks the file on the first boot and a backslash, an ampersand, a pipe or a semicolon rewrites or truncates the password on the next one; a leading [ and the literal true or false are written unquoted and change type.\n  Either:\n  1. Set moodle.redis.password to a value with none of ' \\ & | ; a leading [ or the words true and false\n  2. Set readOnlyDirroot.enabled=true, where the chart writes the password as getenv and never through sed" }}
{{- end }}

{{/* Validate Redis Port */}}
{{- $redis := $moodle.redis | default dict }}
{{- if and $redis.port (ne ($redis.port | toString) "6379") }}
{{- fail "ERROR: moodle.redis.port is not 6379. The image's configure_redis.php hardcodes 6379 and reads no REDIS_PORT, so any other value is accepted here and then fails the boot.\n  Either:\n  1. Set moodle.redis.port to 6379, or leave it unset\n  2. Publish your Redis on 6379, for example through a Service that maps 6379 to the real port" }}
{{- end }}

{{/* Validate Dirroot Ownership */}}
{{- if $readOnlyDirroot.enabled }}
{{- range $n := list "dirroot" "moodle" }}
{{- if (index $persistence $n | default dict).enabled }}
{{- fail (printf "ERROR: persistence.%s cannot be used with readOnlyDirroot.enabled=true - it collides with the chart's dirroot volume and mount path. Configure the code volume with readOnlyDirroot.volume instead." $n) }}
{{- end }}
{{- end }}
{{- end }}

{{/* Validate Shared Code Tree */}}
{{- if and $multiPod (not $readOnlyDirroot.enabled) }}
{{- range $index, $mount := (.Values.extraVolumeMounts | default list) }}
{{- $mountPath := $mount.mountPath | default "" }}
{{- if or (eq $mountPath "/var/www/html") (hasPrefix "/var/www/html/" $mountPath) }}
{{- range $vol := ($.Values.extraVolumes | default list) }}
{{- if eq ($vol.name | default "") ($mount.name | default "") }}
{{- if not (or (hasKey $vol "emptyDir") (hasKey $vol "ephemeral")) }}
{{- fail (printf "ERROR: extraVolumeMounts[%d] mounts %s at the code tree from a volume every pod shares, with more than one pod.\n  Moodle keeps dirroot per node: the same path on every node, never the same directory. One directory serving several pods swaps a running pod's code mid-request, and the plugin and component caches then describe a tree that no single pod has.\n  This is the same rule readOnlyDirroot enforces, and it does not depend on it.\n  Either:\n  1. Give the volume a per-pod source, ephemeral.volumeClaimTemplate or emptyDir\n  2. Run one pod\n  3. Set readOnlyDirroot.enabled=true and build the tree from the image instead" $index $mountPath) }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/* Validate Code Tree Mounts */}}
{{- if $readOnlyDirroot.enabled }}
{{- $roDirrootMessage := "ERROR: %s mounts %s inside the code tree with readOnlyDirroot.enabled=true.\n  A mount there hides every file the image ships under it whether or not it sets readOnly, and at a path the image does not ship the container cannot start at all.\n  Either:\n  1. Declare the code in moodle.plugins with its own url, which accepts any url and not only the Moodle plugins directory\n  2. Build an image from the Moodle image with the code already in the tree\n  3. Add an entry to initContainers that mounts the dirroot volume at /seed and writes the code there" }}
{{- range $index, $mount := (.Values.extraVolumeMounts | default list) }}
{{- $mountPath := $mount.mountPath | default "" }}
{{- if or (eq $mountPath "/var/www/html") (hasPrefix "/var/www/html/" $mountPath) }}
{{- fail (printf $roDirrootMessage (printf "extraVolumeMounts[%d]" $index) $mountPath) }}
{{- end }}
{{- end }}
{{- range $name, $config := $persistence }}
{{- $mountPath := $config.mountPath | default (ternary "/var/www/html" "" (eq $name "moodle")) }}
{{- if and $config.enabled (or (eq $mountPath "/var/www/html") (hasPrefix "/var/www/html/" $mountPath)) }}
{{- fail (printf $roDirrootMessage (printf "persistence.%s" $name) $mountPath) }}
{{- end }}
{{- end }}
{{- end }}

{{/* Validate Install Arguments */}}
{{- if not $readOnlyDirroot.enabled }}
{{- $installArgs := dict "moodle.site.url" (tpl ($site.url | default "") .) "moodle.site.language" ($site.language | default "en") "moodle.admin.username" (tpl ($admin.username | default "admin") .) "moodle.admin.email" (tpl ($admin.email | default "admin@example.com") .) "moodle.admin.password" ($admin.password | default "") "moodle.database.type" ($database.type | default "pgsql") "moodle.database.host" (tpl ($database.host | default "") .) "moodle.database.port" ($database.port | default "5432") "moodle.database.name" (tpl ($database.name | default "") .) "moodle.database.user" (tpl ($database.user | default "") .) "moodle.database.prefix" (tpl ($database.prefix | default "mdl_") .) "moodle.database.password" ($database.password | default "") }}
{{- range $path, $value := $installArgs }}
{{- if regexMatch "\\s" ($value | toString) }}
{{- fail (printf "ERROR: %s must not contain whitespace unless readOnlyDirroot.enabled=true.\n  The image generates config.php with an unquoted install.php argument list, so the value splits and the cold install aborts with 'Unrecognised options:' and CrashLoops the pod. With readOnlyDirroot enabled the chart owns config.php and the image never runs install.php.\n  Either:\n  1. Set readOnlyDirroot.enabled=true\n  2. Set %s to a value with no whitespace" $path $path) }}
{{- end }}
{{- end }}
{{- end }}

{{/* Validate Site Name */}}
{{- if and (not $readOnlyDirroot.enabled) (regexMatch "\\s" ($site.name | default "Moodle")) }}
{{- fail "ERROR: moodle.site.name must not contain whitespace unless readOnlyDirroot.enabled=true.\n  The image generates config.php with --fullname=$MOODLE_SITENAME unquoted, so a space aborts the cold install with 'Unrecognised options:' and CrashLoops the pod. With readOnlyDirroot enabled the chart owns config.php and quotes it.\n  This value reaches install.php and nothing else, so on a database that already holds a site it is never applied: the name you see is the one in the database, and the chart cannot tell the two cases apart before it renders. Adopting an existing site is therefore the case where this refusal costs the most and buys the least.\n  Either:\n  1. Set readOnlyDirroot.enabled=true\n  2. Put a single token here. On an existing site the real name stays in the database untouched, and on a new one set the full name afterwards from moodle.postConfigureCommands, with update_course from course/lib.php on SITEID"  }}
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

{{/* Validate Plugin Versions */}}
{{- range $index, $plugin := ($moodle.plugins | default list) }}
{{- $version := ternary (printf "%.15g" ($plugin.version | float64)) ($plugin.version | toString) (kindIs "float64" $plugin.version) }}
{{- if and $plugin.version (not (regexMatch "^[0-9]+$" $version)) }}
{{- fail (printf "ERROR: moodle.plugins[%d].version '%s' is not a Moodle version stamp, and the plugins directory resolves an unrecognised one to the oldest release it has.\n  Example: version: 2026042006" $index $version) }}
{{- end }}
{{- end }}

{{/* Validate Plugin Registration */}}
{{- if and $moodle.plugins (not (ternary $moodle.autoUpdateMoodle true (hasKey $moodle "autoUpdateMoodle"))) }}
{{- fail "ERROR: moodle.plugins is set with moodle.autoUpdateMoodle=false. The plugin code lands in dirroot and nothing registers it, so versiondb stays null, Moodle suspends cron for the whole site, and the pod stays Ready while the site answers 200.\n  Either:\n  1. Set moodle.autoUpdateMoodle=true\n  2. Remove moodle.plugins and ship the plugins in an image built from the Moodle image" }}
{{- end }}

{{/* Validate OIDC configuration */}}
{{- $oidc := $moodle.oidc | default dict }}
{{- if $oidc.enabled }}
  {{- if not ($oidc.discoveryUrl | default "") }}
    {{- fail "ERROR: moodle.oidc.discoveryUrl is required when moodle.oidc.enabled=true.\n  Set this to your provider's .well-known/openid-configuration URL.\n  e.g., 'https://keycloak.example.com/realms/my-realm/.well-known/openid-configuration'" }}
  {{- end }}
  {{- if not (hasPrefix "https://" (tpl ($oidc.discoveryUrl | default "") .)) }}
    {{- fail "ERROR: moodle.oidc.discoveryUrl must be an https URL. Moodle refuses every OAuth2 issuer base URL that is not https, so the chart installs the schema and then the provider step fails and the pod CrashLoops.\n  Example: discoveryUrl: 'https://keycloak.example.com/realms/my-realm/.well-known/openid-configuration'" }}
  {{- end }}
  {{- if not $oidc.clientId }}
    {{- fail "ERROR: moodle.oidc.clientId is required when moodle.oidc.enabled=true" }}
  {{- end }}
  {{- if and (not $oidc.existingSecret) (not $oidc.clientSecret) }}
    {{- fail "ERROR: OIDC client secret must be configured.\n  Either:\n  1. Set moodle.oidc.clientSecret (for dev/testing)\n  2. Set moodle.oidc.existingSecret (recommended for production)" }}
  {{- end }}
  {{- if not $oidc.name }}
    {{- fail "ERROR: moodle.oidc.name is required when moodle.oidc.enabled=true.\n  It is the provider name shown on the Moodle login page, e.g., 'Keycloak'" }}
  {{- end }}
  {{- if not $oidc.userFieldMappings }}
    {{- fail "ERROR: moodle.oidc.userFieldMappings is required when moodle.oidc.enabled=true.\n  At minimum, set: userFieldMappings: [\"sub:idnumber\"]" }}
  {{- end }}
{{- end }}

{{- end }}

{{/*
Redis session key prefix. Moodle namespaces cache *values* by siteidentifier, but session keys are
raw: the handler only sets Redis OPT_PREFIX when one is configured, and it stores a hash per user at
user_<userid>. User ids are small integers, so two releases on one Redis share user_2. Default to a
value derived from the release; changing it resets sessions.
*/}}
{{- define "moodle.redis.sessionPrefix" -}}
{{- $redis := (.Values.moodle | default dict).redis | default dict -}}
{{- if $redis.sessionPrefix -}}
{{- tpl $redis.sessionPrefix . -}}
{{- else -}}
{{- printf "%s-%s-" .Release.Namespace .Release.Name -}}
{{- end -}}
{{- end -}}

{{/*
Redis MUC store key prefix. cachestore_redis purges by unlinking the whole definition hash, and that
hash is md5("mode component area") with nothing site specific in it, so a purge on one release drops
another release's entries. Moodle permits at most 5 characters here, so derive a short digest rather
than a name.
*/}}
{{- define "moodle.redis.cachePrefix" -}}
{{- $redis := (.Values.moodle | default dict).redis | default dict -}}
{{- if $redis.cachePrefix -}}
{{- tpl $redis.cachePrefix . -}}
{{- else -}}
{{- printf "%s/%s" .Release.Namespace .Release.Name | sha256sum | trunc 5 -}}
{{- end -}}
{{- end -}}

{{/*
Render a value that may contain template syntax.
Free-form values -- annotations, labels, env vars, volumes, scheduling -- are written by the
operator, and an umbrella chart usually wants {{ .Values.global.* }} in them. Every such block
goes through here so they all behave the same way, whichever object they land on.
Usage: {{ include "moodle.tplvalues.render" (dict "value" .Values.podLabels "context" $) }}
*/}}
{{- define "moodle.tplvalues.render" -}}
{{- if typeIs "string" .value }}
{{- tpl .value .context }}
{{- else }}
{{- tpl (.value | toYaml) .context }}
{{- end }}
{{- end -}}

{{/*
Split moodle.config into literal values and values that name a Secret.
A value that is a map is a reference and must carry exactly existingSecret and key.
Map iteration in Helm is key-sorted, so the generated variable names are stable across renders.
Returns {plain: <config without references>, refs: [{plugin,name,secret,key,env}]}
*/}}
{{- define "moodle.config.split" -}}
{{- $cfg := fromYaml (tpl (toYaml .Values.moodle.config) $) -}}
{{- $plain := dict -}}
{{- $refs := list -}}
{{- $i := 0 -}}
{{- range $plugin, $settings := $cfg }}
  {{- $keep := dict -}}
  {{- range $name, $value := $settings }}
    {{- if kindIs "map" $value }}
      {{- if not (and (hasKey $value "existingSecret") (hasKey $value "key")) }}
        {{- fail (printf "ERROR: moodle.config.%s.%s is a map, so it must name a Secret with existingSecret and key.\n  Either:\n  1. Set existingSecret and key to read the value from a Secret\n  2. Give a plain value" $plugin $name) }}
      {{- end }}
      {{- range $k, $v := $value }}
        {{- if not (has $k (list "existingSecret" "key")) }}
          {{- fail (printf "ERROR: moodle.config.%s.%s has an unknown field %q. A Secret reference takes existingSecret and key only." $plugin $name $k) }}
        {{- end }}
      {{- end }}
      {{- if not $value.existingSecret }}
        {{- fail (printf "ERROR: moodle.config.%s.%s has an empty existingSecret. Name the Secret holding the value." $plugin $name) }}
      {{- end }}
      {{- if not $value.key }}
        {{- fail (printf "ERROR: moodle.config.%s.%s has an empty key. Name the key inside %s." $plugin $name $value.existingSecret) }}
      {{- end }}
      {{- $refs = append $refs (dict "plugin" $plugin "name" $name "secret" $value.existingSecret "key" $value.key "env" (printf "MOODLE_CFGSECRET_%d" $i)) -}}
      {{- $i = add1 $i -}}
    {{- else }}
      {{- $_ := set $keep $name $value -}}
    {{- end }}
  {{- end }}
  {{- if $keep }}{{- $_ := set $plain $plugin $keep -}}{{- end }}
{{- end }}
{{- toYaml (dict "plain" $plain "refs" $refs) -}}
{{- end -}}
