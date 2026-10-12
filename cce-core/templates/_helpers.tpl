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

{{/*
==============================================================================
SchemaManager gate (encryption 3.1.0)
==============================================================================
Since 3.1.0 the SchemaManager is a Job rather than an init container of the
cognaioservice pod, because the crypto provider has to be ready before it can
run. That makes the chain crypto -> SchemaManager -> everything else, and the
last arrow needs a mechanism: without one, all pods start at once and the
services hit a database the migrator has not touched yet.

This is that mechanism. An init container polls the Job's completion through the
Kubernetes API using the service account token of its own pod (the Role in
cognaio-schema-manager/rbac.yaml grants `get` on batch/jobs). A failed migration
never becomes a running service - the pod simply stays in Init.

Renders nothing when cognaioschemamanager.gate.enabled is false. The services
then fail loud on a half-migrated database and CrashLoopBackOff until the Job is
through, which Kubernetes heals on its own - noisier, but no RBAC needed.
*/}}

{{/*
Name of the SchemaManager Job. A completed Job is immutable, so something has to
recreate it or the migration silently does not run on the next rollout.

With jobNamePerRevision (the default) the name carries the release revision: a new
name is a new Job and Helm removes the previous one, so plain `helm upgrade` is
correct without help. Set it to false only when the delivery tool guarantees
delete-before-create (an ArgoCD Sync hook with BeforeHookCreation) - then the name
is stable and the gated services stop rolling on every sync.

Usage: {{ include "cognaio.schemaManagerJobName" . }}
*/}}
{{- define "cognaio.schemaManagerJobName" -}}
{{- $sm := .Values.cognaioschemamanager -}}
{{- if $sm.jobNamePerRevision -}}
{{- printf "%s-r%d" $sm.name (.Release.Revision | int) -}}
{{- else -}}
{{- $sm.name -}}
{{- end -}}
{{- end -}}

{{/*
The gate init container. Emits the whole `initContainers:` key, so it is included
directly under a pod `spec:`.
Usage: {{- include "cognaio.schemaManagerGate" $ | nindent 6 }}
*/}}
{{- define "cognaio.schemaManagerGate" -}}
{{- $gate := .Values.cognaioschemamanager.gate -}}
{{- if $gate.enabled -}}
initContainers:
  - name: wait-for-schema-manager
    image: {{ .Values.image.containerRegistry }}/{{ $gate.image.name }}:{{ $gate.image.tag }}
    imagePullPolicy: {{ .Values.image.pullPolicy }}
    {{- with .Values.securityContext }}
    securityContext:
      {{- toYaml . | nindent 6 }}
    {{- end }}
    command: ["/bin/sh", "-c"]
    args:
      - |
        # Never wait mutely. A gate that cannot tell "the migration is not finished yet" from
        # "I am not allowed to ask" looks exactly like a slow migration from the outside, and
        # costs an hour of debugging. Every answer the API gives is either acted on or printed.
        SA=/var/run/secrets/kubernetes.io/serviceaccount
        JOB={{ include "cognaio.schemaManagerJobName" . }}
        URL="https://kubernetes.default.svc/apis/batch/v1/namespaces/$(cat $SA/namespace)/jobs/$JOB"
        echo "gate: waiting for schema manager job $JOB"
        n=0
        while true; do
          BODY=$(wget -q -O- --no-check-certificate \
                   --header="Authorization: Bearer $(cat $SA/token)" "$URL" 2>&1) \
            || BODY="GATE_REQUEST_FAILED $BODY"
          # Whitespace-normalised, so matching does not depend on whether the api server answers
          # with compact or pretty-printed json.
          FLAT=$(echo "$BODY" | tr -d ' \t\n')
          case "$FLAT" in
            *'"succeeded":'[1-9]*)
              echo "gate: job $JOB succeeded - starting"
              exit 0 ;;
            *'"code":403'*)
              # A permission problem never resolves itself, so waiting for it is pointless.
              echo "gate: FORBIDDEN to read job $JOB in namespace $(cat $SA/namespace)."
              echo "gate: the Role/RoleBinding for this pod's service account is missing."
              exit 1 ;;
            *'"code":404'*)
              : ;;   # expected right after a rollout - the Job may not exist yet
            *GATE_REQUEST_FAILED*)
              echo "gate: cannot reach the kubernetes api: $BODY" ;;
          esac
          n=$((n + 1))
          if [ $((n % 12)) -eq 0 ]; then
            # The status object sits at the END of the job json - the first bytes are metadata
            # and would tell you nothing.
            echo "gate: still waiting after $((n * {{ $gate.pollSeconds }}))s - tail: $(echo "$FLAT" | tail -c 300)"
          fi
          sleep {{ $gate.pollSeconds }}
        done
    {{- with $gate.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end -}}
{{- end -}}
