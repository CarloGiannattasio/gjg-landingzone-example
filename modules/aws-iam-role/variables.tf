variable "role_name" {
  description = "Name of the IAM role. The attached customer managed policy is named <role_name>-policy."
  type        = string
}

variable "trust_policy_path" {
  description = "Filesystem path to the IAM trust (assume-role) policy JSON document. The document is loaded with file() and is not inlined."
  type        = string
}

variable "permission_policy_path" {
  description = "Filesystem path to the IAM permissions policy JSON document. The document is loaded with file() and is not inlined."
  type        = string
}

variable "tags" {
  description = "Tags applied to the IAM role and the customer managed policy."
  type        = map(string)
  default     = {}
}
