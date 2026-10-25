# Export these into the shell before creating the azure-environment ConfigMap:
#
#   export ARM_CLIENT_ID=$(tofu output -raw client_id)
#   export ARM_TENANT_ID=$(tofu output -raw tenant_id)
#   export ARM_SUBSCRIPTION_ID=$(tofu output -raw subscription_id)

output "client_id" {
  description = "Set this as ARM_CLIENT_ID and as the tf-runner service account annotation."
  value       = azurerm_user_assigned_identity.tf_runner.client_id
}

output "tenant_id" {
  description = "Set this as ARM_TENANT_ID."
  value       = data.azurerm_subscription.current.tenant_id
}

output "subscription_id" {
  description = "Set this as ARM_SUBSCRIPTION_ID."
  value       = data.azurerm_subscription.current.subscription_id
}

output "state_storage_account_name" {
  description = "Replaces REPLACE_WITH_YOUR_STATE_ACCOUNT in terraform/ and iac/azure/*/backend.hcl (README step 1)."
  value       = azurerm_storage_account.state.name
}

output "ci_client_id" {
  description = "Set this as the AZURE_CLIENT_ID repository variable for the IaC policy workflow."
  value       = one(azurerm_user_assigned_identity.ci[*].client_id)
}

output "state_key_vault_uri" {
  description = "vault_uri for the azure_vault key provider."
  value       = one(azurerm_key_vault.state[*].vault_uri)
}

output "state_key_name" {
  description = "vault_key_name for the azure_vault key provider."
  value       = one(azurerm_key_vault_key.prod_state[*].name)
}
