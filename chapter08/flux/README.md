# Flux manifests (Azure path)

Two ways to point Flux at a source are shown here.

- `gitrepository.yaml` + `kustomization-git.yaml`: the classic Git source.
- `ocirepository.yaml` + `kustomization-oci.yaml`: the same desired state
  published as an OCI artifact in Azure Container Registry.
- `imagepolicy.yaml`: image automation, so that a new image published by CI is
  written back to Git as a commit rather than applied by the pipeline.

All of these use the stable APIs (`source.toolkit.fluxcd.io/v1`,
`kustomize.toolkit.fluxcd.io/v1`, `helm.toolkit.fluxcd.io/v2`). The beta versions
used in the first edition were removed in `microsoft.flux` extension 1.23.0
(June 2026) and will no longer reconcile.

If the cluster was provisioned with `iac/azure`, the `fluxConfigurations`
resource already created an equivalent `GitRepository` and `Kustomization`. These
files are here so you can read what Azure generated, and so you can apply the
same objects to a self-managed Flux installation.
