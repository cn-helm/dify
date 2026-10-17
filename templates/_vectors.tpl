{{- define "dify.vectorConfig" -}}
{{- $host := printf "%s-vector" (include "dify.name" .) -}}
{{- $config := dict -}}
{{- if eq .Values.vectorStore.mode "internal" -}}
{{- if eq .Values.vectorStore.type "qdrant" -}}
{{- $config = dict "QDRANT_URL" (printf "http://%s:6333" $host) "QDRANT_GRPC_ENABLED" "false" -}}
{{- else if eq .Values.vectorStore.type "pgvector" -}}
{{- $config = dict "PGVECTOR_HOST" $host "PGVECTOR_PORT" "5432" "PGVECTOR_USER" "postgres" "PGVECTOR_DATABASE" "dify" -}}
{{- else if eq .Values.vectorStore.type "pgvecto-rs" -}}
{{- $config = dict "PGVECTO_RS_HOST" $host "PGVECTO_RS_PORT" "5432" "PGVECTO_RS_USER" "postgres" "PGVECTO_RS_DATABASE" "dify" -}}
{{- else if eq .Values.vectorStore.type "chroma" -}}
{{- $config = dict "CHROMA_HOST" $host "CHROMA_PORT" "8000" "CHROMA_TENANT" "default_tenant" "CHROMA_DATABASE" "default_database" "CHROMA_AUTH_PROVIDER" "chromadb.auth.token_authn.TokenAuthClientProvider" -}}
{{- else if eq .Values.vectorStore.type "elasticsearch" -}}
{{- $config = dict "ELASTICSEARCH_HOST" $host "ELASTICSEARCH_PORT" "9200" "ELASTICSEARCH_USERNAME" "elastic" "ELASTICSEARCH_VERIFY_CERTS" "false" -}}
{{- else if eq .Values.vectorStore.type "opensearch" -}}
{{- $config = dict "OPENSEARCH_HOST" $host "OPENSEARCH_PORT" "9200" "OPENSEARCH_USER" "admin" "OPENSEARCH_SECURE" "true" "OPENSEARCH_VERIFY_CERTS" "false" "OPENSEARCH_AUTH_METHOD" "basic" -}}
{{- end -}}
{{- end -}}
{{- range $key, $value := .Values.vectorStore.config -}}
{{- $_ := set $config $key ($value | toString) -}}
{{- end -}}
{{- $config | toYaml -}}
{{- end -}}
{{- define "dify.vectorCredentials" -}}
{{- $keys := dict "qdrant" "QDRANT_API_KEY" "pgvector" "PGVECTOR_PASSWORD" "pgvecto-rs" "PGVECTO_RS_PASSWORD" "chroma" "CHROMA_AUTH_CREDENTIALS" "elasticsearch" "ELASTICSEARCH_PASSWORD" "opensearch" "OPENSEARCH_PASSWORD" -}}
{{- if and (eq .Values.vectorStore.mode "internal") (hasKey $keys .Values.vectorStore.type) -}}
{{- $reference := dict "name" (include "dify.secret" .) "key" "VECTOR_STORE_PASSWORD" -}}
{{- list (dict "name" (get $keys .Values.vectorStore.type) "valueFrom" (dict "secretKeyRef" $reference)) | toYaml -}}
{{- end -}}
{{- end -}}