# -----------------------------------------------------------------------------
# Amazon EKS Capabilities
#
# Announced 30 November 2025 and available in all commercial regions. Three
# capabilities ship today: ARGOCD (managed GitOps), ACK (AWS resources as
# Kubernetes objects) and KRO (resource composition). AWS runs the Argo CD
# control plane outside the cluster and handles scaling, upgrades, high
# availability, SSO and ECR token refresh.
#
# Identity Center is the only supported SSO provider, so its instance is a
# prerequisite. The configuration references the instance by ARN and exposes
# its region (idc_region) separately from the cluster's; keep the two aligned
# unless you have a specific reason not to.
# -----------------------------------------------------------------------------

data "aws_ssoadmin_instances" "this" {}

# Group whose members receive Argo CD ADMIN. Change the DisplayName to a group
# that exists in your Identity Center directory.
data "aws_identitystore_group" "platform_admins" {
  identity_store_id = one(data.aws_ssoadmin_instances.this.identity_store_ids)

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = var.idc_admin_group_display_name
    }
  }
}

module "argocd_capability" {
  source  = "terraform-aws-modules/eks/aws//modules/capability"
  version = "~> 21.0"

  type         = "ARGOCD"
  cluster_name = module.eks.cluster_name

  configuration = {
    argo_cd = {
      aws_idc = {
        idc_instance_arn = one(data.aws_ssoadmin_instances.this.arns)
      }

      # The capability's primary namespace. AppProjects must live here.
      # Applications and ApplicationSets use it by default, but additional
      # namespaces can be enabled (application.namespaces and
      # applicationsetcontroller.namespaces in argocd-cmd-params-cm, permitted
      # by the AppProject's spec.sourceNamespaces).
      namespace = var.argocd_namespace

      # Global role mapping accepts three roles only: ADMIN, EDITOR, VIEWER.
      # Finer-grained access comes from AppProject roles and policies; EDITOR
      # and VIEWER users need project roles to see Applications. Third-party
      # SSO providers are not supported.
      rbac_role_mapping = [{
        role = "ADMIN"
        identity = [{
          id   = data.aws_identitystore_group.platform_admins.group_id
          type = "SSO_GROUP"
        }]
      }]
    }
  }

  # Permissions the AWS-managed control plane assumes on your behalf. Pulling
  # Helm charts or images from ECR needs read access; token refresh is handled
  # by AWS, so nothing is stored in the cluster.
  iam_policy_statements = {
    ECRRead = {
      actions = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:DescribeImages",
      ]
      resources = ["*"]
    }
  }

  tags = var.tags
}

# ACK lets the cluster manage AWS resources declaratively from the same Git
# repository as the workloads, without installing or upgrading controllers.
# This is the AWS answer to "infrastructure in the same reconciliation loop".
module "ack_capability" {
  source  = "terraform-aws-modules/eks/aws//modules/capability"
  version = "~> 21.0"

  count = var.enable_ack_capability ? 1 : 0

  type         = "ACK"
  cluster_name = module.eks.cluster_name

  # Grant only the services you intend to manage from Git. AdministratorAccess
  # appears in the upstream example for brevity; it is not a recommendation.
  iam_policy_statements = {
    S3Manage = {
      actions   = ["s3:CreateBucket", "s3:DeleteBucket", "s3:List*", "s3:Get*", "s3:PutBucket*"]
      resources = ["*"]
    }
  }

  tags = var.tags
}
