# -----------------------------------------------------------------------------
# Azure-managed GitOps: the microsoft.flux cluster extension
#
# This is the difference between the first and second editions of this chapter.
# Instead of a pipeline agent pushing manifests into the cluster, Azure installs
# and maintains the Flux controllers as a cluster extension, and the controllers
# pull the desired state from Git.
#
# Extension version note: microsoft.flux 1.23.0 (June 2026) REMOVED the
# deprecated Flux beta APIs (source v1beta1/v1beta2, kustomize v1beta1/v1beta2,
# helm v2beta1/v2beta2). Manifests written for the first edition will fail to
# reconcile. Everything under ../flux uses the current APIs. Leaving
# release_train on "stable" keeps the extension current; pin `version` instead
# if you need a frozen environment.
# -----------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_extension" "flux" {
  name           = "flux"
  cluster_id     = azurerm_kubernetes_cluster.main.id
  extension_type = "microsoft.flux"

  # Omit `version` so that Azure keeps the extension on the stable release train.
  release_train = "stable"

  configuration_settings = {
    # source, kustomize, helm and notification controllers are installed by
    # default. The two image controllers are NOT: they are opt-in, and they are
    # what allows a new image to be written back to Git as a commit instead of
    # being applied by a pipeline.
    "image-automation-controller.enabled" = "true"
    "image-reflector-controller.enabled"  = "true"

    # Multi-tenancy enforcement (cross-namespace source references refused) is
    # already the default. It is set explicitly here only to document the intent
    # and to guard against someone disabling it later; the flag exists mainly so
    # that it CAN be turned off, which on a shared cluster it should not be.
    "multiTenancy.enforce" = "true"
  }

  depends_on = [azurerm_role_assignment.kubelet_acr_pull]
}

# The Flux configuration itself: which repository, which branch, which path.
#
# Azure names the resulting cluster objects after this resource: a configuration
# called "gitops-ch08" with a kustomization called "apps" produces a
# Kustomization named gitops-ch08-apps in the flux-system namespace. Use that
# full name with the Flux CLI.
resource "azurerm_kubernetes_flux_configuration" "main" {
  name       = "gitops-ch08"
  cluster_id = azurerm_kubernetes_cluster.main.id
  namespace  = "flux-system"
  scope      = "cluster"

  # Reconcile continuously. Setting this to false is the documented "stop the
  # world" switch during an incident. Alert on it, because a configuration left
  # suspended has quietly stopped tracking Git.
  continuous_reconciliation_enabled = true

  git_repository {
    url             = var.gitops_repository_url
    reference_type  = "branch"
    reference_value = var.gitops_branch

    # Required for a private repository. Points at a Kubernetes secret
    # (kind Opaque, keys "username"/"password") that you create out of band
    # with kubectl, so the PAT never enters Terraform state:
    #   kubectl create secret generic gitops-ch08-auth -n flux-system \
    #     --from-literal=username=git \
    #     --from-literal=password=<fine-grained PAT, Contents: Read-only>
    local_auth_reference = var.gitops_auth_secret_name

    sync_interval_in_seconds = 60
    timeout_in_seconds       = 600
  }

  kustomizations {
    name = "apps"
    path = var.gitops_path

    sync_interval_in_seconds  = 60
    retry_interval_in_seconds = 60
    timeout_in_seconds        = 600

    # Garbage collection is Azure's name for Flux pruning: it removes objects
    # deleted from Git. It defaults to FALSE, which means that without this line
    # Git remains the source of truth for creation and updates but silently
    # stops being the source of truth for deletion.
    garbage_collection_enabled = true
  }

  depends_on = [azurerm_kubernetes_cluster_extension.flux]
}
