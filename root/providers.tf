# Real AWS when aws_endpoint_url is null: region and default tags come from
# the account JSON, and credentials come from the default chain (GitHub OIDC
# in CI). A non-null URL is the local Moto plan path. Dummy keys and the
# endpoints block exist only in that case, so an unset variable does not
# point the provider at localhost.
locals {
  moto_endpoint     = var.aws_endpoint_url
  gcp_mock_endpoint = var.gcp_endpoint_url
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
  # (`cloudwatchlogs` is an alias and must not be set as well). KMS covers
  # flow-log encryption. S3 is not used.
  dynamic "endpoints" {
    for_each = local.moto_endpoint != null ? [local.moto_endpoint] : []
    content {
      ec2  = endpoints.value
      iam  = endpoints.value
      sts  = endpoints.value
      logs = endpoints.value
      kms  = endpoints.value
    }
  }
}

# Real GCP when gcp_endpoint_url is null: project and region come from the
# project JSON, and credentials come from the environment (Application Default
# Credentials or GOOGLE_APPLICATION_CREDENTIALS in CI). A non-null URL is the
# local mock plan path. The dummy access token and compute_custom_endpoint
# exist only in that case, so an unset variable does not point Compute at the mock.
provider "google" {
  project = local.gcp_config.project_id
  region  = local.gcp_config.region

  access_token = local.gcp_mock_endpoint != null ? "testing" : null

  # hashicorp/google has no single API host. compute_custom_endpoint replaces
  # the Compute base URL for networks, subnets, routers, and Cloud NAT.
  # Provider init still calls the Google userinfo endpoint on googleapis.com
  # and continues if that request fails. This field does not redirect that call.
  compute_custom_endpoint = local.gcp_mock_endpoint != null ? local.gcp_mock_endpoint : null
}
