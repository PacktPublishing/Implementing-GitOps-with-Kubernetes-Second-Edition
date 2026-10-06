# Cross-cloud drift and reconciliation signals

Chapter 11 covers observability strategy, including SRE principles, SLOs, DORA
metrics and tracing. What lives here is the narrow slice Chapter 8 needs: the metrics that
tell you whether *GitOps itself* is healthy on each cloud.

- `flux-rules.yaml` - alerting rules for the Flux controllers on AKS.
- `argocd-rules.yaml` - alerting rules for Argo CD Application state.

## The `cloud` label does not come from Kustomize

The rules group by a `cloud` label, and it is worth being precise about where
that label comes from, because it is a common source of confusion.

The `labels:` block in `gitops/overlays/*/kustomization.yaml` labels **Kubernetes
objects**. It cannot add a label to a Prometheus time series. The Flux and Argo CD
metrics have fixed label sets:

- `gotk_reconcile_condition{kind,name,namespace,type,status}`
- `gotk_suspend_status{kind,name,namespace}`
- `argocd_app_info{name,namespace,project,repo,dest_server,sync_status,health_status,...}`

So `cloud` has to be attached at collection time, as an external label on the
scraping agent or as a static label on remote write. On AWS, add it to the
collector's `global.external_labels`. On Azure, add it to the
`ama-metrics-settings-configmap` as a `prometheus-collector-settings` cluster
alias, or attach it during remote write. Until you do, `by (cloud)` produces an
empty label and `{{ $labels.cloud }}` renders blank.

## Loading the rules differs by cloud

**Amazon Managed Prometheus** accepts native Prometheus rule-group YAML, so
`flux-rules.yaml` can be loaded as-is with `aws amp create-rule-groups-namespace`.

**Azure Monitor managed Prometheus does not.** Rules there are an Azure resource,
`Microsoft.AlertsManagement/prometheusRuleGroups`, created from ARM, Bicep or the
CLI. Microsoft publishes `az-prom-rules-converter` precisely to turn a Prometheus
rule YAML file into that ARM template, so the rule *expressions* below are still
written once; it is the packaging that differs.

## Argo CD metrics on the managed capability

With self-managed Argo CD you scrape the application controller directly. With
the EKS capability for Argo CD the control plane runs outside your cluster, so
there is no controller pod to scrape. The `Application` objects themselves do
live in your cluster, so the portable way to get the same signal is to expose
their status with the kube-state-metrics *custom resource state* configuration
and alert on that. `argocd-rules.yaml` is written against the upstream metric
names; if you are on the capability, map them to your kube-state-metrics output.
