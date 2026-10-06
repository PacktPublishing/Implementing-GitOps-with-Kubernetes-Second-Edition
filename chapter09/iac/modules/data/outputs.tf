output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.main.name
}

output "blob_endpoint" {
  description = "Primary blob service endpoint. Consumed by the application layer."
  value       = azurerm_storage_account.main.primary_blob_endpoint
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.main.id
}
