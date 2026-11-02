output "tenant_role_arn" {
  description = "Set as spec.provider.aws.role in the weather-app SecretStore"
  value       = aws_iam_role.tenant.arn
}
