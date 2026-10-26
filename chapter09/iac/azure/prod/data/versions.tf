terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}

# No static credentials anywhere in this block. In the runner pod the
# Terraform custom resource sets ARM_USE_AKS_WORKLOAD_IDENTITY, and the AKS
# webhook injects the client ID, tenant ID and federated token file from the
# annotated service account. In CI, ARM_USE_OIDC uses the GitHub OIDC token.
provider "azurerm" {
  use_oidc = true

  resource_provider_registrations = "none"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
