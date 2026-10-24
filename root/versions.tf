terraform {
  required_version = ">= 1.5.0"

  # A real landing zone would use an S3 + DynamoDB backend per account.
  # This example omits the backend block and keeps state local.

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
