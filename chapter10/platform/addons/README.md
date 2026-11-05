# Platform add-ons

One small file per add-on and cluster role. The file pins the chart and its
version; `values/<addon>/` holds the configuration. The ApplicationSets in
`hub/applicationsets` combine every file here with every cluster of the
matching role, so adding an add-on to the fleet, or upgrading one, is a
one-line pull request that Renovate (Chapter 5) can open for you.

| Add-on | management | workload | Why |
|---|---|---|---|
| cert-manager | yes | yes | Kargo's webhooks (mgmt); TLS for Gateways (workload) |
| external-secrets | yes | yes | Kargo Git token (mgmt); application API key (workload) |
| kargo | yes | - | Promotion between environments |
| envoy-gateway | - | yes | Gateway API implementation (Ingress-NGINX is retired) |
| argo-rollouts | - | yes | Canary releases with automated analysis |
| keda | - | yes | Event- and metric-driven autoscaling |
| kube-prometheus-stack | - | yes | Metrics for HPA/KEDA, canary analysis, dashboards (Chapter 11) |
