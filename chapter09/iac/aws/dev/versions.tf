# The AWS half of the chapter is deliberately small: it exists to show that
# only the identity wiring changes when the same pattern moves to EKS.

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# No credentials in the provider block. On EKS the runner pod's service
# account is annotated with an IAM role ARN and the SDK picks up the
# projected web identity token automatically.
provider "aws" {
  region = var.region
}
