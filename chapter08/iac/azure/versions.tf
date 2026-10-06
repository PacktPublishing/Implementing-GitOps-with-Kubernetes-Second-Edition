# Chapter 8 keeps infrastructure code deliberately thin: it exists only to stand up
# the two managed clusters. Terraform and OpenTofu patterns are the subject of Chapter 9.
#
# Every configuration in this folder runs unchanged under OpenTofu:
#   tofu init && tofu plan -out azureplan && tofu apply azureplan

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  # Required since azurerm v4.0. Export ARM_SUBSCRIPTION_ID or set -var subscription_id.
  subscription_id = var.subscription_id

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
