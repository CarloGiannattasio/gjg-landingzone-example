# Terraform 1.9 treats a directory that contains only .tftest.hcl files as
# empty and does not install modules those tests reference. This file declares
# no resources. Its presence makes `terraform init` load
# tests/vpc_tshirt.tftest.hcl and tests/gcp_vpc_tshirt.tftest.hcl, and install
# the modules those tests reference.
terraform {
  required_version = ">= 1.5.0"
}
