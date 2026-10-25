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

# No static credentials anywhere in this block. The runner pod receives a
# federated token from the AKS OIDC issuer and exchanges it for an Entra
# token; ARM_USE_OIDC and ARM_OIDC_TOKEN_FILE_PATH are set on the runner pod
# by the Terraform custom resource.
provider "azurerm" {
  use_oidc = true

  resource_provider_registrations = "none"

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
