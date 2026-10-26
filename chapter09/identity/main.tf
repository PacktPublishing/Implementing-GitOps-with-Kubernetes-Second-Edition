resource "azurerm_resource_group" "bootstrap" {
  name     = var.resource_group_name
  location = var.location
}

# -----------------------------------------------------------------------------
# The identity the runner pods assume. No client secret is ever created: trust
# is established by federating the cluster's OIDC issuer with a specific
# service account in a specific namespace.
# -----------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "tf_runner" {
  name                = "gitops-tf-runner"
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = azurerm_resource_group.bootstrap.location
}

# AzureRM 4.65 renamed parent_id to user_assigned_identity_id, and AzureRM 5.0
# removed parent_id; the resource group is implied by the identity's resource
# ID. When upgrading an existing credential, review the plan rather than
# assuming the rename forces replacement; if a replacement is proposed,
# schedule it so runner token exchanges are not interrupted.
resource "azurerm_federated_identity_credential" "tf_runner" {
  for_each = toset(var.runner_namespaces)

  name                      = "tf-runner-${each.value}"
  user_assigned_identity_id = azurerm_user_assigned_identity.tf_runner.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.oidc_issuer_url

  # This is the whole security boundary: only this service account, in this
  # namespace, on this cluster, can obtain a token for this identity.
  subject = "system:serviceaccount:${each.value}:tf-runner"
}

# Contributor at subscription scope is what the first edition granted. It is
# too wide for most estates; scope the assignment to the resource groups the
# runner is expected to manage, or replace it with a custom role.
resource "azurerm_role_assignment" "tf_runner" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.tf_runner.principal_id
}

# -----------------------------------------------------------------------------
# Remote state for production. Cluster Secrets are fine for dev; production
# state should outlive the cluster that reconciles it.
# -----------------------------------------------------------------------------

resource "azurerm_storage_account" "state" {
  name                     = var.state_storage_account_name
  resource_group_name      = azurerm_resource_group.bootstrap.name
  location                 = azurerm_resource_group.bootstrap.location
  account_tier             = "Standard"
  account_replication_type = "ZRS"

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }
  }
}

# storage_account_id rather than the removed storage_account_name: with the
# resource ID the provider uses the Resource Manager API, which is why the
# container can still be created while shared keys are disabled.
resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "state_writer" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.tf_runner.principal_id
}

# The person running this bootstrap. Shared keys are disabled on the state
# account, so reading state from a terminal -- for the production teardown, or
# for a break-glass inspection -- needs a data-plane role. Owner and
# Contributor do not include one.
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "state_operator" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
