# -----------------------------------------------------------------------------
# Optional: a Key Vault key for OpenTofu state and plan encryption.
#
# Used by the azure_vault key provider (OpenTofu 1.11 or later); see
# examples/state-encryption/. OpenTofu generates a fresh data key for every
# state or plan file and wraps it with this key, so whoever runs tofu needs
# three data-plane permissions on it: keys/read, wrap and unwrap. The built-in
# role "Key Vault Crypto Service Encryption User" is exactly that set.
#
# The OpenTofu documentation recommends one key per state file. One key per
# environment is the compromise shown here; add keys if your estate needs the
# isolation.
#
# Created only when enable_state_encryption = true.
# -----------------------------------------------------------------------------

resource "azurerm_key_vault" "state" {
  count = var.enable_state_encryption ? 1 : 0

  name                       = var.state_key_vault_name
  resource_group_name        = azurerm_resource_group.bootstrap.name
  location                   = azurerm_resource_group.bootstrap.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true

  # A key that protects state must not be recoverable by accident or lost by
  # accident. Purge protection means a deleted vault is only soft-deleted for
  # the retention period, and its name cannot be reused until then.
  purge_protection_enabled   = true
  soft_delete_retention_days = 7
}

# The person running this bootstrap needs to create the key.
resource "azurerm_role_assignment" "state_key_officer" {
  count = var.enable_state_encryption ? 1 : 0

  scope                = azurerm_key_vault.state[0].id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_key" "prod_state" {
  count = var.enable_state_encryption ? 1 : 0

  name         = "tfstate-prod"
  key_vault_id = azurerm_key_vault.state[0].id
  key_type     = "RSA"
  key_size     = 3072
  key_opts     = ["wrapKey", "unwrapKey"]

  depends_on = [azurerm_role_assignment.state_key_officer]
}

# The runner wraps and unwraps on every plan and apply.
resource "azurerm_role_assignment" "runner_state_key" {
  count = var.enable_state_encryption ? 1 : 0

  scope                = azurerm_key_vault_key.prod_state[0].resource_versionless_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.tf_runner.principal_id
}

# CI plans production against its real state, so it has to decrypt it too.
# That is a real widening: the pull request identity can now read every value
# in the production state. Leave github_repository unset, or drop production
# from the CI plan, if that trade is wrong for you.
resource "azurerm_role_assignment" "ci_state_key" {
  count = var.enable_state_encryption && var.github_repository != null ? 1 : 0

  scope                = azurerm_key_vault_key.prod_state[0].resource_versionless_id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.ci[0].principal_id
}
