# Shared backend settings for the staging roots. The key is deliberately absent:
# each root passes its own with -backend-config="key=staging/<root>.tfstate".
#
# No use_oidc here. CI sets ARM_USE_OIDC=true in the environment; a local run
# authenticates with your Azure CLI session instead.
resource_group_name  = "gitops-tfstate-rg"
storage_account_name = "<tfstate-storage-account>"
container_name       = "tfstate"
use_azuread_auth     = true
