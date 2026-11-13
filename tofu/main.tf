# One Always Free e2-micro VM. See ../CLAUDE.md for the rules.
#
# Networking: internal IPv4 + external IPv6 only. In-use external IPv4 is billed;
# external IPv6 is not. Consequences:
#   - The VM can't reach IPv4-only hosts (e.g. github.com). No NAT64: Cloud NAT is billed.
#   - SSH directly over IPv6 from a machine with IPv6 (Windows/PowerShell here),
#     or through IAP from anywhere (WSL here).
#   - Egress still counts against the 1 GB/month free allowance, IPv6 included.

locals {
  # Hard-coded on purpose: anything else is billed.
  machine_type = "e2-micro"
  disk_type    = "pd-standard"
  image        = "ubuntu-os-cloud/ubuntu-minimal-2404-lts-amd64"

  region      = regex("^(.*)-[a-z]$", var.zone)[0]
  managed_key = "managed-by"
  managed_val = "opentofu-gcp-freetier"
  labels      = { (local.managed_key) = local.managed_val }
}

resource "google_compute_instance" "vm" {
  name         = var.instance_name
  machine_type = local.machine_type
  zone         = var.zone
  tags         = ["freetier-ssh"]
  labels       = local.labels

  allow_stopping_for_update = true
  deletion_protection       = false

  scheduling {
    preemptible        = false
    provisioning_model = "STANDARD" # Spot/preemptible is not covered by the free tier.
    automatic_restart  = true
  }

  boot_disk {
    auto_delete = true # `tofu destroy` must delete the disk, or it keeps counting toward 30 GB.

    initialize_params {
      image  = local.image
      type   = local.disk_type
      size   = var.boot_disk_gb
      labels = local.labels
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.this.id
    stack_type = "IPV4_IPV6"

    # No access_config block: no external IPv4 (billed).
    ipv6_access_config {
      network_tier = "PREMIUM" # Required for external IPv6.
    }
  }

  metadata = {
    ssh-keys               = "${var.ssh_user}:${trimspace(file(pathexpand(var.ssh_public_key_path)))}"
    block-project-ssh-keys = "true"
  }

  lifecycle {
    # A newer Ubuntu image must not recreate the VM; gcloud may add SSH keys to metadata.
    ignore_changes = [boot_disk[0].initialize_params[0].image, metadata]
  }

  depends_on = [
    terraform_data.always_free_guard,
    google_compute_firewall.ssh_ipv6,
    google_compute_firewall.ssh_iap,
  ]
}
