variable "environment" {
  description = "Environment name."
  type        = string
}

# The four variables below are not chosen by a human. They arrive from the
# network module's outputs, by way of a Kubernetes Secret. This is the seam
# where dependency management at the GitOps level replaces a Terraform remote
# state data source.

variable "resource_group_name" {
  description = "Resource group created by the network module."
  type        = string
}

variable "location" {
  description = "Region the network module used."
  type        = string
}

variable "vnet_id" {
  description = "Virtual network the private DNS zone is linked to."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet the storage private endpoint is placed in."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource in the module."
  type        = map(string)
  default     = {}
}
