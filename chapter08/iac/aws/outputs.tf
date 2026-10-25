output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_arn" {
  description = "Register clusters with Argo CD by ARN, not by API server URL."
  value       = module.eks.cluster_arn
}

output "ecr_repository_url" {
  description = "Registry path to use in the AWS overlay and CI workflow."
  value       = aws_ecr_repository.app.repository_url
}

output "account_id" {
  description = "Never hardcode this into a manifest; the overlay patches it in."
  value       = data.aws_caller_identity.current.account_id
}

output "github_ci_role_arn" {
  description = "AWS_ROLE_ARN for the GitHub Actions workflow."
  value       = aws_iam_role.github_ci.arn
}

output "argocd_capability_arn" {
  value = module.argocd_capability.arn
}

output "update_kubeconfig_command" {
  value = "aws eks --region ${var.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "argocd_capability_role_arn" {
  description = "IAM role the AWS-managed Argo CD control plane assumes."
  value       = module.argocd_capability.iam_role_arn
}

output "argocd_server_url" {
  description = "URL of the AWS-managed Argo CD server."
  value       = module.argocd_capability.argocd_server_url
}
