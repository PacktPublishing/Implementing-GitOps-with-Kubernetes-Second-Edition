# -----------------------------------------------------------------------------
# Optional: the identity the pull request gate uses.
#
# CI plans the staging and production roots against their real state, so that a
# change that would destroy something shows up as a deletion rather than as a
# create against an empty state. That needs read access to the state container
# and, because the workflow plans with -refresh=false, nothing else: no role on
# the resources themselves, and no write access anywhere.
#
# It is a separate identity from the runner's on purpose. The runner has
# Contributor; the pull request gate must not. Its OIDC trust is limited to one
# repository and one protected GitHub environment (var.ci_environment), so only
# an approved plan job can use it.
#
# Created only when github_repository is set, e.g. "my-org/my-fork".
# -----------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "ci" {
  count = var.github_repository == null ? 0 : 1

  name                = "gitops-iac-ci"
  resource_group_name = azurerm_resource_group.bootstrap.name
  location            = azurerm_resource_group.bootstrap.location
}

locals {
  # When the repository has immutable OIDC subject claims enabled, GitHub
  # replaces "owner/repo" with "owner@ownerId/repo@repoId" in the token it
  # presents, so the federated credential subject must be built from that
  # exact prefix instead of the plain repository name.
  #
  # The conditional (rather than a bare coalesce) matters because
  # github_repository defaults to null here: coalesce still evaluates every
  # argument eagerly, so interpolating a null var.github_repository would
  # fail even when this local is never used (github_repository unset).
  github_oidc_subject_prefix = (
    var.github_repository == null ? null :
    coalesce(var.github_oidc_subject_prefix, "repo:${var.github_repository}")
  )
}

# Trust only the protected GitHub environment the plan job runs in. A job that
# declares `environment:` presents the subject
# repo:<owner>/<repo>:environment:<name>, so this credential cannot be used by
# an ungated pull_request job, which presents repo:<owner>/<repo>:pull_request.
# The environment's required reviewers are what release a plan against real
# production state. Pull requests from forks get no OIDC token at all.
resource "azurerm_federated_identity_credential" "ci_plan_environment" {
  count = var.github_repository == null ? 0 : 1

  name                      = "github-env-${var.ci_environment}"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${local.github_oidc_subject_prefix}:environment:${var.ci_environment}"
}

resource "azurerm_role_assignment" "ci_state_reader" {
  count = var.github_repository == null ? 0 : 1

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.ci[0].principal_id
}
