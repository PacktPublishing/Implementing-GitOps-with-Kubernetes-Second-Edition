output "tenant_id" {
  value = data.azuread_client_config.current.tenant_id
}

output "argocd_client_id" {
  description = "Entra application (client) ID used by argocd-cm and the argocd-server service account"
  value       = azuread_application.argocd.client_id
}

output "argocd_hub_role_arn" {
  description = "AWS role the hub components assume with their projected token"
  value       = aws_iam_role.argocd_hub.arn
}
