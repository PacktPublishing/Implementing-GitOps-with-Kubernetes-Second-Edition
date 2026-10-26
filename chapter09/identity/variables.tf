variable "subscription_id" {
  description = "Azure subscription the runner will provision into."
  type        = string
  default     = null
}

variable "location" {
  description = "Region for the identity and state resources."
  type        = string
  default     = "switzerlandnorth"
}

variable "resource_group_name" {
  description = "Resource group holding the managed identity and the state account."
  type        = string
  default     = "gitops-tfstate-rg"
}

variable "oidc_issuer_url" {
  description = <<-EOT
    OIDC issuer URL of the management cluster. Obtain it with:
      az aks show -g <rg> -n <cluster> --query oidcIssuerProfile.issuerUrl -o tsv
  EOT
  type        = string
}

variable "runner_namespaces" {
  description = "Namespaces whose tf-runner service account may federate."
  type        = list(string)
  default     = ["flux-system"]
}

variable "state_storage_account_name" {
  description = "Globally unique name for the remote state storage account."
  type        = string
}

variable "github_repository" {
  description = <<-EOT
    Optional. "<owner>/<repo>" of the fork whose pull requests run the IaC
    policy gate. When set, a separate read-only CI identity is created and
    federated to that repository's pull_request workflows. See ci.tf.
  EOT
  type        = string
  default     = null
}

variable "github_oidc_subject_prefix" {
  description = <<-EOT
    Overrides the "repo:owner/repo" prefix used in the CI federated credential
    subject. Only needed when the repository has immutable OIDC subject
    claims enabled (Settings > Actions > General > "Use immutable subject
    claims"), in which case GitHub replaces owner/repo with owner@ownerId/repo@repoId.
    Get the exact value with:
      gh api /repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
  EOT
  type        = string
  default     = null
}

variable "ci_environment" {
  description = <<-EOT
    Name of the protected GitHub environment the IaC policy workflow's plan job
    runs in. The CI identity trusts only repo:<owner>/<repo>:environment:<name>.
    Create the environment with required reviewers before opening a pull request.
  EOT
  type        = string
  default     = "iac-plan"
}

variable "enable_state_encryption" {
  description = "Create a Key Vault and key for OpenTofu state encryption. See state-encryption.tf."
  type        = bool
  default     = false
}

variable "state_key_vault_name" {
  description = "Globally unique Key Vault name, 3-24 characters. Required when enable_state_encryption is true."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_state_encryption || var.state_key_vault_name != null
    error_message = "state_key_vault_name must be set when enable_state_encryption is true."
  }
}
