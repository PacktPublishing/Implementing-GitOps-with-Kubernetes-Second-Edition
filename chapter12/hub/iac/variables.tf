variable "subscription_id" {
  type    = string
  default = null
}

# Defaults match chapter08/iac/azure and chapter08/iac/aws.
variable "resource_group_name" {
  type    = string
  default = "gitops-ch08-rg"
}

variable "aks_cluster_name" {
  type    = string
  default = "aks-gitops-ch08"
}

variable "eks_cluster_name" {
  type    = string
  default = "eks-gitops-ch08"
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "argocd_namespace" {
  type    = string
  default = "argocd"
}

# The walkthrough reaches the UI with kubectl port-forward. In production,
# use the Ingress host name, served with a trusted TLS certificate.
variable "argocd_url" {
  type    = string
  default = "https://localhost:8080"
}
