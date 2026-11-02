data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

data "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  resource_group_name = var.resource_group_name
}

# Key Vault with Azure RBAC (no access policies) and purge protection.
resource "azurerm_key_vault" "app" {
  name                       = var.key_vault_name
  location                   = data.azurerm_resource_group.main.location
  resource_group_name        = data.azurerm_resource_group.main.name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 30
}

# One identity per tenant namespace, never one for the whole operator.
resource "azurerm_user_assigned_identity" "eso_reader" {
  name                = "id-${var.app_namespace}-eso-reader"
  location            = data.azurerm_resource_group.main.location
  resource_group_name = data.azurerm_resource_group.main.name
}

# The subject is the whole security boundary: one service account in one
# namespace on one cluster issuer.
resource "azurerm_federated_identity_credential" "eso_reader" {
  name                      = "fic-${var.app_namespace}-eso-reader"
  user_assigned_identity_id = azurerm_user_assigned_identity.eso_reader.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = data.azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.app_namespace}:eso-reader"
}

# Read secret values only; no list of vault contents, no write.
resource "azurerm_role_assignment" "eso_reader" {
  scope                = azurerm_key_vault.app.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.eso_reader.principal_id
}

# Secret VALUES are deliberately not managed here: anything in a Terraform
# resource ends up in state (Chapter 9). Create them out of band:
#   az keyvault secret set --vault-name kv-gitops-ch12 \
#     --name weather-app-db --value "$(openssl rand -base64 24)"
