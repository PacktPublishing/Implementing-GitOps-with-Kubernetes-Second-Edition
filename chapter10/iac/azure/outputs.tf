output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.main.vault_uri
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

# Used by scripts/render-placeholders.sh to fill the cluster Secrets in
# platform/hub/clusters.
output "clusters" {
  value = {
    for k, c in azurerm_kubernetes_cluster.this : k => {
      name     = c.name
      role     = var.clusters[k].role
      endpoint = c.kube_config[0].host
      ca_data  = c.kube_config[0].cluster_ca_certificate
    }
  }
  sensitive = true
}

output "ci_client_id" {
  value = azurerm_user_assigned_identity.ci.client_id
}

output "argocd_hub_client_id" {
  value = azurerm_user_assigned_identity.argocd_hub.client_id
}

output "kargo_client_id" {
  value = azurerm_user_assigned_identity.kargo.client_id
}

output "kargo_git_client_id" {
  value = azurerm_user_assigned_identity.kargo_git.client_id
}

output "weather_client_ids" {
  value = { for env, id in azurerm_user_assigned_identity.weather : env => id.client_id }
}
