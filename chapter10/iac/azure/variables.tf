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
  description = "Resource group holding the chapter resources."
  type        = string
  default     = "gitops-ch10-rg"
}

variable "kubernetes_version" {
  description = <<-EOT
    AKS minor version for every cluster. 1.36 is used because the Envoy Gateway
    1.9 line supports Kubernetes 1.33-1.36. Check
    `az aks get-versions -l <region> -o table` before applying.
  EOT
  type        = string
  default     = "1.36"
}

variable "clusters" {
  description = <<-EOT
    The estate. "role" becomes an Argo CD cluster label and decides which
    platform add-ons a cluster receives; "environments" lists the application
    environments the cluster hosts (one namespace each).
  EOT
  type = map(object({
    role         = string
    environments = list(string)
    node_vm_size = string
    min_nodes    = number
    max_nodes    = number
  }))
  default = {
    mgmt = {
      role         = "management"
      environments = []
      node_vm_size = "Standard_D2s_v5"
      min_nodes    = 2
      max_nodes    = 3
    }
    nonprod = {
      role         = "workload"
      environments = ["dev", "staging"]
      node_vm_size = "Standard_D2s_v5"
      min_nodes    = 2
      max_nodes    = 4
    }
    prod = {
      role         = "workload"
      environments = ["prod"]
      node_vm_size = "Standard_D4s_v5"
      min_nodes    = 3
      max_nodes    = 6
    }
  }
}

variable "github_repository" {
  description = "owner/repo allowed to federate into the CI identity (keyless push to ACR)."
  type        = string
  default     = "PacktPublishing/Implementing-GitOps-with-Kubernetes-Second-Edition"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    book    = "Implementing GitOps with Kubernetes, 2nd Edition"
    chapter = "10"
  }
}
