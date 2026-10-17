{{- define "dify.name" -}}
{{- default (printf "%s-dify" .Release.Name) .Values.nameOverride | trunc 40 | trimSuffix "-" -}}
{{- end -}}
{{- define "dify.env" -}}
{{- $config := dict "configMapRef" (dict "name" (printf "%s-config" (include "dify.name" .))) -}}
{{- $secret := dict "secretRef" (dict "name" (include "dify.secret" .)) -}}
{{- $sources := concat .Values.extraEnvFrom (list $config $secret) -}}
{{- if .Values.vectorStore.existingSecret -}}
{{- $sources = prepend $sources (dict "secretRef" (dict "name" .Values.vectorStore.existingSecret)) -}}
{{- end -}}
{{- dict "envFrom" $sources | toYaml -}}
{{- end -}}
{{- define "dify.broker" -}}
{{- $url := printf "redis://:$(REDIS_PASSWORD)@%s:%v/1" (ternary (printf "%s-redis" (include "dify.name" .)) .Values.redis.host (eq .Values.redis.mode "internal")) .Values.redis.port -}}
{{- $broker := list (dict "name" "CELERY_BROKER_URL" "value" $url) -}}
{{- $vector := include "dify.vectorCredentials" . | fromYamlArray -}}
{{- concat $broker $vector | toYaml -}}
{{- end -}}
{{- define "dify.claim" -}}
{{- default (printf "%s-storage" (include "dify.name" .)) .Values.persistence.existingClaim -}}
{{- end -}}
{{- define "dify.dbPort" -}}
{{- default (ternary 3306 5432 (eq .Values.database.type "mysql")) .Values.database.port -}}
{{- end -}}
{{- define "dify.dbUser" -}}
{{- default (ternary "root" "postgres" (eq .Values.database.type "mysql")) .Values.database.username -}}
{{- end -}}
{{- define "dify.volumeClaim" -}}
accessModes: [{{ .Values.persistence.accessMode | quote }}]
{{- if .Values.persistence.storageClass }}
storageClassName: {{ .Values.persistence.storageClass | quote }}
{{- end }}
{{ dict "resources" (dict "requests" (dict "storage" .Values.persistence.size)) | toYaml }}
{{- end -}}
{{- define "dify.labels" -}}
app.kubernetes.io/name: dify
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
{{- define "dify.secret" -}}
{{- default (printf "%s-secrets" (include "dify.name" .)) .Values.security.existingSecret -}}
{{- end -}}
{{- define "dify.url" -}}
{{- if eq .Values.exposure.type "Ingress" -}}
{{- printf "%s://%s" (ternary "https" "http" .Values.exposure.tls.enabled) .Values.exposure.host -}}
{{- else -}}
{{- trimSuffix "/" .Values.exposure.publicUrl -}}
{{- end -}}
{{- end -}}
{{- define "dify.pod" -}}
automountServiceAccountToken: false
{{- with .Values.imagePullSecrets }}
imagePullSecrets: {{ toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.nodeSelector }}
nodeSelector: {{ toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations: {{ toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity: {{ toYaml . | nindent 2 }}
{{- end }}
{{- end -}}