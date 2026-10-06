variable "location" {
  description = "Azure region for this environment."
  type        = string
  default     = "switzerlandnorth"
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    book    = "Implementing GitOps with Kubernetes, 2nd Edition"
    chapter = "09"
  }
}
