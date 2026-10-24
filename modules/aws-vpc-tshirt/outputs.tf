output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "IPv4 CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, in availability zone order."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, in availability zone order."
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways. Small and Medium have one; Large has one per availability zone."
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_count" {
  description = "Number of NAT gateways for the selected t-shirt size."
  value       = local.nat_gateway_count
}

output "availability_zone_count" {
  description = "Number of availability zones for the selected t-shirt size."
  value       = local.availability_zone_count
}

output "tshirt_size" {
  description = "Selected t-shirt size."
  value       = var.tshirt_size
}
