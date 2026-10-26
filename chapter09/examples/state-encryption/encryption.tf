# OpenTofu state and plan encryption with an Azure Key Vault key.
#
# Copy this file into a root -- iac/azure/prod/network, for instance -- once
# the bootstrap has been applied with enable_state_encryption = true. It is an
# OpenTofu feature: Terraform does not read the encryption block. Requires
# OpenTofu 1.11 or later, which is the release that added azure_vault.
#
# Read examples/state-encryption/README.md before enabling it on a root that
# already has state. The migration block below is not optional in that case.

# Encryption settings are evaluated during `tofu init`, before any state is
# read, so they must come from literals, locals or variables that are known at
# that point. A vault URI is an identifier, not a secret: setting it as the
# default here is the simplest thing that works for every caller (the runner,
# CI and a local cleanup) without extra plumbing.
variable "key_vault_uri" {
  description = "tofu -chdir=chapter09/identity output -raw state_key_vault_uri"
  type        = string
  default     = "https://REPLACE_WITH_YOUR_VAULT.vault.azure.net"
}

variable "state_key_name" {
  description = "tofu -chdir=chapter09/identity output -raw state_key_name"
  type        = string
  default     = "tfstate-prod"
}

terraform {
  encryption {
    # Authentication follows the azurerm backend: in the runner pod that is
    # AKS workload identity (ARM_USE_AKS_WORKLOAD_IDENTITY), locally it is
    # your Azure CLI session. The identity needs keys/read, wrap and unwrap
    # on the key ("Key Vault Crypto Service Encryption User").
    key_provider "azure_vault" "primary" {
      vault_uri      = var.key_vault_uri
      vault_key_name = var.state_key_name
      key_length     = 32
    }

    method "aes_gcm" "default" {
      keys = key_provider.azure_vault.primary
    }

    # Only needed while an existing unencrypted state is being migrated.
    # Remove it, and the fallback blocks, after the first successful apply.
    method "unencrypted" "migrate" {}

    state {
      method = method.aes_gcm.default

      fallback {
        method = method.unencrypted.migrate
      }
    }

    # The saved plan carries the same sensitive values as the state, and
    # Tofu Controller keeps it in a Secret between plan and apply. Encrypt it
    # too.
    plan {
      method = method.aes_gcm.default

      fallback {
        method = method.unencrypted.migrate
      }
    }
  }
}
