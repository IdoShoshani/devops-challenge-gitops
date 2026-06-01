{{/*
Resource short name. All current templates use this; equal to the chart name today.
*/}}
{{- define "sample-nodejs.name" -}}
{{ .Chart.Name }}
{{- end -}}

{{/*
Fully qualified resource name (additive helper, not yet referenced in templates).
Collapses doubled names: when .Release.Name already contains .Chart.Name, return
.Release.Name as-is — otherwise return "<release>-<chart>". This is the idiomatic
Helm pattern (`helm create`-style) and makes the chart multi-release-safe without
renaming any current resource (release "sample-nodejs" -> "sample-nodejs").
*/}}
{{- define "sample-nodejs.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Chart name + version label, with `+` replaced (illegal in label values).
*/}}
{{- define "sample-nodejs.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels applied to every rendered resource.
*/}}
{{- define "sample-nodejs.labels" -}}
helm.sh/chart: {{ include "sample-nodejs.chart" . }}
app.kubernetes.io/name: {{ include "sample-nodejs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels (subset of common labels — must NOT change across releases of a
Deployment, since selectors are immutable on apps/v1 Deployment).
*/}}
{{- define "sample-nodejs.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sample-nodejs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
