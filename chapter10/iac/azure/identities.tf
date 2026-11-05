# -----------------------------------------------------------------------------
# Identities. There is no client secret, no registry password and no
# kubeconfig token anywhere in this chapter: every actor proves who it is with
# a federated token.
#
#   ci           GitHub Actions on main     -> AcrPush
#   argocd-hub   Argo CD on mgmt            -> deploy to nonprod and prod
#   kargo        Kargo controller on mgmt   -> read image tags from ACR
#   kargo-git    ESO in the Kargo project   -> read the Git token from Key Vault
#   weather-<env> ESO in each app namespace -> read the weather API key
# -----------------------------------------------------------------------------

locals {
  mgmt_issuer = azurerm_kubernetes_cluster.this["mgmt"].oidc_issuer_url
  workload_clusters = {
    for k, v in var.clusters : k => v if v.role == "workload"
  }
  # One entry per application environment: env => cluster key.
  environments = merge([
    for k, v in var.clusters : { for env in v.environments : env => k }
  ]...)
  argocd_service_accounts = [
    "argocd-application-controller",
    "argocd-applicationset-controller",
    "argocd-server",
  ]
}

# --- CI ----------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "ci" {
  name                = "id-ch10-ci"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

# Only pushes to main may publish an image. Pull-request builds run the tests
# and the scan but never authenticate to Azure.
resource "azurerm_federated_identity_credential" "ci_main" {
  name                = "github-main"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.ci.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_repository}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "ci_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
}

# --- Argo CD hub ---------------------------------------------------------------

resource "azurerm_user_assigned_identity" "argocd_hub" {
  name                = "id-ch10-argocd-hub"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "argocd_hub" {
  for_each = toset(local.argocd_service_accounts)

  name                = each.value
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.argocd_hub.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = local.mgmt_issuer
  subject             = "system:serviceaccount:argocd:${each.value}"
}

# Chapter 10 grants the hub cluster-admin on the workload clusters to keep the
# walkthrough short. Chapter 12 replaces this with a read-only hub identity and
# per-project sync impersonation.
resource "azurerm_role_assignment" "argocd_hub_workload" {
  for_each = local.workload_clusters

  scope                = azurerm_kubernetes_cluster.this[each.key].id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = azurerm_user_assigned_identity.argocd_hub.principal_id
}

# --- Kargo ---------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "kargo" {
  name                = "id-ch10-kargo"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "kargo" {
  name                = "kargo-controller"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.kargo.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = local.mgmt_issuer
  subject             = "system:serviceaccount:kargo:kargo-controller"
}

# Kargo discovers new tags in ACR with this ambient identity: no image
# credential Secret is needed.
resource "azurerm_role_assignment" "kargo_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.kargo.principal_id
}

resource "azurerm_user_assigned_identity" "kargo_git" {
  name                = "id-ch10-kargo-git"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "kargo_git" {
  name                = "kargo-git-secrets"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.kargo_git.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = local.mgmt_issuer
  subject             = "system:serviceaccount:weather:kargo-git-secrets"
}

# Scoped to one secret, not to the vault.
resource "azurerm_role_assignment" "kargo_git_secret" {
  scope                = azurerm_key_vault_secret.placeholders["kargo-github-token"].resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.kargo_git.principal_id
}

# --- Application secrets, one identity per environment ---------------------------

resource "azurerm_user_assigned_identity" "weather" {
  for_each = local.environments

  name                = "id-ch10-weather-${each.key}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "weather" {
  for_each = local.environments

  name                = "weather-${each.key}"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = azurerm_user_assigned_identity.weather[each.key].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this[each.value].oidc_issuer_url
  subject             = "system:serviceaccount:weather-${each.key}:weather-secrets"
}

resource "azurerm_role_assignment" "weather_secret" {
  for_each = local.environments

  scope                = azurerm_key_vault_secret.placeholders["weather-api-key-${each.key}"].resource_versionless_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.weather[each.key].principal_id
}
