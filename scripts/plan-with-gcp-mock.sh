#!/usr/bin/env bash
# Plan the root module with no real Google or AWS credentials. Does not apply.
#
# AWS calls go to Cloud Custodian's pinned Moto (aws_endpoint_url).
# Compute calls go to a loopback HTTP stub (gcp_endpoint_url), sent with the
# dummy access token "testing". Null gcp_endpoint_url is the real-credential
# path and is not used here.
#
# Arguments are forwarded to plan-with-c7n-moto.sh:
#   1. AWS config_path relative to the root module (that script's first argument).
#   2. Optional gcp_config_path. When omitted, root uses its default GCP file.
#
# hashicorp/google has no single API host the way AWS has an endpoints block.
# compute_custom_endpoint covers the Compute resources in modules/gcp-vpc-tshirt
# (network, subnets, router, Cloud NAT). A request whose host is googleapis.com
# is not a mock plan.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "GCP mock plan: dummy credentials only. No apply."
echo "compute_custom_endpoint is loopback. Provider init still calls Google userinfo on googleapis.com and continues if that request fails. An empty-state plan does not call compute.googleapis.com."
exec "$ROOT/scripts/plan-with-c7n-moto.sh" "$@"
