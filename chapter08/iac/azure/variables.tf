variable "subscription_id" {
  description = "Azure subscription ID. Defaults to the ARM_SUBSCRIPTION_ID environment variable."
  type        = string
  default     = null
}

variable "location" {
  description = "Azure region for all chapter resources."
  type        = string
  default     = "switzerlandnorth"
}

variable "resource_group_name" {
  description = "Name of the resource group holding the chapter resources."
  type        = string
  default     = "gitops-ch08-rg"
}

variable "cluster_name" {
  description = "AKS cluster name."
  type        = string
  default     = "aks-gitops-ch08"
}

variable "kubernetes_version" {
  description = <<-EOT
    AKS Kubernetes minor version. 1.34 reached GA on AKS in November 2025 and is
    supported until November 2026 (November 2027 with Long-Term Support enabled).
    Check `az aks get-versions -l <region> -o table` before applying.
  EOT
  type        = string
  default     = "1.34"
}

variable "node_count" {
  description = "System node pool size. One node is enough for the chapter walkthrough."
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "System node pool VM size."
  type        = string
  default     = "Standard_D2s_v4"
}

variable "gitops_repository_url" {
  description = "HTTPS URL of the Git repository that Flux reconciles."
  type        = string
  default     = "https://github.com/PacktPublishing/Implementing-GitOps-with-Kubernetes-2nd.git"
}

variable "gitops_branch" {
  description = "Branch Flux tracks."
  type        = string
  default     = "main"
}

variable "gitops_auth_secret_name" {
  description = <<-EOT
    Name of a Kubernetes secret (kind Opaque, keys "username"/"password") in the
    flux-system namespace holding Git credentials, for a private
    gitops_repository_url. Leave null for a public repository. Create the
    secret out of band, e.g.:
      kubectl create secret generic gitops-ch08-auth -n flux-system \
        --from-literal=username=git \
        --from-literal=password=<fine-grained PAT, Contents: Read-only>
  EOT
  type        = string
  default     = null
}

variable "gitops_path" {
  description = "Path inside the repository that Flux reconciles for this cluster."
  type        = string
  default     = "./chapter08/gitops/overlays/azure"
}

variable "github_repository" {
  description = "owner/repo allowed to federate into the CI identity (keyless push to ACR)."
  type        = string
  default     = "PacktPublishing/Implementing-GitOps-with-Kubernetes-2nd"
}

variable "github_oidc_subject_prefix" {
  description = <<-EOT
    Overrides the "repo:owner/repo" prefix used in the federated credential
    subject. Only needed when the repository has immutable OIDC subject
    claims enabled (Settings > Actions > General > "Use immutable subject
    claims"), in which case GitHub replaces owner/repo with owner@ownerId/repo@repoId.
    Get the exact value with:
      gh api /repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
  EOT
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    book    = "Implementing GitOps with Kubernetes, 2nd Edition"
    chapter = "08"
  }
}
