{{/*
Expand the name of the chart.
*/}}
{{- define "gatus.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "gatus.fullname" -}}
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
Create chart label.
*/}}
{{- define "gatus.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to every resource.
*/}}
{{- define "gatus.labels" -}}
helm.sh/chart: {{ include "gatus.chart" . }}
{{ include "gatus.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "gatus.selectorLabels" -}}
app.kubernetes.io/name: {{ include "gatus.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Name of the ConfigMap.
*/}}
{{- define "gatus.configMapName" -}}
{{- printf "%s-config" (include "gatus.fullname" .) }}
{{- end }}

{{/*
Name of the PVC.
*/}}
{{- define "gatus.pvcName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- printf "%s-data" (include "gatus.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Name of the ServiceAccount.
*/}}
{{- define "gatus.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "gatus.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Name of the discovery CronJob ServiceAccount.
*/}}
{{- define "gatus.discoveryServiceAccountName" -}}
{{- printf "%s-discovery-sa" (include "gatus.fullname" .) }}
{{- end }}

{{/*
Render a single Gatus endpoint block, merging endpoint-level overrides
on top of the endpointDefaults from values.
Usage: {{ include "gatus.endpoint" (dict "ep" $ep "defaults" .Values.gatus.endpointDefaults) }}
*/}}
{{- define "gatus.endpoint" -}}
{{- $ep := .ep }}
{{- $d  := .defaults }}
- name: {{ $ep.name | quote }}
  {{- if $ep.group }}
  group: {{ $ep.group | quote }}
  {{- end }}
  url: {{ $ep.url | quote }}
  interval: {{ default $d.interval $ep.interval }}
  {{- if $ep.method }}
  method: {{ $ep.method }}
  {{- end }}
  {{- if $ep.body }}
  body: {{ $ep.body | quote }}
  {{- end }}
  {{- if $ep.headers }}
  headers:
    {{- toYaml $ep.headers | nindent 4 }}
  {{- end }}
  {{- if $ep.client }}
  client:
    {{- toYaml $ep.client | nindent 4 }}
  {{- end }}
  conditions:
    {{- range (default $d.conditions $ep.conditions) }}
    - {{ . | quote }}
    {{- end }}
  {{- if $ep.alerts }}
  alerts:
    {{- toYaml $ep.alerts | nindent 4 }}
  {{- end }}
{{- end }}
