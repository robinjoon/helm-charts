{{/*
Expand the name of the chart.
*/}}
{{- define "second-brain.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "second-brain.fullname" -}}
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
{{- define "second-brain.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "second-brain.labels" -}}
helm.sh/chart: {{ include "second-brain.chart" . }}
{{ include "second-brain.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "second-brain.selectorLabels" -}}
app.kubernetes.io/name: {{ include "second-brain.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "second-brain.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "second-brain.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference.
*/}}
{{- define "second-brain.image" -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end }}

{{/*
Migration job name. Argo CD renders Helm with a stable .Release.Revision, so
include the image tag to create a fresh Job when the deployed image changes.
*/}}
{{- define "second-brain.migrationJobName" -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- $suffix := regexReplaceAll "[^a-z0-9-]+" (lower $tag) "-" | trimAll "-" -}}
{{- printf "%s-migrate-%s" (include "second-brain.fullname" .) $suffix | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
ConfigMap name.
*/}}
{{- define "second-brain.configMapName" -}}
{{- printf "%s-env" (include "second-brain.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Secret name.
*/}}
{{- define "second-brain.secretName" -}}
{{- if .Values.secretRefs.existingSecret }}
{{- .Values.secretRefs.existingSecret }}
{{- else }}
{{- printf "%s-env" (include "second-brain.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
PVC name.
*/}}
{{- define "second-brain.pvcName" -}}
{{- if .Values.persistence.existingClaim }}
{{- .Values.persistence.existingClaim }}
{{- else }}
{{- printf "%s-data" (include "second-brain.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Shared envFrom sources.
*/}}
{{- define "second-brain.envFrom" -}}
- configMapRef:
    name: {{ include "second-brain.configMapName" . }}
{{- if or .Values.secretRefs.existingSecret .Values.secretRefs.create }}
- secretRef:
    name: {{ include "second-brain.secretName" . }}
{{- end }}
{{- with .Values.config.extraEnvFrom }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Default internal app URL for the worker.
*/}}
{{- define "second-brain.workerAppBaseUrl" -}}
{{- if .Values.worker.appBaseUrl }}
{{- .Values.worker.appBaseUrl }}
{{- else }}
{{- printf "http://%s:%v" (include "second-brain.fullname" .) .Values.service.port }}
{{- end }}
{{- end }}

{{/*
AI proxy Service name.
*/}}
{{- define "second-brain.aiProxyServiceName" -}}
{{- if .Values.aiProxy.service.name }}
{{- .Values.aiProxy.service.name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-ai-proxy" (include "second-brain.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
AI proxy config Secret name.
*/}}
{{- define "second-brain.aiProxyConfigSecretName" -}}
{{- if .Values.aiProxy.internal.existingConfigSecret }}
{{- .Values.aiProxy.internal.existingConfigSecret }}
{{- else }}
{{- printf "%s-config" (include "second-brain.aiProxyServiceName" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
AI proxy auth PVC name.
*/}}
{{- define "second-brain.aiProxyAuthPvcName" -}}
{{- if .Values.aiProxy.internal.persistence.existingClaim }}
{{- .Values.aiProxy.internal.persistence.existingClaim }}
{{- else }}
{{- printf "%s-auth" (include "second-brain.aiProxyServiceName" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
AI proxy logs PVC name.
*/}}
{{- define "second-brain.aiProxyLogsPvcName" -}}
{{- if .Values.aiProxy.internal.logsPersistence.existingClaim }}
{{- .Values.aiProxy.internal.logsPersistence.existingClaim }}
{{- else }}
{{- printf "%s-logs" (include "second-brain.aiProxyServiceName" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
AI proxy base URL injected into Second Brain.
*/}}
{{- define "second-brain.aiProxyBaseUrl" -}}
{{- if .Values.aiProxy.baseUrl }}
{{- .Values.aiProxy.baseUrl }}
{{- else }}
{{- printf "http://%s:%v/v1" (include "second-brain.aiProxyServiceName" .) .Values.aiProxy.service.port }}
{{- end }}
{{- end }}

{{/*
Explicit AI proxy env for app-like pods.
*/}}
{{- define "second-brain.aiProxyEnv" -}}
{{- if and .Values.aiProxy.enabled .Values.aiProxy.useAsAppAiBaseUrl }}
- name: AI_BASE_URL
  value: {{ include "second-brain.aiProxyBaseUrl" . | quote }}
{{- end }}
{{- end }}

{{/*
Validate values that cannot be expressed in the schema.
*/}}
{{- define "second-brain.validate" -}}
{{- if .Values.aiProxy.enabled }}
{{- if not (or (eq .Values.aiProxy.mode "internal") (eq .Values.aiProxy.mode "external")) }}
{{- fail "aiProxy.mode must be either internal or external" }}
{{- end }}
{{- if and (eq .Values.aiProxy.mode "external") (empty .Values.aiProxy.external.addresses) }}
{{- fail "aiProxy.external.addresses must contain at least one IP address when aiProxy.mode=external" }}
{{- end }}
{{- end }}
{{- end }}
