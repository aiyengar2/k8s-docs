{{/* vim: set filetype=mustache: */}}
{{/*
A special ConfigMap from a template
*/}}
{{- define "simple-chart.specialConfigMap" -}}
{{- if .Values.specialConfigMap }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: specialConfigMap
  namespace: {{ .Release.Namespace }}
{{- end }}
{{- end -}}

{{- define "simple-chart.specialConfigMap2" -}}
{{- if .specialConfigMap }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: specialConfigMap2
  namespace: default
{{- end }}
{{- end -}}
