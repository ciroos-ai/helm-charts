{{/*
Expand the name of the chart.
*/}}
{{- define "ciroos-agents.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "ciroos-agents.fullname" -}}
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
{{- define "ciroos-agents.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ciroos-agents.labels" -}}
helm.sh/chart: {{ include "ciroos-agents.chart" . }}
{{ include "ciroos-agents.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ciroos-agents.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ciroos-agents.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ciroos-agents.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ciroos-agents.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Read-only RBAC rules granting beacon visibility into apps and batch workloads,
and every core resource except Secrets, for use when beacon.readAllResources is disabled.
*/}}
{{- define "ciroos-agents.beaconReadRules" -}}
- apiGroups:
  - apps
  resources:
  - '*'
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - batch
  resources:
  - '*'
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - bindings
  - componentstatuses
  - configmaps
  - endpoints
  - events
  - limitranges
  - namespaces
  - nodes
  - persistentvolumeclaims
  - persistentvolumeclaims/status
  - persistentvolumes
  - persistentvolumes/status
  - pods/log
  - pods/status
  - podtemplates
  - replicationcontrollers
  - replicationcontrollers/scale
  - replicationcontrollers/status
  - resourcequotas
  - resourcequotas/status
  - serviceaccounts
  - services
  - services/status
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - source.ciroos.ai
  resources:
  - workloadsources
  verbs:
  - get
  - list
  - watch
{{- end }}
