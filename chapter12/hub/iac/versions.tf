# Identities for the self-managed Argo CD hub that runs on the Chapter 8 AKS
# cluster. Nothing here stores a secret: SSO uses Entra Workload ID, and the
# hub reaches EKS with a federated AWS role. Runs unchanged under OpenTofu.
terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

provider "azuread" {}

provider "aws" {
  region = var.aws_region
}
