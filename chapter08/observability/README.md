# Cross-cloud drift and reconciliation signals

Chapter 11 covers observability strategy, including SRE principles, SLOs, DORA
metrics and tracing. What lives here is the narrow slice Chapter 8 needs: the metrics that
tell you whether *GitOps itself* is healthy on each cloud.

- `flux-rules.yaml` - alerting rules for Flux on AKS, written against
  `gotk_resource_info`.
- `argocd-rules.yaml` - alerting rules for **self-managed** Argo CD, written
  against the upstream controller metrics.
- `argocd-capability-rules.yaml` - status-based rules for the **EKS capability
  for Argo CD**, written against `argocd_capability_app_info`.
- `kube-state-metrics-argocd.yaml` - kube-state-metrics values that export
  `argocd_capability_app_info` from `Application` status.

The alerting goals are shared across clouds; the queries are not, because Flux
and the managed Argo CD capability expose different metrics and labels. Reuse an
expression only where the input metrics match.

## Where the Flux metric comes from

`gotk_resource_info` is **not** published by the Flux controllers. It is exported
by kube-state-metrics from the status of the Flux custom resources, using the
custom-resource-state configuration from the Flux monitoring example
(<https://github.com/fluxcd/flux2-monitoring-example>, file
`monitoring/controllers/kube-prometheus-stack/kube-state-metrics-config.yaml`).
Install that configuration first; without it the Flux rules match nothing.

The older controller metrics `gotk_reconcile_condition` and
`gotk_suspend_status` were removed from Flux. Do not alert on them.

## The `cloud` label does not come from Kustomize

The rules group by a `cloud` label, and it is worth being precise about where
that label comes from, because it is a common source of confusion.

The `labels:` block in `gitops/overlays/*/kustomization.yaml` labels **Kubernetes
objects**. It cannot add a label to a Prometheus time series. The metrics used
here have fixed label sets:

- `gotk_resource_info{customresource_kind,exported_namespace,name,ready,suspended,...}`
- `argocd_app_info{name,namespace,project,repo,dest_server,sync_status,health_status,...}` (self-managed)
- `argocd_capability_app_info{exported_namespace,name,project,dest_name,sync_status,health_status,operation_phase}` (capability)

So `cloud` has to be attached at collection time, as an external label on the
scraping agent or as a static label on remote write. On AWS, add it to the
collector's `global.external_labels`. On Azure, add it to the
`ama-metrics-settings-configmap` as a `prometheus-collector-settings` cluster
alias, or attach it during remote write. Until you do, `by (cloud)` produces an
empty label and `{{ $labels.cloud }}` renders blank.

## Loading the rules differs by cloud

**Amazon Managed Prometheus** accepts native Prometheus rule-group YAML, so the
rule files can be loaded as-is with `aws amp create-rule-groups-namespace`.

**Azure Monitor managed Prometheus does not.** Rules there are an Azure resource,
`Microsoft.AlertsManagement/prometheusRuleGroups`, created from ARM, Bicep or the
CLI. Microsoft publishes `az-prom-rules-converter` precisely to turn a Prometheus
rule YAML file into that ARM template; it is the packaging that differs.

## Argo CD metrics on the managed capability

With self-managed Argo CD you scrape the application controller directly and use
`argocd-rules.yaml`. With the EKS capability for Argo CD the control plane runs
outside your cluster, so there is no controller pod to scrape. The `Application`
objects themselves do live in your cluster, so merge
`kube-state-metrics-argocd.yaml` into your kube-state-metrics values and load
`argocd-capability-rules.yaml`.
