locals {
  aws_config = jsondecode(file(abspath("${path.module}/${var.config_path}")))

  gcp_config = jsondecode(file(abspath("${path.module}/${var.gcp_config_path}")))

  aws_environments = ["prod", "nonprod", "preprod"]
  tshirt_sizes     = ["Small", "Medium", "Large"]

  gcp_required_keys = [
    "project_id",
    "environment",
    "business_unit",
    "region",
    "cost_center",
    "mandatory_tags",
    "vpc",
  ]

  gcp_vpc_required_keys = ["name", "cidr_block", "tshirt_size"]
}

resource "terraform_data" "config_contract" {
  lifecycle {
    precondition {
      condition     = try(local.aws_config.business_unit, null) == "example"
      error_message = "AWS account config business_unit must be \"example\"."
    }

    precondition {
      condition     = contains(local.aws_environments, try(local.aws_config.environment, ""))
      error_message = "AWS account config environment must be one of: prod, nonprod, preprod."
    }

    precondition {
      condition     = contains(local.tshirt_sizes, try(local.aws_config.vpc.tshirt_size, ""))
      error_message = "AWS account config vpc.tshirt_size must be one of: Small, Medium, Large."
    }

    precondition {
      condition = (
        alltrue([
          for key in local.gcp_required_keys : contains(try(keys(local.gcp_config), []), key)
        ])
        && (
          contains(try(keys(local.gcp_config), []), "account_name")
          || contains(try(keys(local.gcp_config), []), "project_name")
        )
        && alltrue([
          for key in local.gcp_vpc_required_keys : contains(try(keys(try(local.gcp_config.vpc, {})), []), key)
        ])
      )
      error_message = "GCP config must include account_name (or project_name), project_id, environment, business_unit, region, cost_center, mandatory_tags, and vpc.name, vpc.cidr_block, and vpc.tshirt_size."
    }
  }
}

module "vpc" {
  source = "../modules/aws-vpc-tshirt"

  name               = local.aws_config.vpc.name
  tshirt_size        = local.aws_config.vpc.tshirt_size
  cidr_block         = local.aws_config.vpc.cidr_block
  delete_default_vpc = local.aws_config.vpc.delete_default_vpc
  enable_flow_logs   = local.aws_config.vpc.enable_flow_logs
  tags               = local.aws_config.mandatory_tags
}

module "gcp_vpc" {
  source = "../modules/gcp-vpc-tshirt"

  name             = local.gcp_config.vpc.name
  tshirt_size      = local.gcp_config.vpc.tshirt_size
  cidr_block       = local.gcp_config.vpc.cidr_block
  region           = local.gcp_config.region
  project_id       = local.gcp_config.project_id
  enable_flow_logs = try(local.gcp_config.vpc.enable_flow_logs, false)
}

module "iam_roles" {
  source   = "../modules/aws-iam-role"
  for_each = { for r in local.aws_config.iam_roles : r.name => r }

  role_name              = each.value.name
  trust_policy_path      = abspath("${path.module}/../policies/iam-trust/${each.value.trust_policy}")
  permission_policy_path = abspath("${path.module}/../policies/iam-permissions/${each.value.permission_policy}")
  tags                   = local.aws_config.mandatory_tags
}
