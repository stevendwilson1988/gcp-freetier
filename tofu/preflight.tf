# Pre-flight: count Compute Engine usage across EVERY project on the billing
# account and refuse to plan anything that would cost money. See ../CLAUDE.md.
#
# Resources owned by this config carry the `managed-by` label and are excluded
# from "other" usage, then counted again from the desired config. Re-planning
# never double counts.

data "external" "usage" {
  program = ["bash", "${path.module}/scripts/usage.sh"]

  query = {
    project_id         = var.project_id
    billing_account_id = var.billing_account_id == null ? "" : var.billing_account_id
    managed_label      = "${local.managed_key}=${local.managed_val}"
  }
}

locals {
  free_e2_micro    = 1
  free_disk_gb     = 30
  free_snapshot_gb = 5

  billing_account = data.external.usage.result.billing_account
  u               = { for k, v in data.external.usage.result : k => tonumber(v) if k != "billing_account" }

  usage_report = <<-EOT
    Billing account ${local.billing_account}, ${local.u.projects_checked} project(s) with Compute enabled:
    e2-micro (free):      ${local.u.free_e2_micro} other + 1 here (limit ${local.free_e2_micro})
    Persistent disk:      ${local.u.disk_gb} GB other + ${var.boot_disk_gb} GB here (limit ${local.free_disk_gb} GB pd-standard)
    Snapshots:            ${local.u.snapshot_gb} GB (limit ${local.free_snapshot_gb} GB)
    Billed already (must be 0):
      non-free instances:   ${local.u.paid_instances}
      non-standard disks:   ${local.u.non_standard_disks}
      VMs with ext. IPv4:   ${local.u.ipv4_in_use}
      static external IPs:  ${local.u.static_external_ips}
      custom images:        ${local.u.custom_images}
  EOT
}

# Everything this config creates depends on this, so a failed precondition
# stops the plan before any resource is touched.
resource "terraform_data" "always_free_guard" {
  input = local.usage_report

  lifecycle {
    precondition {
      condition     = local.u.free_e2_micro + 1 <= local.free_e2_micro
      error_message = "Would exceed the 1 Always Free e2-micro (720 h/month).\n${local.usage_report}"
    }
    precondition {
      condition     = local.u.disk_gb + var.boot_disk_gb <= local.free_disk_gb
      error_message = "Would exceed 30 GB of Always Free standard persistent disk.\n${local.usage_report}"
    }
    precondition {
      condition     = local.u.snapshot_gb <= local.free_snapshot_gb
      error_message = "Snapshots already exceed 5 GB.\n${local.usage_report}"
    }
    precondition {
      condition     = local.u.paid_instances + local.u.non_standard_disks + local.u.ipv4_in_use + local.u.static_external_ips + local.u.custom_images == 0
      error_message = "Resources on this billing account are already billed. Fix them first.\n${local.usage_report}"
    }
  }
}
