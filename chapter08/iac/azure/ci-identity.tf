# -----------------------------------------------------------------------------
# Keyless CI: a user-assigned managed identity that GitHub Actions federates into
#
# The first edition stored an Azure DevOps service-connection GUID and a registry
# credential. Here there is no secret at all: GitHub presents a short-lived OIDC
# token, Entra validates it against the federated credential subject, and the
# workflow receives an access token scoped to AcrPush.
# -----------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "ci" {
  name                = "id-${var.cluster_name}-ci"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = var.tags
}

resource "azurerm_role_assignment" "ci_acr_push" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPush"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
}

locals {
  # When the repository has immutable OIDC subject claims enabled, GitHub
  # replaces "owner/repo" with "owner@ownerId/repo@repoId" in the token it
  # presents, so the federated credential subject must be built from that
  # exact prefix instead of the plain repository name.
  github_oidc_subject_prefix = coalesce(var.github_oidc_subject_prefix, "repo:${var.github_repository}")
}

# One federated credential per trusted GitHub context. The subject is matched
# exactly, so a workflow running on another branch cannot obtain this token.
resource "azurerm_federated_identity_credential" "github_main" {
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${local.github_oidc_subject_prefix}:ref:refs/heads/${var.gitops_branch}"
}

resource "azurerm_federated_identity_credential" "github_pr" {
  name                      = "github-pull-request"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${local.github_oidc_subject_prefix}:pull_request"
}
