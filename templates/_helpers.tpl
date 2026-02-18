{{/*
Expand the name of the chart.
*/}}
{{- define "edgequota.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
*/}}
{{- define "edgequota.fullname" -}}
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
{{- define "edgequota.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "edgequota.labels" -}}
helm.sh/chart: {{ include "edgequota.chart" . }}
{{ include "edgequota.selectorLabels" . }}
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
{{- define "edgequota.selectorLabels" -}}
app.kubernetes.io/name: {{ include "edgequota.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "edgequota.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "edgequota.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the image name
*/}}
{{- define "edgequota.image" -}}
{{- $registry := .Values.image.registry -}}
{{- $repository := .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if $registry }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- else }}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{/*
Config file mount path
*/}}
{{- define "edgequota.configPath" -}}
/etc/edgequota
{{- end }}

{{/*
TLS cert mount path
*/}}
{{- define "edgequota.tlsPath" -}}
/etc/edgequota/tls
{{- end }}

{{/*
Return the admin container port
*/}}
{{- define "edgequota.adminPort" -}}
{{- .Values.edgequota.admin.port | default 9090 }}
{{- end }}

{{/*
Return the proxy container port
*/}}
{{- define "edgequota.proxyPort" -}}
{{- .Values.edgequota.server.port | default 8080 }}
{{- end }}

{{/*
Return the proxy service port: 443 when TLS is enabled, 80 otherwise
*/}}
{{- define "edgequota.servicePort" -}}
{{- if .Values.edgequota.server.tls.enabled -}}
443
{{- else -}}
80
{{- end -}}
{{- end }}

{{/*
Return the proxy service port name
*/}}
{{- define "edgequota.servicePortName" -}}
{{- if .Values.edgequota.server.tls.enabled -}}
https
{{- else -}}
http
{{- end -}}
{{- end }}

{{/*
Render endpoints as a YAML list. Accepts either a list of strings or a single
comma-separated string (for backwards compatibility). Always outputs a YAML list.
Usage: include "edgequota.endpointsList" .Values.edgequota.redis.endpoints
*/}}
{{- define "edgequota.endpointsList" -}}
{{- if kindIs "slice" . -}}
{{ toYaml . }}
{{- else -}}
{{ toYaml (splitList "," . | compact) }}
{{- end -}}
{{- end }}

{{/*
Checksum annotations for rolling restarts on config/secret changes
*/}}
{{- define "edgequota.checksumAnnotations" -}}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
{{- if .Values.secrets.create }}
checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
{{- end }}
{{- end }}
