# Shared VPC network: one global VPC in the host project, shared with the
# service projects that run the workloads.
#
# Compared with the AWS module (see docs/aws-vs-gcp.md):
#   - the VPC is global and subnets are regional (each spans every zone),
#     so one app subnet replaces AWS's two-per-tier-per-AZ layout
#   - there's no public subnet: the external HTTPS load balancer runs on
#     Google's edge, outside this VPC
#   - there's no DB subnet: Cloud SQL gets a private IP from a reserved
#     range Google peers into this VPC (private services access)
#   - Private Google Access (one subnet flag) replaces AWS's per-service
#     interface endpoints

# --- Shared VPC -----------------------------------------------------------------

resource "google_compute_shared_vpc_host_project" "host" {
  project = var.host_project_id
}

resource "google_compute_shared_vpc_service_project" "this" {
  for_each = var.service_project_ids

  host_project    = google_compute_shared_vpc_host_project.host.project
  service_project = each.value
}

# --- VPC and subnet -------------------------------------------------------------

resource "google_compute_network" "this" {
  project = var.host_project_id
  name    = var.network_name

  # Auto mode creates a subnet in every region with ranges we didn't
  # choose. Custom mode: only the subnets defined below exist.
  auto_create_subnetworks = false

  # Cloud Routers only advertise their own region's subnets. Switch to
  # GLOBAL in Phase 4 if the VPN must reach subnets in other regions.
  routing_mode = "REGIONAL"
}

resource "google_compute_subnetwork" "app" {
  #checkov:skip=CKV_GCP_26:VPC Flow Logs are scheduled for roadmap Phase 5 (observability), same as on AWS
  #checkov:skip=CKV_GCP_76:IPv4-only network; Private Google Access over IPv6 has no IPv6 range to apply to

  project       = var.host_project_id
  name          = "${var.network_name}-app"
  region        = var.region
  network       = google_compute_network.this.id
  ip_cidr_range = var.app_subnet_cidr

  # VMs with no external IP can still call Google APIs (Cloud Storage,
  # Secret Manager, Cloud SQL Admin, Artifact Registry...) over Google's
  # network -- free, and one flag instead of an endpoint per service.
  private_ip_google_access = true
}

# Least privilege for Shared VPC: grant networkUser on this subnet only,
# not on the host project (which would let a service project use every
# current and future subnet).
resource "google_compute_subnetwork_iam_member" "app_users" {
  for_each = var.app_subnet_users

  project    = var.host_project_id
  region     = google_compute_subnetwork.app.region
  subnetwork = google_compute_subnetwork.app.name
  role       = "roles/compute.networkUser"
  member     = each.value
}

# --- Baseline firewall ------------------------------------------------------------

# Every VPC has two invisible "implied" rules: deny all ingress and allow
# all egress, both at priority 65535. This makes the ingress one explicit
# (priority 65534, just above it), so the baseline is code that shows up
# in reviews, and logging can be turned on in Phase 5 to see what's being
# blocked. Specific allow rules (load balancer health checks, IAP) come
# with the app tier in step 3.6, at higher priority (lower number).
resource "google_compute_firewall" "deny_all_ingress" {
  project   = var.host_project_id
  name      = "${var.network_name}-deny-all-ingress"
  network   = google_compute_network.this.id
  direction = "INGRESS"
  priority  = 65534

  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }
}

# --- Private services access (Cloud SQL private IP) -----------------------------

resource "google_compute_global_address" "private_services" {
  project       = var.host_project_id
  name          = "${var.network_name}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = var.private_service_range.address
  prefix_length = var.private_service_range.prefix_length
  network       = google_compute_network.this.id
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}

# --- Outbound internet for private VMs ------------------------------------------

# Cloud NAT is configuration on a Cloud Router, not a VM or an appliance
# per zone like an AWS NAT Gateway. Outbound only: nothing on the internet
# can open a connection to a VM through it.
resource "google_compute_router" "this" {
  project = var.host_project_id
  name    = "${var.network_name}-router"
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  project = var.host_project_id
  name    = "${var.network_name}-nat"
  router  = google_compute_router.this.name
  region  = var.region

  nat_ip_allocate_option = "AUTO_ONLY"

  # Only the app subnet gets NAT -- a subnet added later doesn't silently
  # get internet access.
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.app.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
