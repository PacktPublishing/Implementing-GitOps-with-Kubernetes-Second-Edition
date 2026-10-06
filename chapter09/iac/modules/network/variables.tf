variable "environment" {
  description = "Environment name. Becomes part of every resource name."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of dev, staging or prod."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "switzerlandnorth"
}

variable "address_space" {
  description = "Virtual network address space. Non-overlapping across environments."
  type        = list(string)
}

variable "workload_subnet_prefix" {
  description = "Address prefix of the workload subnet."
  type        = string
}

variable "private_endpoint_subnet_prefix" {
  description = "Address prefix of the subnet holding private endpoints."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource in the module."
  type        = map(string)
  default     = {}
}
