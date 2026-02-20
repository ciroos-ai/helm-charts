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
│ k8smcp                 │ Kubernetes Management Control Plane - cluster resource tracking │
├────────────────────────┼─────────────────────────────────────────────────────────────────┤
│ eventrouter-controller │ Routes and filters Kubernetes events based on rules             │
├────────────────────────┼─────────────────────────────────────────────────────────────────┤
│ beacon                 │ Agent heartbeat and cluster identity management                 │
├────────────────────────┼─────────────────────────────────────────────────────────────────┤
│ vector                 │ High-performance data pipeline for telemetry forwarding         │
└────────────────────────┴─────────────────────────────────────────────────────────────────┘

Optional Agents (can be disabled)
┌──────────────────────────────────────┬──────────────────────────────────────────────┬────────────────────────────────────────┐
│                Agent                 │                   Purpose                    │              Disable Flag              │
├──────────────────────────────────────┼──────────────────────────────────────────────┼────────────────────────────────────────┤
│ otelcollector                        │ OpenTelemetry metrics collection             │ otelcollector.enabled: false           │
├──────────────────────────────────────┼──────────────────────────────────────────────┼────────────────────────────────────────┤
│ ebpf-topo-coll                       │ eBPF network topology collection (DaemonSet) │ ebpfTopoColl.enabled: false            │
├──────────────────────────────────────┼──────────────────────────────────────────────┼────────────────────────────────────────┤
│ source-repository-watcher-controller │ GitOps state monitoring (ArgoCD/Flux)        │ sourceRepositoryWatcher.enabled: false │
└──────────────────────────────────────┴──────────────────────────────────────────────┴────────────────────────────────────────┘

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

sourceRepositoryWatcher:
  enabled: false
