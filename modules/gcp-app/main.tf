# App tier on GCP: a regional managed instance group (MIG) of private VMs
# in the Shared VPC's app subnet.
#
# Compared with modules/aws-app (see docs/aws-vs-gcp.md):
#   - instance template + MIG + autoscaler     ~ launch template + ASG + scaling policy
#   - a REGIONAL MIG spreads VMs across zones  ~ an ASG across several AZ subnets
#   - the VM's service account                 ~ the instance profile / IAM role
#   - IAP TCP forwarding                       ~ SSM Session Manager
#   - firewall rules live in the HOST project (the network team's), and
#     target the VMs by service account instead of by security group
#
# The load balancer, TLS certificate and Cloud Armor come in the next step;
# the health check and named port here are what it will plug into.

# --- Identity -------------------------------------------------------------------

# A dedicated, near-empty identity for the VMs. Never the Compute Engine
# default service account: it's shared by every VM in the project, and it
# used to be granted Editor on the whole project automatically.
resource "google_service_account" "app" {
  project      = var.project_id
  account_id   = "${var.name}-vm"
  display_name = "App tier VMs (${var.name})"
}

# Only what the VMs need today: write their own logs and metrics. Cloud SQL
# and Secret Manager access is added with the database in step 3.7.
resource "google_project_iam_member" "app" {
  for_each = toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
  ])

  project = var.project_id
  role    = each.value
  member  = google_service_account.app.member
}

# --- Instance template -------------------------------------------------------------

resource "google_compute_instance_template" "app" {
  project      = var.project_id
  name_prefix  = "${var.name}-"
  machine_type = var.machine_type
  region       = var.region

  disk {
    source_image = var.source_image
    boot         = true
    auto_delete  = true
    disk_size_gb = 10
    disk_type    = "pd-balanced"
  }

  network_interface {
    subnetwork = var.subnet_self_link
    # No access_config block = no external IP. The VMs are reachable only
    # through the load balancer and IAP; outbound traffic uses Cloud NAT.
  }

  service_account {
    email = google_service_account.app.email
    # The broad scope is the modern default: what the VM may actually do is
    # decided by the service account's IAM roles, not by legacy scopes.
    scopes = ["cloud-platform"]
  }

  # Verified boot chain: Secure Boot only runs signed bootloaders and
  # kernels, the vTPM measures the boot, and integrity monitoring alerts if
  # those measurements change (a bootkit, for example).
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    # SSH keys come from IAM (OS Login), not from keys pasted into metadata:
    # access is granted and revoked with roles, and every login is audited.
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
    serial-port-enable     = "FALSE"

    startup-script = templatefile("${path.module}/startup.sh.tftpl", {
      app_port = var.app_port
    })
  }

  labels = {
    tier = "app"
  }

  # Templates are immutable: every change creates a new one. Create the new
  # template before deleting the old one, which the MIG still references.
  lifecycle {
    create_before_destroy = true
  }
}

# --- Health check ----------------------------------------------------------------

# One health check for both jobs: autohealing (recreate a VM that stops
# answering) and, from the next step, the load balancer's backend health.
resource "google_compute_health_check" "app" {
  project = var.project_id
  name    = "${var.name}-http"

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = var.app_port
    request_path = "/health"
  }

  log_config {
    enable = false # turned on in Phase 5 (observability)
  }
}

# --- Managed instance group --------------------------------------------------------

resource "google_compute_region_instance_group_manager" "app" {
  project            = var.project_id
  name               = "${var.name}-mig"
  region             = var.region
  base_instance_name = var.name

  version {
    instance_template = google_compute_instance_template.app.id
  }

  # The load balancer's backend service sends traffic to this port by name.
  named_port {
    name = "http"
    port = var.app_port
  }

  # Recreate a VM that fails the health check. The delay gives a new VM time
  # to boot and start the app before its first failed check counts.
  auto_healing_policies {
    health_check      = google_compute_health_check.app.id
    initial_delay_sec = 180
  }

  # A new template rolls out by itself: add new VMs first, then remove old
  # ones, never dropping below the current size. A regional MIG needs a
  # surge of 0 or at least one VM per zone, hence 3.
  update_policy {
    type                  = "PROACTIVE"
    minimal_action        = "REPLACE"
    max_surge_fixed       = 3
    max_unavailable_fixed = 0
  }

  # Don't make `terraform apply` wait for the VMs to be healthy -- the same
  # lesson as the AWS ASG's wait_for_capacity_timeout = "0": capacity
  # problems are the MIG's job to retry, and a failed wait only taints the
  # resource. Health is checked by autohealing and the load balancer.
  wait_for_instances = false

  # target_size is owned by the autoscaler below.
}

resource "google_compute_region_autoscaler" "app" {
  project = var.project_id
  name    = "${var.name}-autoscaler"
  region  = var.region
  target  = google_compute_region_instance_group_manager.app.id

  autoscaling_policy {
    # Two VMs minimum, so one zone going down still leaves one serving.
    min_replicas    = var.min_replicas
    max_replicas    = var.max_replicas
    cooldown_period = 120

    cpu_utilization {
      target = 0.6
    }
  }
}

# --- Firewall (host project) ------------------------------------------------------

# In a Shared VPC, firewall rules belong to the host project: the service
# project can run VMs in the subnet but cannot open ports on it. Rules
# target the VMs' service account rather than a network tag, because anyone
# who can edit a VM can add a tag to it, but attaching a service account
# requires permission on that service account.

# Google's health checkers (and, from the next step, the load balancer's
# proxies) connect from these two ranges -- nothing else may reach the app.
resource "google_compute_firewall" "allow_health_checks" {
  project   = var.host_project_id
  name      = "${var.name}-allow-health-checks"
  network   = var.network_id
  direction = "INGRESS"
  priority  = 1000

  source_ranges           = ["35.191.0.0/16", "130.211.0.0/22"]
  target_service_accounts = [google_service_account.app.email]

  allow {
    protocol = "tcp"
    ports    = [tostring(var.app_port)]
  }
}

# SSH only through Identity-Aware Proxy: IAP checks the caller's IAM role
# (roles/iap.tunnelResourceAccessor) before opening a tunnel, and only IAP's
# own range may connect. There is no route for SSH from the internet.
resource "google_compute_firewall" "allow_iap_ssh" {
  project   = var.host_project_id
  name      = "${var.name}-allow-iap-ssh"
  network   = var.network_id
  direction = "INGRESS"
  priority  = 1000

  source_ranges           = ["35.235.240.0/20"]
  target_service_accounts = [google_service_account.app.email]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
