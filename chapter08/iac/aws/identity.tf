# -----------------------------------------------------------------------------
# Workload identity on EKS
#
# Nodes pull from ECR through the node role. Workloads that need AWS APIs use
# EKS Pod Identity associations, which replace the IRSA pattern of annotating a
# service account with a role ARN and maintaining an OIDC trust policy.
# -----------------------------------------------------------------------------

# Read-only ECR access for the sample application's service account, shown here
# as the canonical Pod Identity example.
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

resource "aws_iam_role" "weather_app" {
  name               = "${var.cluster_name}-weather-app"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "weather_app_ecr_read" {
  role       = aws_iam_role.weather_app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_pod_identity_association" "weather_app" {
  cluster_name    = module.eks.cluster_name
  namespace       = "weather-app"
  service_account = "weather-app"
  role_arn        = aws_iam_role.weather_app.arn
  tags            = var.tags
}

# -----------------------------------------------------------------------------
# Keyless CI: a role GitHub Actions assumes via OIDC to push to ECR
# -----------------------------------------------------------------------------

data "aws_iam_openid_connect_provider" "github" {
  # Create once per account:
  #   aws iam create-open-id-connect-provider \
  #     --url https://token.actions.githubusercontent.com \
  #     --client-id-list sts.amazonaws.com
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scope the trust to the trusted publishing branch. A wildcard on the whole
    # repository (repo:owner/repo:*) would let any ref mint registry credentials.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:ref:refs/heads/${var.gitops_branch}",
        # Give pull-request validation a separate, least-privileged role.
      ]
    }
  }
}

# -----------------------------------------------------------------------------
# Pull-request validation: a SEPARATE role with no ECR push rights
#
# The pull_request subject is deliberately absent from the publishing role
# above. This role has no policy attached; grant it only what your
# pull-request checks need, and never ecr:PutImage.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "github_pr_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:pull_request"]
    }
  }
}

resource "aws_iam_role" "github_ci_pr" {
  name               = "${var.cluster_name}-github-ci-pr"
  assume_role_policy = data.aws_iam_policy_document.github_pr_trust.json
  tags               = var.tags
}

resource "aws_iam_role" "github_ci" {
  name               = "${var.cluster_name}-github-ci"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
  tags               = var.tags
}

data "aws_iam_policy_document" "ecr_push" {
  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:DescribeImages",
    ]
    resources = [aws_ecr_repository.app.arn]
  }
}

resource "aws_iam_policy" "ecr_push" {
  name   = "${var.cluster_name}-ecr-push"
  policy = data.aws_iam_policy_document.ecr_push.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "github_ci_ecr_push" {
  role       = aws_iam_role.github_ci.name
  policy_arn = aws_iam_policy.ecr_push.arn
}
