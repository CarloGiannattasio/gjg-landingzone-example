# T-shirt VPC for the example business unit.
#
# Small:  1 AZ, 1 public subnet, 1 private subnet, 1 NAT gateway.
# Medium: 2 AZs, 2 public subnets, 2 private subnets, 1 shared NAT gateway.
# Large:  3 AZs, 3 public subnets, 3 private subnets, 1 NAT gateway per AZ.
#
# Subnet CIDRs use cidrsubnet(var.cidr_block, 8, netnum):
#   public  netnums 0 .. az_count-1
#   private netnums 10 .. 10+az_count-1

# Zone names are pinned so a new AZ in the region cannot enter the set
# (CKV_AWS_394). Every AWS account file in this example is us-east-1.
# Small and Medium use a prefix of this list; Large uses all three.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name = "zone-name"
    values = [
      "us-east-1a",
      "us-east-1b",
      "us-east-1c",
    ]
  }
}

locals {
  # AZ count is derived from t-shirt size. It is intentionally not a variable.
  tshirt_sizes = {
    Small = {
      availability_zone_count = 1
      nat_gateway_count       = 1
    }
    Medium = {
      availability_zone_count = 2
      nat_gateway_count       = 1
    }
    Large = {
      availability_zone_count = 3
      nat_gateway_count       = 3
    }
  }

  selected                = local.tshirt_sizes[var.tshirt_size]
  availability_zone_count = local.selected.availability_zone_count
  nat_gateway_count       = local.selected.nat_gateway_count
  availability_zones      = slice(data.aws_availability_zones.available.names, 0, local.availability_zone_count)
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = var.name
  })
}

# Adopt the VPC default security group and leave it with no rules so it
# denies all traffic (CKV2_AWS_12).
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-default-sg"
  })
}

resource "aws_subnet" "public" {
  count = local.availability_zone_count

  vpc_id            = aws_vpc.this.id
  availability_zone = local.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.cidr_block, 8, count.index)
  # NAT uses an EIP in this subnet. Instances do not get a public address
  # unless one is set on the instance (CKV_AWS_130).
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name}-public-${local.availability_zones[count.index]}"
  })
}

resource "aws_subnet" "private" {
  count = local.availability_zone_count

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.availability_zones[count.index]
  cidr_block              = cidrsubnet(var.cidr_block, 8, 10 + count.index)
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name}-private-${local.availability_zones[count.index]}"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-public"
  })
}

resource "aws_route_table_association" "public" {
  count = local.availability_zone_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-nat-${local.availability_zones[count.index]}"
  })
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id     = aws_eip.nat[count.index].id
  subnet_id         = aws_subnet.public[count.index].id
  connectivity_type = "public"

  tags = merge(var.tags, {
    Name = "${var.name}-nat-${local.availability_zones[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  count = local.nat_gateway_count

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.name}-private-${local.availability_zones[count.index]}"
  })
}

resource "aws_route_table_association" "private" {
  count = local.availability_zone_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[min(count.index, local.nat_gateway_count - 1)].id
}

# The AWS provider adopts the default VPC. force_destroy allows destroy to
# actually delete it (CIS: remove the default VPC).
resource "aws_default_vpc" "this" {
  #checkov:skip=CKV_AWS_148:Adopts the existing default VPC with force_destroy so destroy deletes it. Checkov fails every aws_default_vpc, including this delete path.
  count = var.delete_default_vpc ? 1 : 0

  force_destroy = true

  tags = merge(var.tags, {
    Name = "${var.name}-default"
  })
}

data "aws_caller_identity" "current" {
  count = var.enable_flow_logs ? 1 : 0
}

data "aws_region" "current" {
  count = var.enable_flow_logs ? 1 : 0
}

resource "aws_kms_key" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  description             = "Encrypts VPC flow logs for ${var.name}."
  deletion_window_in_days = 7
  enable_key_rotation     = true

  # Key policies must set Resource to "*". The principal is this account's
  # root, plus the regional CloudWatch Logs service for this log group.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current[0].account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current[0].region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*",
        ]
        Resource = "*"
        Condition = {
          ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current[0].region}:${data.aws_caller_identity.current[0].account_id}:log-group:/aws/vpc/${var.name}/flow-logs"
          }
        }
      },
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name}-flow-logs"
  })
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.flow_logs[0].arn

  tags = merge(var.tags, {
    Name = "${var.name}-flow-logs"
  })
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name}-vpc-flow-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name}-vpc-flow-logs"
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name}-vpc-flow-logs"
  role = aws_iam_role.flow_logs[0].id

  # Actions are limited to this log group and its streams, not Resource "*".
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteVpcFlowLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
        ]
        Resource = [
          aws_cloudwatch_log_group.flow_logs[0].arn,
          "${aws_cloudwatch_log_group.flow_logs[0].arn}:*",
        ]
      }
    ]
  })
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  log_destination_type = "cloud-watch-logs"
  iam_role_arn         = aws_iam_role.flow_logs[0].arn

  tags = merge(var.tags, {
    Name = "${var.name}-flow-logs"
  })

  depends_on = [aws_iam_role_policy.flow_logs]
}
