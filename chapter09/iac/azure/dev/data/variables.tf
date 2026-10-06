variable "resource_group_name" {
  description = "Injected from the network module's outputs Secret."
  type        = string
}

variable "location" {
  description = "Injected from the network module's outputs Secret."
  type        = string
}

variable "vnet_id" {
  description = "Injected from the network module's outputs Secret."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Injected from the network module's outputs Secret."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    book    = "Implementing GitOps with Kubernetes, 2nd Edition"
    chapter = "09"
  }
}
