# Custom VPC: free, and avoids the default network's SSH-from-anywhere rule.
# No Cloud NAT, router, static IP or load balancer: all are billed.

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# Needed for `gcloud compute ssh --tunnel-through-iap`. IAP TCP forwarding is free.
resource "google_project_service" "iap" {
  service            = "iap.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_network" "this" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute, terraform_data.always_free_guard]
}

resource "google_compute_subnetwork" "this" {
  name          = "${var.name_prefix}-subnet"
  network       = google_compute_network.this.id
  region        = local.region
  ip_cidr_range = "10.2.0.0/24"

  # Dual stack: internal IPv4 only, plus a free external IPv6 range.
  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "EXTERNAL"

  # Lets the VM reach Google APIs over internal IPv4. Free.
  private_ip_google_access = true

  # No log_config block: VPC flow logs stay off.
}

resource "google_compute_firewall" "ssh_ipv6" {
  name          = "${var.name_prefix}-ssh-ipv6"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = [var.ssh_allowed_cidr_ipv6]
  target_tags   = ["freetier-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Google's IAP TCP forwarding range. Only principals with IAP access on the
# project can tunnel through it; this is the SSH path from WSL (no IPv6 there).
resource "google_compute_firewall" "ssh_iap" {
  name          = "${var.name_prefix}-ssh-iap"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["freetier-ssh"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# ICMPv6 (path MTU discovery, etc.); IPv6 breaks in odd ways without it.
resource "google_compute_firewall" "icmpv6" {
  name          = "${var.name_prefix}-icmpv6"
  network       = google_compute_network.this.id
  direction     = "INGRESS"
  source_ranges = ["::/0"]

  allow {
    protocol = "58"
  }
}
