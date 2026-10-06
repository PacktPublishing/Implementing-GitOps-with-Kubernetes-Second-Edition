# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  # EKS requires subnets in at least two availability zones.
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.0.0/19", "10.0.32.0/19"]
  public_subnets  = ["10.0.64.0/19", "10.0.96.0/19"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Subnet discovery tags for the AWS Load Balancer Controller.
  public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Container registry
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "app" {
  name = "weather-app"

  # IMMUTABLE is the GitOps-correct choice: a tag always refers to the same image,
  # so what Git records is what runs. The first edition used MUTABLE with :latest.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# EKS cluster
#
# api_and_config_map is avoided: access is granted purely through EKS access
# entries, which is also what the Argo CD capability uses to reach the cluster.
# -----------------------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  # Pod Identity is the successor to IRSA: an agent on the node brokers
  # credentials, so no OIDC trust policy per role and no service-account
  # annotation plumbing. See identity.tf.
  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    aws-ebs-csi-driver     = {}
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.instance_types
      min_size       = 2
      max_size       = 4
      desired_size   = 2
    }
  }

  tags = var.tags
}
