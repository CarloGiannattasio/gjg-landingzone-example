# config_path and gcp_config_path are paths relative to the root module
# directory. The module reads each file with
# file(abspath("${path.module}/${var.config_path}")).

variable "config_path" {
  description = "Path to one AWS account JSON file, relative to the root module directory. CI must pass this value; there is no default."
  type        = string
}

variable "gcp_config_path" {
  description = "Path to one GCP project JSON file, relative to the root module directory. Decoded to prove the multi-cloud config contract. No GCP resources are created."
  type        = string
  default     = "../config/gcp/example/example-prod/example-prod.json"
}

variable "aws_endpoint_url" {
  description = "Base URL of one Moto server for every AWS service this stack calls. Null keeps the real AWS provider: no custom endpoints and no static keys. Set only for a local mock plan."
  type        = string
  default     = null
}
