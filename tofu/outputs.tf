output "external_ipv6" {
  value = google_compute_instance.vm.network_interface[0].ipv6_access_config[0].external_ipv6
}

output "ssh_ipv6" {
  description = "From a machine with IPv6 (PowerShell on this PC)."
  value       = "ssh ${var.ssh_user}@${google_compute_instance.vm.network_interface[0].ipv6_access_config[0].external_ipv6}"
}

output "ssh_iap" {
  description = "From anywhere, including WSL (no IPv6 on Windows 10 WSL)."
  value       = "gcloud compute ssh ${var.ssh_user}@${var.instance_name} --project ${var.project_id} --zone ${var.zone} --tunnel-through-iap --ssh-key-file ${trimsuffix(var.ssh_public_key_path, ".pub")}"
}

output "always_free_usage" {
  description = "Billing-account usage at plan time (other resources + this config)."
  value       = local.usage_report
}
