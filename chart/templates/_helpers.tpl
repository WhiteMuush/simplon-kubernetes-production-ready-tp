{{/*
Both helpers take a dict, because they are called from inside a range where the
scope is the service, not the chart root: {{ include "..." (dict "root" $ "name" $name) }}
*/}}

{{/* Kept minimal: the selector is immutable once the Deployment exists. */}}
{{- define "microservices.selectorLabels" -}}
app: {{ .name }}
{{- end }}

{{- define "microservices.labels" -}}
app: {{ .name }}
helm.sh/chart: {{ .root.Chart.Name }}-{{ .root.Chart.Version }}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- end }}
