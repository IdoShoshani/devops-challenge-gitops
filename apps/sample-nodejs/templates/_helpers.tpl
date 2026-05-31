{{- define "sample-nodejs.name" -}}
{{ .Chart.Name }}
{{- end -}}

{{- define "sample-nodejs.labels" -}}
app.kubernetes.io/name: {{ include "sample-nodejs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{- define "sample-nodejs.selectorLabels" -}}
app.kubernetes.io/name: {{ include "sample-nodejs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
