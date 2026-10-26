output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "acr_login_server" {
  description = "Registry host to use in the Azure overlay and CI workflow."
  value       = azurerm_container_registry.acr.login_server
}

output "oidc_issuer_url" {
  description = "Cluster OIDC issuer, needed when federating workload identities."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "ci_client_id" {
  description = "AZURE_CLIENT_ID for the GitHub Actions workflow."
  value       = azurerm_user_assigned_identity.ci.client_id
}

output "ci_pr_client_id" {
  description = "Client ID of the separate pull-request identity (no AcrPush). Use only in pull-request workflows."
  value       = azurerm_user_assigned_identity.ci_pr.client_id
}

output "prometheus_query_endpoint" {
  value = azurerm_monitor_workspace.prometheus.query_endpoint
}

output "get_credentials_command" {
  value = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name}"
}
