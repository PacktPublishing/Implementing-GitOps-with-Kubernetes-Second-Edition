# These outputs become the keys of the Kubernetes Secret named in
# .spec.writeOutputsToSecret. Keep them small and stable: they are an API.

output "resource_group_name" {
  value = module.network.resource_group_name
}

output "location" {
  value = module.network.location
}

output "vnet_id" {
  value = module.network.vnet_id
}

output "workload_subnet_id" {
  value = module.network.workload_subnet_id
}

output "private_endpoint_subnet_id" {
  value = module.network.private_endpoint_subnet_id
}
