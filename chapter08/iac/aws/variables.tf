variable "region" {
  description = "AWS region for all chapter resources."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "eks-gitops-ch08"
}

variable "kubernetes_version" {
  description = <<-EOT
    EKS Kubernetes minor version. 1.34 is in standard support until December 2026;
    1.35 and 1.36 are also available. The first edition pinned 1.29, which left
    standard support long ago.
  EOT
  type        = string
  default     = "1.34"
}

variable "instance_types" {
  description = "Managed node group instance types."
  type        = list(string)
  default     = ["t3.large"]
}

variable "gitops_repository_url" {
  description = "HTTPS URL of the Git repository Argo CD reconciles."
  type        = string
  default     = "https://github.com/PacktPublishing/Implementing-GitOps-with-Kubernetes-2nd.git"
}

variable "gitops_branch" {
  description = "Branch Argo CD tracks."
  type        = string
  default     = "main"
}

variable "github_repository" {
  description = "owner/repo allowed to federate into the CI role (keyless push to ECR)."
  type        = string
  default     = "PacktPublishing/Implementing-GitOps-with-Kubernetes-2nd"
}

variable "argocd_namespace" {
  description = <<-EOT
    Namespace holding Application, ApplicationSet and AppProject objects.
    The EKS capability for Argo CD confines them to a single namespace, unlike
    self-managed Argo CD.
  EOT
  type        = string
  default     = "argocd"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    book    = "Implementing GitOps with Kubernetes, 2nd Edition"
    chapter = "08"
  }
}

variable "idc_admin_group_display_name" {
  description = <<-EOT
    Display name of the AWS IAM Identity Center group mapped to the Argo CD ADMIN
    role. The capability supports only Identity Center as an SSO provider.
  EOT
  type        = string
  default     = "AWSAdministrator"
}

variable "enable_ack_capability" {
  description = "Also enable the ACK capability, used in the AWS tooling section."
  type        = bool
  default     = false
}
