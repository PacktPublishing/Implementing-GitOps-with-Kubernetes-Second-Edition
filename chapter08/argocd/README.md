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
- `AppProject` objects must live in the capability's primary namespace (`argocd`
  here). `Application` and `ApplicationSet` objects use it by default and can use
  additional namespaces once `application.namespaces` and
  `applicationsetcontroller.namespaces` are enabled in `argocd-cmd-params-cm` and
  the project lists them in `spec.sourceNamespaces`.
- Global role mapping accepts only `ADMIN`, `EDITOR` and `VIEWER`. AppProject
  roles and policies grant finer-grained access; `EDITOR` and `VIEWER` users need
  project roles to see Applications.
- `argocd login` is unavailable; authenticate with a token and prefix commands
  with the namespace: `argocd app sync argocd/weather-app-aws`.
- Config management plugins, the notifications controller and custom SSO
  providers are not supported. Supported settings, including custom health checks
  under `resource.customizations.health.*`, are read from the `argocd-cm`
  ConfigMap in your cluster. Many Lua health checks carry over, but the managed
  runtime disables the standard Lua libraries (`useOpenLibs`), so test scripts
  that depend on them before migrating. UI extensions are unsupported; UI banners
  can be set through supported `argocd-cm` settings. If you need a config
  management plugin or third-party SSO, stay self-managed.
- The sync timeout is fixed at 120 seconds.
