output "account_name" {
  description = "AWS account name from the selected account config."
  value       = local.aws_config.account_name
}

output "environment" {
  description = "Environment of the selected AWS account."
  value       = local.aws_config.environment
}

output "business_unit" {
  description = "Business unit that owns the selected AWS account."
  value       = local.aws_config.business_unit
}

output "region" {
  description = "AWS region from the selected account config."
  value       = local.aws_config.region
}

output "vpc_id" {
  description = "ID of the account VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the account VPC."
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_count" {
  description = "Number of NAT gateways created for the selected T-shirt size."
  value       = module.vpc.nat_gateway_count
}

output "tshirt_size" {
  description = "T-shirt size applied to the account VPC."
  value       = module.vpc.tshirt_size
}

output "iam_role_arns" {
  description = "Map of IAM role name to role ARN."
  value       = { for name, role in module.iam_roles : name => role.role_arn }
}

output "gcp_project_id" {
  description = "GCP project id from the decoded multi-cloud config. No GCP resources are created."
  value       = local.gcp_config.project_id
}

output "gcp_environment" {
  description = "GCP environment from the decoded multi-cloud config. No GCP resources are created."
  value       = local.gcp_config.environment
}
