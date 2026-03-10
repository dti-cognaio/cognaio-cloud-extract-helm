{{/*
Expand the name of the chart.
*/}}
{{- define "cognaio.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "cognaio.fullname" -}}
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
{{- define "cognaio.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "cognaio.labels" -}}
helm.sh/chart: {{ include "cognaio.chart" . }}
{{ include "cognaio.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.labels }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cognaio.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cognaio.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "cognaio.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "cognaio.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create correctly quoteted organization users list like: "'email_1@example.com','email_2@example.com'"
*/}}
{{- define "cognaio.organizationUsers" -}}
{{- $users := .Values.cognaioservice.env.organization.users }}
{{- if $users }}
{{- $quotedUsers := list }}
{{- range $users }}
{{- $quotedUser := printf "'%s'" . }}
{{- $quotedUsers = append $quotedUsers $quotedUser }}
{{- end }}
{{- join "," $quotedUsers | quote }}
{{- else }}
{{- "" | quote }}
{{- end }}
{{- end }}

{{/*
Create database schemas string from list.
Usage: {{ include "cognaio.dbSchemas" .Values.someservice.env.db.schemas }}
*/}}
{{- define "cognaio.dbSchemas" -}}
{{- if . -}}
{{- join "; " . -}}
{{- end -}}
{{- end -}}