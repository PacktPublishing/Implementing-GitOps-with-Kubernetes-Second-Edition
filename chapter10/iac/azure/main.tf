# -----------------------------------------------------------------------------
# Shared services: resource group, registry, Key Vault
# -----------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# One registry for every environment. Promotion moves a tag reference through
# Git; it never copies or rebuilds the image.
resource "azurerm_container_registry" "acr" {
  name                = "gitopsch10${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  admin_enabled       = false
  tags                = var.tags
}

# Holds the weather provider API key and the Kargo Git token. Neither value is
# ever written to Git or to a pipeline: you set them once with `az keyvault
# secret set` (see README, step 1.3), and External Secrets Operator reads them.
resource "azurerm_key_vault" "main" {
  name                       = "kv-gitops-ch10-${random_string.suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  tags                       = var.tags
}

# Lets the person running `tofu apply` write the secret values afterwards.
resource "azurerm_role_assignment" "operator_kv_officer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# The secrets are created empty so that role assignments can be scoped to each
# one. Their real values are set out of band and never pass through state:
# OpenTofu ignores later changes to `value`.
resource "azurerm_key_vault_secret" "placeholders" {
  for_each = toset(concat(
    ["kargo-github-token"],
    [for env in keys(local.environments) : "weather-api-key-${env}"],
  ))

  name         = each.value
  value        = "REPLACE_ME"
  key_vault_id = azurerm_key_vault.main.id

  lifecycle {
    ignore_changes = [value]
  }

  depends_on = [time_sleep.rbac_propagation]
}

# Azure RBAC assignments take a short while to propagate; without the pause,
# the first secret write can fail with 403.
resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.operator_kv_officer]
  create_duration = "60s"
}
