variable "project_id" {
  description = "GCP project to create the VM in."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID."
  }
}

variable "billing_account_id" {
  description = "Billing account to check Always Free usage across (e.g. 0X0X0X-0X0X0X-0X0X0X). If null, read from the project."
  type        = string
  default     = null
}

variable "zone" {
  description = "Zone for the VM. Only the three Always Free e2-micro regions are allowed."
  type        = string
  default     = "us-east1-b"

  validation {
    condition     = can(regex("^(us-west1|us-central1|us-east1)-[a-z]$", var.zone))
    error_message = "zone must be in us-west1, us-central1 or us-east1 (the Always Free e2-micro regions)."
  }
}

variable "instance_name" {
  description = "VM name. Renaming replaces the VM."
  type        = string
  default     = "freetier-ubuntu"
}

variable "boot_disk_gb" {
  description = "Boot disk size. All standard persistent disks on the billing account share 30 GB free."
  type        = number
  default     = 30

  validation {
    condition     = var.boot_disk_gb >= 10 && var.boot_disk_gb <= 30
    error_message = "boot_disk_gb must be between 10 and 30."
  }
}

variable "ssh_user" {
  description = "Linux user that gets the SSH key."
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "SSH public key installed for ssh_user."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_allowed_cidr_ipv6" {
  description = "IPv6 prefix allowed to SSH to the VM directly. Use your /64; Windows rotates its temporary address daily. Set it in terraform.tfvars (git-ignored)."
  type        = string
  # No default: the plan fails rather than opening SSH to the internet.

  validation {
    condition     = can(cidrhost(var.ssh_allowed_cidr_ipv6, 0)) && strcontains(var.ssh_allowed_cidr_ipv6, ":") && !startswith(var.ssh_allowed_cidr_ipv6, "::/")
    error_message = "ssh_allowed_cidr_ipv6 must be an IPv6 CIDR such as 2001:db8:1:2::/64, and not ::/0."
  }
}

variable "name_prefix" {
  description = "Prefix for the network resources this config creates."
  type        = string
  default     = "freetier-tofu"
}
