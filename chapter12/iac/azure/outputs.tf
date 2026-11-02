output "eso_reader_client_id" {
  description = "Annotate the eso-reader service account with this value"
  value       = azurerm_user_assigned_identity.eso_reader.client_id
}

output "key_vault_uri" {
  value = azurerm_key_vault.app.vault_uri
}
