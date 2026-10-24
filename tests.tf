# Terraform 1.9 treats a directory that contains only .tftest.hcl files as
# empty and does not install modules those tests reference. This file declares
# no resources. Its presence makes `terraform init` load
# tests/vpc_tshirt.tftest.hcl and install modules/aws-vpc-tshirt.
terraform {
  required_version = ">= 1.5.0"
}
