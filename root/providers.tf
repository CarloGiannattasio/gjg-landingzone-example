# Real AWS when aws_endpoint_url is null: region and default tags come from
# the account JSON, and credentials come from the default chain (GitHub OIDC
# in CI). A non-null URL is the local Moto plan path. Dummy keys and the
# endpoints block exist only in that case, so an unset variable does not
# point the provider at localhost.
locals {
  moto_endpoint = var.aws_endpoint_url
}

provider "aws" {
  region = local.aws_config.region

  access_key                  = local.moto_endpoint != null ? "testing" : null
  secret_key                  = local.moto_endpoint != null ? "testing" : null
  skip_credentials_validation = local.moto_endpoint != null ? true : null
  skip_metadata_api_check     = local.moto_endpoint != null ? true : null
  skip_requesting_account_id  = local.moto_endpoint != null ? true : null

  default_tags {
    tags = local.aws_config.mandatory_tags
  }

  # hashicorp/aws 6.70 endpoints block. CloudWatch Logs is `logs`
  # (`cloudwatchlogs` is an alias and must not be set as well). S3 is not used.
  dynamic "endpoints" {
    for_each = local.moto_endpoint != null ? [local.moto_endpoint] : []
    content {
      ec2  = endpoints.value
      iam  = endpoints.value
      sts  = endpoints.value
      logs = endpoints.value
    }
  }
}
