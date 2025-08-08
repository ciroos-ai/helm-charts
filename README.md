# helm-charts
Helm charts for deploying agents

Prepare values.yaml. Following fields must be set

```
clusterNamespace: <cluster namespace>
clusterName: <cluster name>
pullmodeSecret:
  kubeconfig: <kubeconfig for sveltos applier to connect to Ciroos control cluster>
```

```
helm repo add ciroos https://ciroos-ai.github.io/helm-charts
helm install ciroos ciroos/ciroos --create-namespace -n projectsveltos  -f /tmp/values.yaml
```
