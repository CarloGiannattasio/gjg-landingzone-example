variable "name" {
  type        = string
  description = "Name prefix applied to the VPC and to the Name tag of every resource this module creates."
}

variable "tshirt_size" {
  type        = string
  description = "VPC t-shirt size. Small is 1 AZ with one NAT, Medium is 2 AZs with one shared NAT, and Large is 3 AZs with one NAT per AZ."

  validation {
    condition     = contains(["Small", "Medium", "Large"], var.tshirt_size)
    error_message = "tshirt_size must be one of Small, Medium, or Large."
  }
}

variable "cidr_block" {
  type        = string
  description = "IPv4 CIDR block for the VPC. Public subnets use netnums 0..AZ-1 and private subnets use netnums 10..10+AZ-1, each with an additional 8 prefix bits."

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR in dotted-decimal prefix form (for example, 10.10.0.0/16)."
  }
}

variable "delete_default_vpc" {
  type        = bool
  description = "Adopt the regional default VPC and set force_destroy so Terraform can delete it. CIS recommends removing the default VPC."
  default     = true
}

variable "enable_flow_logs" {
  type        = bool
  description = "Publish VPC flow logs for all traffic to a KMS-encrypted CloudWatch log group retained for 365 days."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Tags merged onto every taggable resource. Name tags set by this module take precedence."
  default     = {}
}
