data "azurerm_kubernetes_cluster" "hub" {
  name                = var.aks_cluster_name
  resource_group_name = var.resource_group_name
}

data "azuread_client_config" "current" {}

locals {
  # The AKS OIDC issuer, published because Chapter 8 set oidc_issuer_enabled.
  issuer = data.azurerm_kubernetes_cluster.hub.oidc_issuer_url

  # The three Argo CD components that talk to remote clusters.
  argocd_service_accounts = [
    "argocd-application-controller",
    "argocd-applicationset-controller",
    "argocd-server",
  ]
}

# -----------------------------------------------------------------------------
# 1. People: Entra ID single sign-on with no client secret
# -----------------------------------------------------------------------------
resource "azuread_application" "argocd" {
  display_name            = "argocd-gitops-ch12"
  owners                  = [data.azuread_client_config.current.object_id]
  sign_in_audience        = "AzureADMyOrg"
  group_membership_claims = ["SecurityGroup"]

  web {
    redirect_uris = ["${var.argocd_url}/auth/callback"]
  }

  # argocd login --sso
  public_client {
    redirect_uris = ["http://localhost:8085/auth/callback"]
  }

  optional_claims {
    id_token {
      name = "groups"
    }
  }

  # Microsoft Graph, delegated User.Read
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000"
    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d"
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "argocd" {
  client_id = azuread_application.argocd.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# argocd-server proves it is argocd-server with its projected token, so the
# OIDC client needs no secret at all.
resource "azuread_application_federated_identity_credential" "argocd_server" {
  application_id = azuread_application.argocd.id
  display_name   = "argocd-server-${var.aks_cluster_name}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = local.issuer
  subject        = "system:serviceaccount:${var.argocd_namespace}:argocd-server"
}

# -----------------------------------------------------------------------------
# 2. Reconciler: the AKS hub reaching EKS without an AWS access key
# -----------------------------------------------------------------------------
# AWS trusts the AKS issuer directly. The URL must match the iss claim of the
# projected token exactly; AKS issuer URLs end with a slash, so keep it.
resource "aws_iam_openid_connect_provider" "aks_hub" {
  url            = local.issuer
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  issuer_hostpath = trimprefix(local.issuer, "https://")
}

data "aws_iam_policy_document" "argocd_hub_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.aks_hub.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.issuer_hostpath}:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Only these three service accounts, in this namespace, on this cluster.
    condition {
      test     = "StringEquals"
      variable = "${local.issuer_hostpath}:sub"
      values   = [for sa in local.argocd_service_accounts : "system:serviceaccount:${var.argocd_namespace}:${sa}"]
    }
  }
}

# No IAM policy is attached: the role only has to prove its identity to the
# EKS API server. What it may do inside the cluster is Kubernetes RBAC.
resource "aws_iam_role" "argocd_hub" {
  name               = "argocd-hub-${var.aks_cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.argocd_hub_trust.json
}

# Map the role to the Kubernetes group 'argocd-hub'. spoke-bootstrap/ binds
# that group to read-everything-plus-impersonate, not to cluster-admin.
resource "aws_eks_access_entry" "argocd_hub" {
  cluster_name      = var.eks_cluster_name
  principal_arn     = aws_iam_role.argocd_hub.arn
  kubernetes_groups = ["argocd-hub"]
  type              = "STANDARD"
}
