variable "name" {
  description = "Prefix for every resource name in this module"
  type        = string
  default     = "sa-app"
}

variable "project_id" {
  description = "Service project that runs the VMs"
  type        = string
}

variable "host_project_id" {
  description = "Shared VPC host project -- owns the network and therefore the firewall rules"
  type        = string
}

variable "region" {
  type = string
}

variable "network_id" {
  description = "Shared VPC network the firewall rules apply to"
  type        = string
}

variable "subnet_self_link" {
  description = "Shared subnet the VMs are placed in"
  type        = string
}

variable "app_port" {
  description = "Port the app listens on"
  type        = number
  default     = 8080
}

variable "machine_type" {
  type    = string
  default = "e2-micro"
}

variable "source_image" {
  description = "Image family for the boot disk. A family, so new templates always get the latest patched image"
  type        = string
  default     = "debian-cloud/debian-12"
}

variable "min_replicas" {
  description = "At least 2, so the regional MIG keeps a VM in more than one zone"
  type        = number
  default     = 2

  validation {
    condition     = var.min_replicas >= 2
    error_message = "Keep at least 2 VMs: with 1, losing its zone takes the app down."
  }
}

variable "max_replicas" {
  type    = number
  default = 3
}
