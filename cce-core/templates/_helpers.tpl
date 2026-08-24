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
Create correctly quoted organization users list like: "'email_1@example.com','email_2@example.com'"
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
{{/*
==============================================================================
OpenTelemetry (OTel)
==============================================================================
The OTel configuration lives GLOBALLY under .Values.otel and applies to every
instrumented service. A service can override enabled / serviceName / endpoint /
captureHeaders under <service>.otel (see values.yaml).

All services are built so that telemetry stays OFF as long as no OTLP endpoint
is configured or OTEL_SDK_DISABLED=true. With otel.enabled false the chart
therefore renders no OTEL_* variables at all and keeps the normal image tags -
the rendered deployment is identical to an installation without OTel support.
*/}}

{{/*
Is telemetry enabled for a service?
Usage: include "cognaio.otel.enabled" (dict "root" $ "svc" .Values.cognaioservice)
Returns "true" or "" (empty = falsy for if/with).
*/}}
{{- define "cognaio.otel.enabled" -}}
{{- $global := .root.Values.otel | default dict -}}
{{- $svcOtel := (.svc | default dict).otel | default dict -}}
{{- $enabled := $global.enabled | default false -}}
{{- if and (hasKey $svcOtel "enabled") (not (kindIs "invalid" $svcOtel.enabled)) -}}
{{- $enabled = $svcOtel.enabled -}}
{{- end -}}
{{- if $enabled -}}true{{- end -}}
{{- end -}}

{{/*
Complete OTEL_* env block of a container. Renders nothing when telemetry is
disabled for the service.
Usage:
  {{- $otelEnv := include "cognaio.otelEnv" (dict "root" $ "svc" .Values.cognaioservice "serviceName" "cognaioservice") }}
Parameters:
  root         chart context ($)
  svc          values sub tree of the service (for <service>.otel)
  serviceName  default for OTEL_SERVICE_NAME
  protocol     "http" (default, Node/Python) or "grpc" (.NET)
  noCapture    true => no OTEL_CAPTURE_HEADERS (worker without HTTP server)
  noPropagate  true => no OTEL_PROPAGATORS (worker without incoming context)
*/}}
{{- define "cognaio.otelEnv" -}}
{{- $root := .root -}}
{{- $svc := .svc | default dict -}}
{{- $global := $root.Values.otel | default dict -}}
{{- $svcOtel := $svc.otel | default dict -}}
{{- if include "cognaio.otel.enabled" (dict "root" $root "svc" $svc) -}}
{{/* The .NET services export via gRPC (:4317), Node/Python via HTTP (:4318). */}}
{{- $grpc := eq (.protocol | default "http") "grpc" -}}
{{- $endpoint := $svcOtel.endpoint | default (ternary $global.endpointGrpc $global.endpoint $grpc) | default "" -}}
{{- if not $endpoint -}}
{{- fail (printf "otel.enabled is true but no OTLP endpoint is configured for '%s' - set otel.endpoint / otel.endpointGrpc or <service>.otel.endpoint" (.serviceName | default "unknown")) -}}
{{- end -}}
{{- $env := list -}}
{{- $env = append $env (dict "name" "OTEL_SDK_DISABLED" "value" "false") -}}
{{- $env = append $env (dict "name" "OTEL_EXPORTER_OTLP_ENDPOINT" "value" $endpoint) -}}
{{- $env = append $env (dict "name" "OTEL_SERVICE_NAME" "value" ($svcOtel.serviceName | default .serviceName)) -}}
{{- if and $global.propagators (not .noPropagate) -}}
{{- $env = append $env (dict "name" "OTEL_PROPAGATORS" "value" $global.propagators) -}}
{{- end -}}
{{/*
OTEL_RESOURCE_ATTRIBUTES applies to all three signals and shows up in Tempo as
resource.<key>, in Loki/Prometheus as <key_with_underscores>. Therefore: own
namespace prefix, low cardinality, no personal data.
*/}}
{{- $attributes := $global.resourceAttributes | default dict -}}
{{- $pairs := list -}}
{{- range $key := (keys $attributes | sortAlpha) -}}
{{- $pairs = append $pairs (printf "%s=%v" $key (get $attributes $key)) -}}
{{- end -}}
{{- if $pairs -}}
{{- $env = append $env (dict "name" "OTEL_RESOURCE_ATTRIBUTES" "value" (join "," $pairs)) -}}
{{- end -}}
{{- $captureHeaders := $svcOtel.captureHeaders | default $global.captureHeaders | default "" -}}
{{- if and $captureHeaders (not .noCapture) -}}
{{- $env = append $env (dict "name" "OTEL_CAPTURE_HEADERS" "value" $captureHeaders) -}}
{{- end -}}
{{- range $extra := ($global.extraEnv | default list) -}}
{{- $env = append $env $extra -}}
{{- end -}}
{{- toYaml $env -}}
{{- end -}}
{{- end -}}

