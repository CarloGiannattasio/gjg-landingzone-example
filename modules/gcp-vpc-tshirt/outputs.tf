output "vpc_cidr" {
  description = "IPv4 CIDR used to carve subnet ranges. The network resource has no CIDR, so this echoes cidr_block."
  value       = var.cidr_block
}

output "tshirt_size" {
  description = "Selected t-shirt size."
  value       = var.tshirt_size
}

output "availability_zone_count" {
  description = "Number of zones for the selected t-shirt size."
  value       = local.availability_zone_count
}

output "nat_gateway_count" {
  description = "Number of Cloud NAT gateways for the selected t-shirt size. Small and Medium have one shared NAT; Large has one per zone."
  value       = local.nat_gateway_count
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, in zone order."
  value       = google_compute_subnetwork.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, in zone order."
  value       = google_compute_subnetwork.private[*].id
}

output "network_id" {
  description = "ID of the custom-mode VPC network."
  value       = google_compute_network.this.id
}

output "network_name" {
  description = "Name of the custom-mode VPC network."
  value       = google_compute_network.this.name
}
