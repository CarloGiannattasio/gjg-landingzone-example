output "role_name" {
  description = "Name of the IAM role."
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "ARN of the IAM role."
  value       = aws_iam_role.this.arn
}

output "policy_arn" {
  description = "ARN of the customer managed IAM policy attached to the role."
  value       = aws_iam_policy.custom.arn
}

output "policy_name" {
  description = "Name of the customer managed IAM policy attached to the role."
  value       = aws_iam_policy.custom.name
}
