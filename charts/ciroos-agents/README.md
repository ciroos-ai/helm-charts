# Ciroos Agent Helm Chart

This Helm chart deploys the Ciroos agent suite into a managed Kubernetes cluster, enabling comprehensive observability, monitoring, and GitOps tracking.

## Prerequisites

**Before installation**, you must register your cluster with Ciroos to obtain the required credentials and configuration values:

```yaml
# Required values from Ciroos cluster registration
clusterNamespace: "your-cluster-namespace"  # Project/organization namespace
clusterName: "your-cluster-name"            # Unique cluster identifier
ingressFqdn: "api.ciroos.example.com"       # Ciroos platform ingress FQDN
ciroosIngressUrl: "https://api.ciroos.example.com"  # Full platform URL
ciroosDockerconfigjson: "base64-encoded-dockerconfig"  # Registry credentials
ciroosCaCrt: "base64-encoded-ca-cert"       # Platform CA certificate
ciroosTlsCrt: "base64-encoded-tls-cert"     # Client TLS certificate
ciroosTlsKey: "base64-encoded-tls-key"      # Client TLS private key

To register your cluster and obtain these values:
1. Log in to the Ciroos platform
2. Navigate to Cluster Management
3. Click "Register New Cluster"
4. Download the generated values.yaml file

Components

Mandatory Agents (always deployed)
┌────────────────────────┬─────────────────────────────────────────────────────────────────┐
│         Agent          │                             Purpose                             │
├────────────────────────┼─────────────────────────────────────────────────────────────────┤
│ eventrouter-controller │ Routes and filters Kubernetes events based on rules             │
├────────────────────────┼─────────────────────────────────────────────────────────────────┤
│ beacon                 │ Agent heartbeat and cluster identity management                 │
├────────────────────────┼─────────────────────────────────────────────────────────────────┤
│ vector                 │ High-performance data pipeline for telemetry forwarding         │
├────────────────────────┼─────────────────────────────────────────────────────────────────┤
│ insight                │ Detect unused resources                                         │
└────────────────────────┴─────────────────────────────────────────────────────────────────┘

Optional Agents (can be disabled)
┌──────────────────────────────────────┬──────────────────────────────────────────────┬──────────────────────────────────────────────────┐
│                Agent                 │                   Purpose                    │              Disable Flag                        │
├──────────────────────────────────────┼──────────────────────────────────────────────┼──────────────────────────────────────────────────┤
│ otelcollector                        │ OpenTelemetry metrics collection             │ otelcollector.enabled: false                     │
├──────────────────────────────────────┼──────────────────────────────────────────────┼──────────────────────────────────────────────────┤
│ ebpf-topo-coll                       │ eBPF network topology collection (DaemonSet) │ ebpfTopoColl.enabled: false                      │
├──────────────────────────────────────┼──────────────────────────────────────────────┼──────────────────────────────────────────────────┤
│ source-repository-watcher-controller │ GitOps state monitoring (ArgoCD/Flux)        │ sourceRepositoryWatcherController.enabled: false │
└──────────────────────────────────────┴──────────────────────────────────────────────┴──────────────────────────────────────────────────┘

RBAC Hardening

By default, beacon is granted `get/list/watch` on every resource in the cluster (`apiGroups: ['*'], resources: ['*']`), which implicitly includes cluster-wide read access to Secrets. If your security posture does not allow this, set:

# values.yaml
beacon:
  readAllResources: false

Disabling this flag removes the wildcard rule entirely, so beacon can no longer read Secrets (or any resource type) cluster-wide. Beacon retains `get/list/watch` on pods only. Any beacon feature that relies on reading other resource types (e.g. Deployments, Nodes, NetworkPolicies) will lose visibility into those resources when this flag is disabled. **It is then the user's responsibility to grant beacon whichever additional RBAC it needs to run investigations** — the chart will not do this for you once the wildcard is turned off.

### Example: granting beacon investigation permissions manually

Beacon's investigation tooling (resource description, workload inspection, best-practices auditing) reads a range of resource types beyond pods — Deployments, Services, ConfigMaps, Nodes, NetworkPolicies, RBAC objects, and more. It also has a `secrets` "describe" capability, which is deliberately **excluded** from the example below — if you're disabling `readAllResources` specifically to keep beacon away from Secrets, don't add `secrets` back into this grant.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: beacon-investigation
rules:
- apiGroups: [""]
  resources: ["services", "endpoints", "configmaps", "persistentvolumeclaims", "persistentvolumes", "nodes", "serviceaccounts"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "daemonsets", "statefulsets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["batch"]
  resources: ["jobs", "cronjobs"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["autoscaling"]
  resources: ["horizontalpodautoscalers"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses", "ingressclasses", "networkpolicies"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["policy"]
  resources: ["poddisruptionbudgets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["storageclasses"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["admissionregistration.k8s.io"]
  resources: ["validatingwebhookconfigurations", "mutatingwebhookconfigurations"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: beacon-investigation
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: beacon-investigation
subjects:
- kind: ServiceAccount
  name: beacon-sa
  namespace: ciroos-agent  # the namespace you installed this chart into
```

Trim the resource list above to whatever your investigations actually need — none of it is required by beacon to start up or send heartbeats; it only affects what beacon can describe/inspect during an investigation.

beacon also creates and deletes Pods by default (for diagnostics). To remove that permission as well:

beacon:
  managePods: false

Disabling `sourceRepositoryWatcherController` (see table above) also removes its own direct, cluster-wide `get/list/watch` on Secrets.

Installation

# Install with values obtained from cluster registration
helm install ciroos-agent ciroos/ciroos-agents \
  --namespace ciroos-agent \
  --create-namespace \
  -f values.yaml

# Or install with inline values
helm install ciroos-agent ciroos/ciroos-agents \
  --namespace ciroos-agent \
  --create-namespace \
  --set global.clusterName=my-cluster \
  --set global.clusterNamespace=production \
  --set ingressFqdn=api.ciroos.example.com

Disable Optional Components

# values.yaml
otelcollector:
  enabled: false

ebpfTopoColl:
  enabled: false

sourceRepositoryWatcherController:
  enabled: false
