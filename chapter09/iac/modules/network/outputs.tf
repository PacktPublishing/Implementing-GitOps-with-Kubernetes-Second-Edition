# Outputs are the contract this module offers to the rest of the estate.
# Tofu Controller writes them to a Kubernetes Secret with
# .spec.writeOutputsToSecret, and the data module reads them back with
# .spec.varsFrom. Every key in the Secret becomes a variable of the same name,
# which is why these names match the data root's variable names exactly.

output "resource_group_name" {
  description = "Name of the environment resource group."
  value       = azurerm_resource_group.main.name
}

output "location" {
  description = "Region the environment was created in."
  value       = azurerm_resource_group.main.location
}

output "vnet_id" {
  description = "Resource ID of the virtual network. Needed to link the private DNS zone."
  value       = azurerm_virtual_network.main.id
}

output "workload_subnet_id" {
  description = "Resource ID of the workload subnet."
  value       = azurerm_subnet.workload.id
}

output "private_endpoint_subnet_id" {
  description = "Resource ID of the private endpoint subnet."
  value       = azurerm_subnet.private_endpoints.id
}
