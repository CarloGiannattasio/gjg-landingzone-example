# T-shirt VPC for the example business unit on GCP.
#
# Small:  1 zone, 1 public subnet, 1 private subnet, 1 Cloud NAT.
# Medium: 2 zones, 2 public subnets, 2 private subnets, 1 shared Cloud NAT.
# Large:  3 zones, 3 public subnets, 3 private subnets, 1 Cloud NAT per zone.
#
# Subnet CIDRs use cidrsubnet(var.cidr_block, 8, netnum):
#   public  netnums 0 .. zone_count-1
#   private netnums 10 .. 10+zone_count-1
#
# The network is custom mode and has no CIDR of its own. A custom-mode
# network has no implied allow rules, so this module creates no firewall
# rules and does not open 0.0.0.0/0. The GCP default network is left in place.

locals {
  # Zone count is derived from t-shirt size. It is intentionally not a variable.
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

  # Zone names are pinned so a newly added zone cannot enter the set.
  # A zones data source would also force terraform test to mock the lookup.
  # Small and Medium use a prefix of this list; Large uses all three.
  availability_zones = slice(
    ["${var.region}-a", "${var.region}-b", "${var.region}-c"],
    0,
    local.availability_zone_count,
  )

  # One shared Cloud NAT (Small, Medium) omits the zone from the name.
  # Large has one router and one NAT per zone, so each name includes the zone.
  router_names = [
    for idx in range(local.nat_gateway_count) : (
      local.nat_gateway_count == 1
      ? "${var.name}-router"
      : "${var.name}-router-${local.availability_zones[idx]}"
    )
  ]

  nat_names = [
    for idx in range(local.nat_gateway_count) : (
      local.nat_gateway_count == 1
      ? "${var.name}-nat"
      : "${var.name}-nat-${local.availability_zones[idx]}"
    )
  ]

  # One NAT covers every private subnet. One NAT per zone covers only its own.
  nat_private_subnet_indexes = [
    for nat_index in range(local.nat_gateway_count) : (
      local.nat_gateway_count == 1
      ? tolist(range(local.availability_zone_count))
      : tolist([nat_index])
    )
  ]
}

resource "google_compute_network" "this" {
  name                    = var.name
  project                 = var.project_id
  auto_create_subnetworks = false
  # REGIONAL matches a single-region network: Cloud Routers advertise only
  # subnets in var.region.
  routing_mode = "REGIONAL"

  # No CIDR on the network. Ranges live on the subnets, carved from var.cidr_block.
  # The GCP default network is not adopted or deleted.
  # hashicorp/google 8.8.1 does not accept labels on this resource.
}

resource "google_compute_subnetwork" "public" {
  count = local.availability_zone_count

  name          = "${var.name}-public-${local.availability_zones[count.index]}"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = cidrsubnet(var.cidr_block, 8, count.index)
  # Public subnets do not need Private Google Access. Private subnets enable
  # it, and Cloud NAT covers only those private subnets.
  private_ip_google_access = false

  # Flow logs are a subnet log_config on GCP, not a separate resource.
  # The block is omitted unless requested so sampling stays off by default.
  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []

    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

resource "google_compute_subnetwork" "private" {
  count = local.availability_zone_count

  name                     = "${var.name}-private-${local.availability_zones[count.index]}"
  project                  = var.project_id
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = cidrsubnet(var.cidr_block, 8, 10 + count.index)
  private_ip_google_access = true

  # Same flow-log settings as the public subnets.
  dynamic "log_config" {
    for_each = var.enable_flow_logs ? [1] : []

    content {
      aggregation_interval = "INTERVAL_5_SEC"
      flow_sampling        = 0.5
      metadata             = "INCLUDE_ALL_METADATA"
    }
  }
}

# Small and Medium share one Cloud NAT across every private subnet.
# Large uses one router and one NAT per zone, each limited to that zone's
# private subnet. Resource counts match nat_gateway_count.
# Cloud NAT does not add a firewall allow from 0.0.0.0/0.
resource "google_compute_router" "this" {
  count = local.nat_gateway_count

  name    = local.router_names[count.index]
  project = var.project_id
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  count = local.nat_gateway_count

  name    = local.nat_names[count.index]
  project = var.project_id
  region  = var.region
  router  = google_compute_router.this[count.index].name

  # AUTO_ONLY lets GCP allocate the external NAT addresses. This module does
  # not reserve static IPs.
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  dynamic "subnetwork" {
    for_each = local.nat_private_subnet_indexes[count.index]

    content {
      name                    = google_compute_subnetwork.private[subnetwork.value].id
      source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
  }

  # google_compute_router_nat has no labels argument.
}
