# Partial backend configuration. The settings are supplied at init time:
#
#   In the cluster, Tofu Controller writes spec.backendConfig.customConfiguration
#   to backend_override.tf, and an override file replaces this block.
#
#   In CI and for a local cleanup:
#     tofu init -backend-config=../backend.hcl -backend-config="key=staging/data.tfstate"
#
# The key must match the one in terraform/staging-data.yaml exactly. Pointing
# this root at another root's key would make the next plan propose to destroy
# everything that root created.
terraform {
  backend "azurerm" {}
}
