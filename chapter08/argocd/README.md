# Argo CD manifests (AWS path, and the multi-cloud fleet view)

- `application-aws.yaml`: a single Application targeting the EKS cluster.
- `appproject.yaml`: the tenancy boundary for the chapter.
- `applicationset-multicloud.yaml`: one definition that produces one Application
  per registered cluster, selected by the `cloud` label. This is the fleet view
  that makes the two clouds look like one control surface.

## Working with the EKS capability for Argo CD

These manifests are written for the managed capability, so a few things differ
from a self-managed installation:

- Clusters are referenced by **ARN**, not by API server URL. `destination.name`
  carries the cluster name registered with the capability.
- All three object kinds must live in the single namespace configured when the
  capability was created (`argocd` here).
- `argocd login` is unavailable; authenticate with a token and prefix commands
  with the namespace: `argocd app sync argocd/weather-app-aws`.
- Config management plugins, the notifications controller and custom SSO
  providers are not supported. Supported settings, including custom health checks
  under `resource.customizations.health.*`, are read from the `argocd-cm`
  ConfigMap in your cluster exactly as upstream. If you need a config management
  plugin or third-party SSO, stay self-managed.
- The sync timeout is fixed at 120 seconds.
