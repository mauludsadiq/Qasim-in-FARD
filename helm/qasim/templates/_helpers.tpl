{{- define "qasim.fullname" -}}
{{- .Release.Name }}-qasim
{{- end }}

{{- define "qasim.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{ include "qasim.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "qasim.selectorLabels" -}}
app.kubernetes.io/name: qasim
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
