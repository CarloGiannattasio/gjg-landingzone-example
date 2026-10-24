mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }
}

run "small" {
  command = plan

  module {
    source = "./modules/aws-vpc-tshirt"
  }

  variables {
    name               = "example"
    tshirt_size        = "Small"
    cidr_block         = "10.10.0.0/16"
    delete_default_vpc = true
    enable_flow_logs   = false
    tags = {
      BusinessUnit = "example"
    }
  }

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  assert {
    condition     = output.vpc_cidr == "10.10.0.0/16"
    error_message = "CIDR mismatch: expected output.vpc_cidr to be 10.10.0.0/16, got ${output.vpc_cidr}."
  }

  assert {
    condition     = output.tshirt_size == "Small"
    error_message = "tshirt_size mismatch: expected Small, got ${output.tshirt_size}."
  }

  assert {
    condition     = output.availability_zone_count == 1
    error_message = "availability_zone_count mismatch: expected 1 for Small, got ${output.availability_zone_count}."
  }

  assert {
    condition     = output.nat_gateway_count == 1
    error_message = "nat_gateway_count mismatch: expected 1 for Small, got ${output.nat_gateway_count}."
  }

  assert {
    condition     = length(output.public_subnet_ids) == 1
    error_message = "public subnet count mismatch: expected 1 for Small, got ${length(output.public_subnet_ids)}."
  }

  assert {
    condition     = length(output.private_subnet_ids) == 1
    error_message = "private subnet count mismatch: expected 1 for Small, got ${length(output.private_subnet_ids)}."
  }

  assert {
    condition     = length(aws_default_vpc.this) == 1 && aws_default_vpc.this[0].force_destroy == true
    error_message = "Expected aws_default_vpc.this to adopt the default VPC with force_destroy so destroy deletes it (CIS: remove the default VPC)."
  }
}

run "medium" {
  command = plan

  module {
    source = "./modules/aws-vpc-tshirt"
  }

  variables {
    name               = "example"
    tshirt_size        = "Medium"
    cidr_block         = "10.30.0.0/16"
    delete_default_vpc = true
    enable_flow_logs   = false
    tags = {
      BusinessUnit = "example"
    }
  }

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  assert {
    condition     = output.vpc_cidr == "10.30.0.0/16"
    error_message = "CIDR mismatch: expected output.vpc_cidr to be 10.30.0.0/16, got ${output.vpc_cidr}."
  }

  assert {
    condition     = output.availability_zone_count == 2
    error_message = "availability_zone_count mismatch: expected 2 for Medium, got ${output.availability_zone_count}."
  }

  assert {
    condition     = output.nat_gateway_count == 1
    error_message = "nat_gateway_count mismatch: expected 1 for Medium, got ${output.nat_gateway_count}."
  }

  assert {
    condition     = length(output.public_subnet_ids) == 2
    error_message = "public subnet count mismatch: expected 2 for Medium, got ${length(output.public_subnet_ids)}."
  }

  assert {
    condition     = length(output.private_subnet_ids) == 2
    error_message = "private subnet count mismatch: expected 2 for Medium, got ${length(output.private_subnet_ids)}."
  }
}

run "large" {
  command = plan

  module {
    source = "./modules/aws-vpc-tshirt"
  }

  variables {
    name               = "example"
    tshirt_size        = "Large"
    cidr_block         = "10.40.0.0/16"
    delete_default_vpc = true
    enable_flow_logs   = true
    tags = {
      BusinessUnit = "example"
    }
  }

  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  assert {
    condition     = output.vpc_cidr == "10.40.0.0/16"
    error_message = "CIDR mismatch: expected output.vpc_cidr to be 10.40.0.0/16, got ${output.vpc_cidr}."
  }

  assert {
    condition     = output.availability_zone_count == 3
    error_message = "availability_zone_count mismatch: expected 3 for Large, got ${output.availability_zone_count}."
  }

  assert {
    condition     = output.nat_gateway_count == 3
    error_message = "nat_gateway_count mismatch: expected 3 for Large, got ${output.nat_gateway_count}."
  }

  assert {
    condition     = length(output.public_subnet_ids) == 3
    error_message = "public subnet count mismatch: expected 3 for Large, got ${length(output.public_subnet_ids)}."
  }

  assert {
    condition     = length(output.private_subnet_ids) == 3
    error_message = "private subnet count mismatch: expected 3 for Large, got ${length(output.private_subnet_ids)}."
  }
}
