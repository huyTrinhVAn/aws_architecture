variable "host_project_id" {
  description = "Shared VPC host project: owns the VPC, subnets, routes, NAT and (later) firewall rules"
  type        = string
}

variable "service_project_ids" {
  description = "Service projects attached to the Shared VPC -- they can place resources in shared subnets but can't change the network"
  type        = set(string)
}

variable "region" {
  description = "Region for the subnet, Cloud Router and Cloud NAT"
  type        = string
}

variable "network_name" {
  type    = string
  default = "sa-vpc"
}

variable "app_subnet_cidr" {
  description = "Primary range of the app subnet. Regional: it spans every zone in var.region"
  type        = string
  default     = "10.10.0.0/24"
}

variable "private_service_range" {
  description = "Range reserved for Google-managed services reached over private IP (Cloud SQL). Google creates its own VPC in this range and peers it with ours"
  type = object({
    address       = string
    prefix_length = number
  })
  default = {
    address       = "10.20.0.0"
    prefix_length = 20
  }
}

variable "app_subnet_users" {
  description = <<-EOT
    Members granted roles/compute.networkUser on the app subnet ONLY (not the
    whole host project), e.g. the service project's Google APIs service agent
    that creates its managed instance groups. Least privilege: a service
    project can use this one subnet and nothing else in the VPC.
  EOT
  type        = set(string)
  default     = []
}
