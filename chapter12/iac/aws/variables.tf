variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "cluster_name" {
  type    = string
  default = "eks-gitops-ch08"
}

variable "app_namespace" {
  type    = string
  default = "weather-app"
}
