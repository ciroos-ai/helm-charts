{{/*
Expand the name of the chart.
*/}}
{{- define "ciroos.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "ciroos.fullname" -}}
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
{{- define "ciroos.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ciroos.labels" -}}
helm.sh/chart: {{ include "ciroos.chart" . }}
{{ include "ciroos.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ciroos.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ciroos.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Read-only RBAC rules granting sveltos-applier-manager visibility into every
resource it needs to deploy/update on a managed cluster (agents, RBAC
objects, CRDs), minus Secrets, for use when sveltosApplierManager.readAllResources
is disabled. sveltos-applier-manager must itself hold get/list/watch on
everything any ClusterRole/Role it installs (e.g. sveltos-agent-manager-role,
drift-detection-manager-role, beacon-clusterrole, eventrouter-controller-role)
grants for read, or Kubernetes' RBAC self-escalation check rejects the write —
keep this list a superset of those roles' read rules.
*/}}
{{- define "ciroos.sveltosApplierReadRules" -}}
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
  - nodes/stats
  - persistentvolumeclaims
  - persistentvolumeclaims/status
  - persistentvolumes
  - persistentvolumes/status
  - pods
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
  - apps
  - batch
  - extensions
  - networking.k8s.io
  - storage.k8s.io
  - rbac.authorization.k8s.io
  - discovery.k8s.io
  - apiextensions.k8s.io
  - cert-manager.io
  - projectcontour.io
  - events.k8s.io
  resources:
  - "*"
  verbs:
  - get
  - list
  - watch
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ciroos.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ciroos.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
