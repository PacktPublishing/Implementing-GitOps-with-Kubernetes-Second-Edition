variable "subscription_id" { type = string }
variable "tenant_id" { type = string }

variable "resource_group_name" {
  type    = string
  default = "gitops-ch08-rg"
}

variable "cluster_name" {
  type    = string
  default = "aks-gitops-ch08"
}

variable "key_vault_name" {
  type    = string
  default = "kv-gitops-ch12"
}

variable "app_namespace" {
  type    = string
  default = "weather-app"
}
