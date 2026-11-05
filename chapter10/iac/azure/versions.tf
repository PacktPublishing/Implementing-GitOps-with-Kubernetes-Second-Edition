# Chapter 10 stands up a small but realistic estate: one management cluster and
# two workload clusters (non-production and production). Infrastructure as code
# is the subject of Chapter 9; this folder is deliberately plain and runs
# unchanged under OpenTofu or Terraform:
#   tofu init && tofu plan -out ch10.plan && tofu apply ch10.plan

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"   # rbac_authorization_enabled, workload_autoscaler_profile
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}
