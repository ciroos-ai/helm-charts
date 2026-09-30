# ciroos Helm Chart

Connects a Kubernetes cluster to Ciroos by installing the Sveltos applier together with a pre-generated, cluster-specific
configuration. Once installed, the cluster is a **managed cluster**: Ciroos deploys and upgrades its agents on it
(beacon, eventrouter, insight-controller, ...) through the applier, so you never install those yourself.

This chart is the Helm equivalent of **Method 1: Single Cluster Registration (YAML Manifest)**. For self-service
registration with reusable project-level credentials, see the `installer` chart instead.

## What it deploys

| Resource | Purpose |
|---|---|
| `sveltos-applier-manager` Deployment (namespace `projectsveltos`) | Runs in pull mode: connects **outbound** to the Ciroos control cluster and applies the resources Ciroos has selected for this cluster. The control cluster never needs inbound access to yours. |
| `pullmode-secret` Secret | Kubeconfig the applier uses to reach the Ciroos control cluster. |
| RBAC for the applier | What the applier may read and write locally (see [Restricted RBAC](#restricted-rbac)). |
| `ciroos-agent` Namespace | Where the Ciroos agents are deployed. |
| Uninstaller Job | Runs on `helm delete` and removes what Ciroos deployed to the cluster. |

## Prerequisites

Register the cluster with Ciroos first. Ciroos generates the values for this chart; each chart/values pair registers
exactly one cluster:

```yaml
clusterNamespace: <cluster namespace>
clusterName: <cluster name>
pullmodeSecret:
  kubeconfig: <base64 encoded kubeconfig for sveltos applier to connect to Ciroos control cluster>
```

## Install

```
helm repo add ciroos https://ciroos-ai.github.io/helm-charts
helm repo update
helm install ciroos ciroos/ciroos --create-namespace -n projectsveltos -f /tmp/values.yaml
```

## Scheduling and metadata

`annotations`, `labels`, `tolerations` and `nodeSelector` can be set on the applier Deployment and on the uninstaller Job:

```yaml
sveltosApplierManager:
  annotations:
    foo1: bar1
  labels:
    bar1: foo1
  tolerations:
  - key: dedicated
    value: system
    effect: NoSchedule
  nodeSelector:
    dedicated: workload
uninstaller:
  annotations:
    fooA: barA
  labels:
    barA: fooA
  tolerations:
  - key: dedicated
    value: system
    effect: NoSchedule
  nodeSelector:
    dedicated: workload
```

## Restricted RBAC

By default the applier can `get/list/watch` every resource in the cluster (`apiGroups: ['*'], resources: ['*']`),
which includes **Secrets in every namespace**. Organizations whose security policy doesn't allow that can enable
**restricted RBAC**.

### What it is

Restricted RBAC has two parts that work together. One is an **organization policy** in Ciroos, the other is a **Helm
value** in this chart:

| Setting | Where it is set | What it controls |
|---|---|---|
| `restricted_rbac: true` | Ciroos, at the organization level | What **Ciroos deploys** to your clusters: `beacon` gets curated read permissions and `source-repository-watcher-controller` is not deployed. |
| `sveltosApplierManager.readAllResources: false` | This chart's values | The **applier's own permissions**, installed by this chart: curated read access that excludes Secrets, and no `create`/`delete` on pods. |

**The Helm value can only be set when the organization has the `restricted_rbac: true` policy.** The chart can't turn
the policy on; it only narrows the applier. Without the policy, Ciroos still deploys beacon with cluster-wide
`get/list/watch` on `*/*`, and the narrowed applier can't grant it (see [Enabling it](#enabling-it)).

| Organization policy | `readAllResources` | Result |
|---|---|---|
| `restricted_rbac: true` | `false` | Fully restricted. This is the supported way to enable restricted RBAC. |
| `restricted_rbac: true` | `true` (default) | Works, but the applier can still read every Secret in the cluster. |
| not set | `true` (default) | Default behavior, nothing is restricted. |
| not set | `false` | **Breaks.** The beacon deployment fails. |

When both are on:

- The applier's cluster-wide read access (`sveltos-applier-manager-read-permission`) is limited to a fixed list of
  resources that **excludes Secrets** (`ciroos.sveltosApplierReadRules` in `templates/_helpers.tpl`).
- The applier has no `create`/`delete` on `pods`.
- `beacon` is deployed with the same kind of curated, Secret-free read permissions (`get/list/watch`) and no
  `create`/`delete` on pods, instead of `*/*`.
- `source-repository-watcher-controller` is **not deployed**. It needs cluster-wide access to Secrets (plus Argo CD and
  Flux source resources), which can't be granted under restricted RBAC.

Everything else Ciroos deploys keeps working; only the components above change.

The applier is also the actor that installs beacon's RBAC on the cluster, so Kubernetes' RBAC self-escalation check
requires it to hold at least whatever it grants beacon. Beacon's own read permissions are configured in the
[`ciroos-agents` chart](../ciroos-agents/README.md) (`beacon.readAllResources`). If you change them, keep the applier's
curated list a superset.

### Enabling it

1. Make sure your Ciroos organization has the `restricted_rbac: true` policy.
2. Set the Helm value when you install or upgrade this chart:

```yaml
sveltosApplierManager:
  readAllResources: false
```

> **Don't set `readAllResources: false` on its own.** Without the organization policy, the applier starts with limited
> permissions while `beacon` is still deployed with cluster-wide `get/list/watch` on `*/*`. Kubernetes' RBAC
> self-escalation check then rejects the applier's attempt to grant beacon permissions it doesn't hold, and the
> beacon deployment fails.

### What the applier can and can't do

With `readAllResources: false`:

- It can **not** read Secrets outside its own two namespaces, `projectsveltos` and `ciroos-agent`, where it has full
  access to manage what it deploys.
- It can **not** grant permissions it doesn't hold itself. It can create ClusterRoles and ClusterRoleBindings, but
  Kubernetes rejects any that exceed its own permissions. It has no `escalate`, `bind` or `impersonate` verbs.

### Extra permissions

If the curated list doesn't cover a resource you need (for example a CRD), add it with `extraClusterRoleRules`
instead of turning `readAllResources` back on:

```yaml
extraClusterRoleRules:
- apiGroups:
  - snapshot.storage.k8s.io
  resources:
  - volumesnapshots
  - volumesnapshotcontents
  verbs:
  - get
  - list
  - watch
```

The rules are granted, through `ciroos-extra-permission` and `ciroos-extra-binding`, to both the applier (it installs
beacon's RBAC, so it must hold at least what it grants) and `beacon-sa`. Never add `secrets` here if the goal is to
keep them out of reach. Check what was granted with `kubectl get clusterrolebinding ciroos-extra-binding -o yaml`.

## Uninstall

```
helm uninstall ciroos -n projectsveltos
```

The uninstaller Job removes the resources Ciroos deployed to the cluster.
