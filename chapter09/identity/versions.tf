# -----------------------------------------------------------------------------
# Bootstrap identity
#
# This configuration is applied once, from a terminal, before the controller
# exists. It is the honest answer to the bootstrap problem: something has to
# create the identity the runner inside the cluster will later use, and that
# something cannot itself be that runner.
#
#   tofu init && tofu plan -out bootstrap && tofu apply bootstrap
#
# Keep it small, keep it separate, and keep its state somewhere durable.
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  use_oidc        = false

  # azurerm 5.0 changed the default from "legacy" to "none", so a fresh
  # subscription no longer registers resource providers on demand. The
  # bootstrap step is the right place to do it once.
  resource_provider_registrations = "legacy"

  features {}
}

data "azurerm_subscription" "current" {}
