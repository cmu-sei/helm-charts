{{/* vim: set filetype=mustache: */}}
{{/*
Generate the proper ingress API
It expects a dictionary with two entries:
  - `ingress` which contains ingress settings (.Values.ingress)
  - `context` the parent context (`.` or `$`)

Usage:
{{ include "common.ingress.apiVersion "ingress" .Values.ingress "context" $ }}
*/}}

{{- define "common.ingress.apiVersion" -}}
{{- if .ingress.apiVersion -}}
{{- .ingress.apiVersion -}}
{{- else if .context.Capabilities.APIVersions.Has "networking.k8s.io/v1" -}}
{{- print "networking.k8s.io/v1" -}}
{{- else if .context.Capabilities.APIVersions.Has "networking.k8s.io/v1beta1" -}}
{{- print "networking.k8s.io/v1beta1" -}}
{{- else -}}
{{- print "extensions/v1beta1" -}}
{{- end }}
{{- end }}

{{/*
Returns true if the ingressClassname field is supported 
expects dict with one entry:
	- `apiVersion` - supported ingress api version (common.ingress.apiVersion)
Usage:
{{- include "common.ingress.supportsIngressClassname"  (dict "apiVersion" $apiVersion) }}
*/}}

{{- define "common.ingress.supportsIngressClassname" -}}
{{- if eq .apiVersion "networking.k8s.io/v1" -}}
{{- print "true" -}}
{{- else -}}
{{- print "false" -}}
{{- end }}
{{- end }}

{{/*
Returns true if the pathType field is supported 
expects dict with one entry:
	- `apiVersion` - supported ingress api version (common.ingress.apiVersion)
Usage:
{{- include "common.ingress.supportsPathType"  (dict "apiVersion" $apiVersion) }}
*/}}

{{- define "common.ingress.supportsPathType" -}}
{{- if eq .apiVersion "networking.k8s.io/v1" -}}
{{- print "true" -}}
{{- else -}}
{{- print "false" -}}
{{- end }}
{{- end }}

{{/*
Formats a backend stanza for ingress based on api availability 
expects dict with four entries:
  - `ingress` which contains ingress settings (.Values.ingress)
	- `apiVersion` - supported ingress api version (common.ingress.apiVersion)
  - `serviceName`  - service name
	- `servicePort` - servicePort
Usage:
{{- include "common.ingress.formatBackend"  (dict "apiVersion" $apiVersion "ingress" .Values.ingress "svcName" $fullName "svcPort" $svcPort) }}
*/}}

{{- define "common.ingress.formatBackend" -}}
{{- if or (eq .apiVersion "extensions/v1beta1") (eq .apiVersion "networking.k8s.io/v1beta1") -}}
serviceName: {{ .svcName }}
servicePort: {{ .svcPort }}
{{- else -}}
service:
  name: {{ .svcName }}
  port:
    {{- if typeIs "string" .svcPort }}
    name: {{ .svcPort }}
    {{- else if or (typeIs "int" .svcPort) (typeIs "float64" .svcPort) }}
    number: {{ .svcPort | int }}
		{{- end }}
{{- end }}
{{- end }}


{{/*
Renders a Ingress for the webservice

It expects a dictionary with the entries:
  - `name` the Ingress name to use
  - `rootContext` the root context ($)
  - `localContext` the context of the deployment to render the Ingress for (.)
  - `ingress` which contains ingress settings (.Values.ingress)
  - `name` 
Usage - 
{{- include "common.ingress.template" (dict "rootContext" $ "localContext" . "ingress" .Values.ingress "fullName" $fullName  "svcPort" $svcPort) }}

*/}}

{{- define "common.ingress.template" }}
{{- $global := .rootContext.Values.global }}
{{- $apiVersion := include "common.ingress.apiVersion" (dict "ingress" .ingress "context" .rootContext) }}
{{- $svcName := .fullName }}
{{- $svcPort := .svcPort }}
---
apiVersion: {{ $apiVersion  }}
kind: Ingress
metadata: 
  name: {{ .fullName }}
  labels: {{- (include "common.labels.default" .localContext) | nindent 4 }}
  {{- with .ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:  
  {{- if and .ingress.ingressClassName (eq "true" (include "common.ingress.supportsIngressClassname" (dict "apiVersion" $apiVersion))) }}
  ingressClassName: {{ .ingress.ingressClassName | quote }}
  {{- end }}
  rules: 
    {{- range .ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            {{- if include "common.ingress.supportsPathType" (dict "apiVersion" $apiVersion) }}
            pathType: {{ default "ImplementationSpecific" .pathType }}
            {{- end }}
            backend: {{- include "common.ingress.formatBackend"  (dict "apiVersion" $apiVersion "ingress" .ingress "svcName" $svcName "svcPort" $svcPort)  | nindent 14 -}}
          {{- end }}
    {{- end }}
  {{- if .ingress.tls }}
  tls:
    {{- range .ingress.tls }}
    - hosts:
      {{-  range .hosts }}
        - {{ . | quote }}
      {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
{{- end}}
