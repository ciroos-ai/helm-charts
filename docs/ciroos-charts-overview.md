# Ciroos Helm charts: architecture, choosing a chart, and RBAC

This document explains how a Kubernetes cluster connects to Ciroos, which of the Helm charts in this repository to
install, and exactly what permissions Ciroos holds in each case, including how to restrict them.

- [1. Concepts: control cluster and managed clusters](#1-concepts-control-cluster-and-managed-clusters)
- [2. How the Sveltos applier connects back to the control cluster](#2-how-the-sveltos-applier-connects-back-to-the-control-cluster)
- [3. The charts and when to use each](#3-the-charts-and-when-to-use-each)
- [4. Permissions in a managed cluster (`ciroos` chart)](#4-permissions-in-a-managed-cluster-ciroos-chart)
- [5. Permissions in an unmanaged cluster (`ciroos-agents` chart)](#5-permissions-in-an-unmanaged-cluster-ciroos-agents-chart)
- [6. Configuring restricted RBAC](#6-configuring-restricted-rbac)
- [7. Verifying what was granted](#7-verifying-what-was-granted)
- [8. What Ciroos cannot do](#8-what-ciroos-cannot-do)
- [9. Network requirements](#9-network-requirements)
- [10. Uninstalling](#10-uninstalling)

---

## 1. Concepts: control cluster and managed clusters

**Ciroos control cluster.** A Kubernetes cluster operated by Ciroos. It runs the Ciroos platform and the
[Sveltos](https://projectsveltos.io) control plane. It holds, for every cluster you register, a description of *what
should run there* (the agents, their configuration, their RBAC) and a per-cluster identity used to deliver it. You never
install anything on the control cluster.

**Managed cluster.** Any cluster you want Ciroos to observe and investigate: your production, staging or
development clusters. The Helm charts in this repository are installed on managed clusters. "Managed" here only means
"registered with Ciroos", not that Ciroos runs your cluster.

```
        Ciroos control cluster                          Your cluster (managed cluster)
 ┌─────────────────────────────────────┐          ┌─────────────────────────────────────────┐
 │ Sveltos control plane               │          │ ns projectsveltos                       │
 │  - SveltosCluster (pull mode)       │  HTTPS   │   sveltos-applier-manager  ──┐          │
 │  - ConfigurationGroups / Bundles    │ <─────── │   (+ sveltos agents)         │ applies  │
 │    = what to deploy to this cluster │ outbound │                              ▼          │
 │ Ciroos platform (ingress, backend)  │  only    │ ns ciroos-agent                         │
 └─────────────────────────────────────┘          │   beacon, eventrouter, insight, vector… │
                                                  └─────────────────────────────────────────┘
```

Two kinds of traffic flow, and both are always initiated from your cluster:

1. **Configuration:** the Sveltos applier *pulls* the desired state from the control cluster (section 2).
2. **Telemetry:** the agents *push* events, resource metadata and heartbeats to the Ciroos platform ingress.

The control cluster never needs network access *into* your cluster.

---

## 2. How the Sveltos applier connects back to the control cluster

Managed clusters use Sveltos **pull mode**. Instead of the control cluster holding credentials to your API server, your
cluster holds a (narrow) credential for the control cluster's API server and polls it.

### Registration

Registering a cluster (namespace `<ns>`, name `<name>`) makes Ciroos' onboarding controller create, **on the control
cluster**:

| Object | Purpose |
|---|---|
| Namespace `<ns>` | Holds everything for this registration. Created if missing. |
| ServiceAccount `<name>` | The cluster's identity. This is the only identity the applier on your cluster uses. |
| Token for that ServiceAccount | Embedded in the kubeconfig you receive. Either a long-lived token Secret (default) or a short-lived token renewed automatically (see below). |
| Role `<name>` + RoleBinding in `<ns>` | What the identity may do in its namespace (table below). |
| ClusterRole `<ns>-<name>` + ClusterRoleBinding | Read-only access to three cluster-scoped Sveltos kinds. |
| `SveltosCluster` `<name>` (pull mode) | Represents your cluster to Sveltos, with liveness checks. |

The onboarding controller then returns a kubeconfig (user `sveltos-applier`) pointing at the control cluster API server.
That kubeconfig is what you pass to the `ciroos` chart as `pullmodeSecret.kubeconfig`, where it becomes the
`pullmode-secret` Secret mounted by the applier (`--secret-with-kubeconfig=pullmode-secret`).

### What the per-cluster identity can do on the control cluster

The identity can only talk to Sveltos' own configuration objects. It has **no access to Secrets, workloads or any
non-Sveltos resource** on the control cluster.

In namespace `<ns>` (Role `<name>`):

| API group | Resources | Verbs |
|---|---|---|
| `lib.projectsveltos.io` | `configurationgroups` | get, list, watch, update |
| `lib.projectsveltos.io` | `configurationbundles`, `sveltosclusters` | get, list, watch |
| `lib.projectsveltos.io` | `resourcesummaries` | get, list, create, watch |
| `lib.projectsveltos.io` | `classifierreports`, `eventreports`, `healthcheckreports`, `reloaderreports` | create, get, list, update, watch |
| `lib.projectsveltos.io` | `*/status` of the above (where applicable) | get, update (patch for report statuses) |
| `config.projectsveltos.io` | `clusterconfigurations`, `clustersummaries` | get, list, update, watch |
| `config.projectsveltos.io` | `clusterreports` | create, delete, get, list, update, watch |

Cluster-wide (ClusterRole `<ns>-<name>`): `get/list/watch` on `classifiers`, `eventsources` and `healthchecks`
(`lib.projectsveltos.io`).

In short: the applier can read what it has been told to deploy and write back reports about what it did. It cannot
read or change anything else.

> The Role is scoped to the namespace the cluster was registered in (`clusterNamespace`). Registrations that share a
> namespace share that scope.

### Token lifetime

| Mode | How | Trade-off |
|---|---|---|
| Default | Long-lived ServiceAccount token Secret. | Simple. The token stays valid until the registration is deleted or the Secret is rotated. |
| Short-lived (`renew_token: true` organization policy) | A 24-hour token. Sveltos' `sc-manager` on the control cluster re-issues it every hour through the TokenRequest API and pushes the new kubeconfig to your cluster. | A leaked kubeconfig expires within a day. `sc-manager` may only mint tokens for **this cluster's** ServiceAccount (`serviceaccounts/token`, `create`, restricted by `resourceNames`). |

**Token renewal is an organization policy, not a chart setting.** It is controlled by the `renew_token` policy on your
Ciroos organization (default `false`). When a cluster is registered, Ciroos reads the policy and decides which kind of
token goes into the kubeconfig. The `ciroos` and `installer` charts have no value for it, because the token is already
baked into the kubeconfig (`pullmodeSecret.kubeconfig`) that Ciroos generates. To use short-lived tokens, ask Ciroos to
enable `renew_token` for your organization and then register the cluster, or re-register an existing one, to get a
kubeconfig that carries a renewable token. Changing the policy doesn't change the token of a cluster that is already
registered.

### What the applier does with this access

1. Watches the control cluster for what Ciroos selected for this cluster.
2. Applies those resources to **your** cluster using its own local ServiceAccount (`sveltos-applier-manager`) and the
   local RBAC described in section 4.
3. Reports success or failure back through `ClusterReports` and `ClusterSummaries`.

Because step 2 uses local RBAC, **what Ciroos can do in your cluster is bounded by the permissions the `ciroos` chart
gives that ServiceAccount**, not by anything on the control cluster. That is what sections 4 and 6 are about.

---

## 3. The charts and when to use each

| Chart | What it installs | Who deploys the agents | Updates |
|---|---|---|---|
| `ciroos` | Sveltos applier, `pullmode-secret`, the applier's RBAC, `ciroos-agent` namespace, uninstaller Job. | **Ciroos**, through the applier. | Ciroos pushes them. No `helm upgrade` needed. |
| `installer` | A bootstrap Job that registers the cluster and then installs the same applier. Reusable, project-level values. | **Ciroos**, through the applier. | Same as `ciroos`. |
| `ciroos-agents` | The agents themselves (beacon, eventrouter, vector, insight, ...) and their RBAC, directly. No applier. | **You**, with Helm. | You run `helm upgrade`. |

`ciroos` and `installer` are two ways to reach the same end state. The only difference is how the cluster is
registered: `ciroos` uses values generated per cluster, `installer` uses reusable project-level credentials and you
supply the cluster name.

### Recommendation: use a managed install (`ciroos` or `installer`)

Choose managed unless a requirement rules it out.

- **Updates ship without customer action.** Fixes, new detectors, new RBAC for new features, and security patches are
  pushed by Ciroos. With `ciroos-agents`, every one of those waits for you to run `helm upgrade`, and clusters drift
  apart across versions.
- **Fewer moving parts for you.** One small component (the applier) on your side instead of the full agent suite.
- **Consistent behavior.** Every cluster runs a version Ciroos has tested together.

The cost is trust. The applier can create and update resources in your cluster, within the limits in section 4. Those
limits can be tightened (section 6), at the price of a smaller feature set.

### When to use `ciroos-agents` (unmanaged)

- You cannot allow any component that applies resources on behalf of an external party. A change-control process must
  approve every deployed manifest.
- The cluster cannot reach the control cluster API server (the managed model needs outbound HTTPS to it), but it can
  reach the Ciroos platform ingress.
- You want to pin and review the exact agent versions and RBAC and upgrade on your own schedule.

Trade-offs: you own upgrades and RBAC extensions, and new Ciroos capabilities that need extra permissions or new CRDs
reach you only when you upgrade.

### Decision summary

| Situation | Chart |
|---|---|
| Default, and we want automatic updates | `ciroos` (or `installer` for self-service registration across many clusters) |
| Managed, but the security policy forbids reading Secrets cluster-wide | `ciroos` + restricted RBAC (section 6) |
| No component may apply resources on its own | `ciroos-agents` |
| Cluster can't reach the control cluster API server | `ciroos-agents` |

---

## 4. Permissions in a managed cluster (`ciroos` chart)

There are two layers: the **applier's own permissions** (from the `ciroos` chart) and the **permissions of the agents
the applier deploys** (see [section 5](#5-permissions-in-an-unmanaged-cluster-ciroos-agents-chart), the agent RBAC is the
same in both modes).

### The applier (`sveltos-applier-manager`, namespace `projectsveltos`)

| Grant | Scope | Details |
|---|---|---|
| Read | Cluster-wide | `get/list/watch` on `*/*` by default. **Includes Secrets in every namespace.** With `readAllResources: false`, a curated list that excludes Secrets (section 6). |
| Full control | Namespaces `projectsveltos` and `ciroos-agent` only | `*` on `*`. This is where it deploys what Ciroos selects. It includes Secrets, but only in these two namespaces. |
| Sveltos and Ciroos CRDs | Cluster-wide | `*` on `lib.projectsveltos.io`, `config.projectsveltos.io` and `lib.ciroos.ai`, and `*` on `customresourcedefinitions`. |
| Cluster RBAC | Cluster-wide | create/get/list/update/patch/delete/watch on `clusterroles` and `clusterrolebindings`. It needs this to install the agents' RBAC. |
| ConfigMaps | Cluster-wide | create/get/list/update/watch/patch. |
| Events | Cluster-wide | create/patch/update. |
| Namespaces | Cluster-wide | patch/update (labels and annotations). |
| Pods | Cluster-wide | create/delete, **only** when `readAllResources: true`. Beacon needs this for diagnostics. Removed under restricted RBAC. |

It has **no** `escalate`, `bind` or `impersonate` verbs. Kubernetes therefore refuses any ClusterRole or binding the
applier creates that grants more than the applier itself holds. This is what makes restricted RBAC enforceable: the
applier can't give an agent Secret access it doesn't have.

### The agents it deploys

Ciroos deploys the same agents as the `ciroos-agents` chart, with the same RBAC. The permission-relevant ones:

| Agent | Cluster-wide access | Namespace-local access (`ciroos-agent`) |
|---|---|---|
| `beacon` | Pods get/list/watch (+ create/delete); **`*/*` get/list/watch by default** (curated under restricted RBAC) | Small Role: pods, pods/status, deployments get, events create |
| `eventrouter-controller` | Read on events, core resources, workloads, CronJobs, cert-manager and Contour kinds; list/watch on CRDs; manages `lib.ciroos.ai` CRs | **`secrets` get** (one Role) |
| `insight-controller` | Read on endpoints, namespaces, nodes, PVCs/PVs, pods, resource quotas, services, endpoint slices, ingresses, jobs, HPAs; events create/patch/update | **`secrets` get** (one Role) |
| `vector` | namespaces, nodes, pods, events: get/list/watch | none |
| `otelcollector` (optional) | pods, namespaces, nodes, `nodes/stats`, workloads read | none |
| `ebpf-topo-reducer` (optional) | pods, nodes, namespaces, services, workloads, jobs read | none |
| `source-repository-watcher-controller` (optional) | **`secrets` get/list/watch**, Argo CD `applications`, Flux `helmreleases`/`kustomizations`/`gitrepositories`, CRDs, deployments | `secrets` create/delete/get/list/update/watch |

Only three things can read Secrets beyond a single namespace, and all of them can be turned off:
the applier's default read rule, beacon's default `*/*` rule, and the source repository watcher. Everything else
reads Secrets only inside `ciroos-agent`, if at all.

---

## 5. Permissions in an unmanaged cluster (`ciroos-agents` chart)

With `ciroos-agents` there is **no applier and no control-cluster credential**. The chart creates:

- the agent Deployments and their ServiceAccounts, with the RBAC in the table above;
- the Ciroos CRDs (`Alert`, `ResourceWatcher`, `AgentHealth`, `WorkloadSource`, ...);
- a Secret with the client certificate and CA the agents use to authenticate to the Ciroos platform
  (`ciroosCaCrt`, `ciroosTlsCrt`, `ciroosTlsKey`) and an image-pull secret.

The agents connect **outbound only**, using that client certificate, to `ingressFqdn` (WebSocket and HTTPS sinks).

What changes compared with managed:

| | Managed (`ciroos`) | Unmanaged (`ciroos-agents`) |
|---|---|---|
| Component that applies resources in your cluster | Applier (with the permissions in section 4) | None. Only Helm, run by you. |
| Can Ciroos add or change deployed workloads or RBAC? | Yes, within the applier's permissions | No. Only through your `helm upgrade`. |
| Control-cluster credential in your cluster | Yes (`pullmode-secret`) | No |
| Agent RBAC | Chosen by Ciroos (curated when the org has `restricted_rbac`) | Chosen by **you**, with chart values |
| `namespaceScoped` option | Not applicable | `namespaceScoped: true` replaces ClusterRoles with namespaced Roles |

Because there is no applier to protect against escalation, the chart values are the only control. Section 6 covers
them.

> If you restrict beacon in an unmanaged install, **you** are responsible for granting whatever it needs. The chart
> will not widen permissions once the wildcard is off.

---

## 6. Configuring restricted RBAC

Goal: Ciroos can observe your cluster **without being able to read Secrets cluster-wide**.

What you give up: beacon loses visibility into resource types you don't grant, which affects investigations, and the
source repository watcher (Argo CD / Flux tracking) is unavailable, because it structurally needs cluster-wide Secret
access.

### 6.1 Managed cluster (`ciroos` chart)

Restricted RBAC has two parts that work together.

| Setting | Where | Effect |
|---|---|---|
| `restricted_rbac: true` | Ciroos, organization policy (ask Ciroos to enable it) | Ciroos deploys `beacon` with curated, Secret-free read rules and skips `source-repository-watcher-controller`. |
| `sveltosApplierManager.readAllResources: false` | `ciroos` chart values | The applier's own read permission becomes a curated list without Secrets, it loses `create`/`delete` on pods, and it only watches `ciroos-agent` and `projectsveltos`. |

**`readAllResources: false` can only be set when your organization already has the `restricted_rbac: true` policy.**
The chart can't turn the policy on. It only narrows the applier. Enable the policy first (ask Ciroos), then set the
Helm value. Setting the value without the policy breaks the beacon deployment (see the last row below).

**Why:** the two settings control different actors, and they have to agree. The Helm value sets the permissions the
applier starts with. The org policy decides what Ciroos then asks the applier to deploy. Without the policy, Ciroos
still deploys beacon with its default cluster-wide read rule (`get/list/watch` on `*/*`). The applier is installing
that ClusterRole, and Kubernetes only lets a subject create a role that grants permissions it holds itself (the RBAC
escalation check). A narrowed applier doesn't hold cluster-wide read, so the API server rejects the request with a
permission-denied error and beacon never gets deployed. With the policy on, Ciroos deploys beacon with the curated,
Secret-free rules, which the narrowed applier does hold, so the request succeeds.

| Organization policy | `readAllResources` | Result |
|---|---|---|
| `restricted_rbac: true` | `false` | Fully restricted. This is the supported configuration. |
| `restricted_rbac: true` | `true` (default) | Works, but the applier can still read every Secret. |
| not set | `true` (default) | Default behavior. Nothing is restricted. |
| not set | `false` | **Breaks.** Beacon is still deployed with `*/*` read, which the narrowed applier can't grant (the escalation check rejects it), so the beacon deployment fails. |

Install (only after confirming the organization has `restricted_rbac: true`):

```yaml
# values.yaml, merged with the generated clusterNamespace / clusterName / pullmodeSecret
sveltosApplierManager:
  readAllResources: false
```

```sh
helm upgrade --install ciroos ciroos/ciroos -n projectsveltos --create-namespace -f values.yaml
```

After this, the applier can read everything in the curated list (core resources other than Secrets, plus the
non-Secret API groups `apps`, `batch`, `networking.k8s.io`, `storage.k8s.io`, `rbac.authorization.k8s.io`,
`discovery.k8s.io`, `apiextensions.k8s.io`, `autoscaling`, `cert-manager.io`, `projectcontour.io` and
`events.k8s.io`) and cannot read Secrets outside `projectsveltos` and `ciroos-agent`.

**Granting extra read access.** If you need Ciroos to see a CRD the curated list doesn't cover, add it with
`extraClusterRoleRules` instead of turning `readAllResources` back on:

```yaml
extraClusterRoleRules:
- apiGroups: ["snapshot.storage.k8s.io"]
  resources: ["volumesnapshots", "volumesnapshotcontents"]
  verbs: ["get", "list", "watch"]
```

The rules are bound to both the applier and `beacon-sa`. The applier needs them too, because it installs beacon's RBAC
and must hold at least what it grants. **Never add `secrets` here** if the goal is to keep them unreachable.

**Keep the lists in sync.** The applier's curated list must stay a superset of what the agents it installs are granted,
or the escalation check rejects the agent's RBAC. The list lives in `ciroos.sveltosApplierReadRules`
(`charts/ciroos/templates/_helpers.tpl`).

### 6.2 Unmanaged cluster (`ciroos-agents` chart)

```yaml
# values.yaml
beacon:
  readAllResources: false     # drop beacon's */* read rule; curated, Secret-free reads instead
  managePods: false           # optional: remove create/delete on pods
sourceRepositoryWatcherController:
  enabled: false              # needs cluster-wide Secret read, so disable it as well
```

- `beacon.readAllResources: false` replaces the wildcard with a curated list: core resources (no Secrets),
  `apps`, `batch`, `extensions`, `networking.k8s.io`, `storage.k8s.io`, `rbac.authorization.k8s.io`,
  `apiextensions.k8s.io`, and `source.ciroos.ai/workloadsources`.
- Disabling the source repository watcher also removes its direct, cluster-wide Secret read. Leaving it enabled either
  defeats the restriction or fails the install.
- To grant more, use `extraClusterRoleRules` (creates `beacon-extra-permission` and `beacon-extra-binding` for
  `beacon-sa`). It is always cluster-wide.
- `namespaceScoped: true` replaces ClusterRoles with namespaced Roles, for installs that must not have any cluster-wide
  grants. Agents then only see the namespace they run in.

### 6.3 Secrets that remain reachable even when restricted

Restricted RBAC removes **cluster-wide** Secret access. These namespace-local Secret grants remain, in the namespace
the agents are installed in (`ciroos-agent`):

| Component | Access |
|---|---|
| `sveltos-applier-manager` (managed only) | Full access in `projectsveltos` and `ciroos-agent`, because it deploys there. |
| `eventrouter-controller`, `insight-controller` | `get` on Secrets in `ciroos-agent` (credentials for notification and integration targets that you configure). |
| `nexus-agent` (disabled by default) | get/list/watch/update/patch in `ciroos-agent`. |

Keep other workloads' Secrets out of the `ciroos-agent` and `projectsveltos` namespaces.

---

## 7. Verifying what was granted

Review what Ciroos holds before and after you change a value:

```sh
# Applier
kubectl get clusterrole sveltos-applier-manager-read-permission -o yaml
kubectl get clusterrole sveltos-applier-manager-other-roles -o yaml
kubectl get clusterrole ciroos-extra-permission -o yaml
kubectl get clusterrolebinding ciroos-extra-binding -o yaml

# Beacon
kubectl get clusterrole beacon-clusterrole -o yaml
```

Test Secret access directly:

```sh
kubectl auth can-i list secrets --all-namespaces \
  --as=system:serviceaccount:projectsveltos:sveltos-applier-manager
kubectl auth can-i list secrets --all-namespaces \
  --as=system:serviceaccount:ciroos-agent:beacon-sa
kubectl auth can-i get secrets -n kube-system \
  --as=system:serviceaccount:ciroos-agent:beacon-sa
```

With restricted RBAC, all three should answer `no`. Expect `yes` for the applier in its own two namespaces:

```sh
kubectl auth can-i get secrets -n ciroos-agent \
  --as=system:serviceaccount:projectsveltos:sveltos-applier-manager
```

To list everything a service account can do: `kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa>`.

---

## 8. What Ciroos cannot do

A summary of the limits described above, for security reviews.

**In every configuration**

- **No inbound access.** Ciroos never connects to your API server. In a managed install your cluster connects out to
  the control cluster. In an unmanaged install there is no control-cluster credential in your cluster at all.
- **No privilege escalation.** The applier has no `escalate`, `bind` or `impersonate` verbs, so it can't create a role
  or binding that grants more than it holds. Beacon's `impersonate` option is off by default.
- **No workloads outside two namespaces.** The applier has unrestricted write access only in `projectsveltos` and
  `ciroos-agent`. Elsewhere it can only manage CRDs, ClusterRoles and ClusterRoleBindings, ConfigMaps, events, and
  namespace labels and annotations (and pod create/delete when not restricted).
- **Nothing outside Sveltos on the control cluster.** The per-cluster identity can't read Secrets, workloads or any
  non-Sveltos resource there (section 2).
- **No unmanaged-install changes without you.** With `ciroos-agents`, nothing changes in your cluster unless you run
  `helm upgrade`.

**With restricted RBAC (section 6)**

- **No Secret reads outside `projectsveltos` and `ciroos-agent`.** This holds for the applier and for beacon.
- **No pod create/delete** by the applier or beacon.
- **No source repository watcher.** It isn't deployed, because it needs cluster-wide Secret access.

**What stays readable under restricted RBAC.** The curated list still includes ConfigMaps (cluster-wide), pod logs
and the other resource types listed in section 6.1. If ConfigMaps in your cluster hold sensitive data, review the
list before enabling Ciroos.

---

## 9. Network requirements

All connections are outbound from your cluster. You don't need to open any inbound port or allow Ciroos to reach your
API server.

| Destination | Protocol | Used by | Managed (`ciroos` / `installer`) | Unmanaged (`ciroos-agents`) |
|---|---|---|---|---|
| Ciroos control cluster API server (the `server:` URL in the kubeconfig you were given) | HTTPS, the port in that URL | Sveltos applier, to pull configuration and report back | Required | Not used |
| Ciroos platform ingress (`ingressFqdn`) | HTTPS (443) and WebSocket over TLS (`wss://…/ws/stargate`) | Agents, to send events, alerts, resource metadata and heartbeats | Required | Required |
| Ciroos container registry (`registry.ciroos.ai`) | HTTPS (443) | Image pulls for the applier and the agents | Required | Required |
| Ciroos onboarding API (`bootstrap.env.apiUrl`) | HTTPS (443) | The `installer` chart's bootstrap Job, once, to register the cluster | Only for `installer` | Not used |

Notes:

- Agents authenticate to the platform ingress with the client certificate in the `<clusterName>-client-cert` Secret
  (unmanaged) or the equivalent Ciroos provisions (managed). The connection uses TLS, so it can't be inspected by a
  proxy that terminates TLS.
- If your cluster uses an HTTP proxy or an allow-list firewall, add the hostnames above. If you mirror images, point the
  image `repository` values at your mirror.
- Inside the cluster, the charts ship NetworkPolicies for the `ciroos-agent` namespace (for example, agents to the
  Kubernetes API, eBPF collector to reducer). They don't affect traffic to the destinations above unless your cluster
  has a default-deny egress policy of its own. In that case, allow the destinations above from `projectsveltos` and
  `ciroos-agent`.

---

## 10. Uninstalling

**Managed (`ciroos` and `installer`).** `helm uninstall` runs an uninstaller Job as a post-delete hook. It removes
everything the applier deployed to the cluster, including the agents and their RBAC, so nothing remains afterwards.

```sh
helm uninstall ciroos -n projectsveltos
```

**Unmanaged (`ciroos-agents`).** `helm uninstall` removes the agents and their RBAC. Helm doesn't delete CRDs shipped
in a chart's `crds/` directory, so the Ciroos CRDs (`Alert`, `ResourceWatcher`, `AgentHealth`, `WorkloadSource`, ...)
stay in the cluster. Remove them yourself if you want a clean cluster:

```sh
kubectl get crd | grep ciroos.ai
kubectl delete crd <name> ...
```

Check which CRDs the chart ships in `charts/ciroos-agents/crds/` before deleting them. Deleting a CRD also deletes
every custom resource of that kind.
