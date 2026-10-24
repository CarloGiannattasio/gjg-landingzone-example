variable "name" {
  type        = string
  description = "Name prefix for the VPC network, firewall, subnets, Cloud Routers, and Cloud NAT."
}

variable "tshirt_size" {
  type        = string
  description = "VPC t-shirt size. Small is 1 zone with one Cloud NAT, Medium is 2 zones with one shared Cloud NAT, and Large is 3 zones with one Cloud NAT per zone."

  validation {
    condition     = contains(["Small", "Medium", "Large"], var.tshirt_size)
    error_message = "tshirt_size must be one of Small, Medium, or Large."
  }
}

variable "cidr_block" {
  type        = string
  description = "IPv4 CIDR used to carve subnet ranges. The VPC network resource has no CIDR. Public subnets use netnums 0..zone-1 and private subnets use netnums 10..10+zone-1, each with an additional 8 prefix bits."

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR in dotted-decimal prefix form (for example, 10.10.0.0/16)."
  }
}

variable "region" {
  type        = string
  description = "GCP region for subnets, Cloud Routers, and Cloud NAT (for example, us-central1). Zones are pinned to this region plus -a, -b, and -c."
}

variable "project_id" {
  type        = string
  description = "GCP project ID that owns the VPC network, firewall, subnets, Cloud Routers, and Cloud NAT."
}

variable "enable_flow_logs" {
  type        = bool
  description = "Enable VPC flow logs on every public and private subnet. Logs aggregate every 5 seconds, sample half of the flows, and include all metadata."
  default     = false
}
