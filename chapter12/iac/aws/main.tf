# 1. The controller identity: EKS Pod Identity on the ESO service account.
data "aws_iam_policy_document" "pod_identity_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso_controller" {
  name               = "${var.cluster_name}-eso-controller"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# The controller role can do exactly one thing: assume tenant roles.
data "aws_iam_policy_document" "eso_controller" {
  statement {
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = [aws_iam_role.tenant.arn]
  }
}

resource "aws_iam_role_policy" "eso_controller" {
  role   = aws_iam_role.eso_controller.id
  policy = data.aws_iam_policy_document.eso_controller.json
}

resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = var.cluster_name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = aws_iam_role.eso_controller.arn
}

# 2. The tenant role, assumed per SecretStore with session tags.
data "aws_iam_policy_document" "tenant_trust" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.eso_controller.arn]
    }
  }
}

resource "aws_iam_role" "tenant" {
  name               = "${var.cluster_name}-${var.app_namespace}-secrets"
  assume_role_policy = data.aws_iam_policy_document.tenant_trust.json
}

# ABAC: a store in namespace X may only read secrets tagged namespace=X.
data "aws_iam_policy_document" "tenant" {
  statement {
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = ["arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:*"]
    condition {
      test     = "StringEquals"
      variable = "secretsmanager:ResourceTag/namespace"
      values   = ["$${aws:PrincipalTag/esoNamespace}"]
    }
  }
}

resource "aws_iam_role_policy" "tenant" {
  role   = aws_iam_role.tenant.id
  policy = data.aws_iam_policy_document.tenant.json
}

# Secret VALUES are created out of band so they never reach Terraform state:
#   aws secretsmanager create-secret --name weather-app-db \
#     --secret-string "$(openssl rand -base64 24)" \
#     --tags Key=namespace,Value=weather-app
