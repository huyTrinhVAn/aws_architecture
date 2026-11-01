variable "project_name" {
  description = "Short project name, used as a prefix for resource names and tags"
  type        = string
}

variable "aws_region" {
  description = "Region the VPC endpoints are created for (part of each endpoint's service name)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ, same order as var.azs)"
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs needs exactly one CIDR per entry in azs."
  }
}

variable "app_subnet_cidrs" {
  description = "CIDR blocks for private app subnets (one per AZ, same order as var.azs)"
  type        = list(string)

  validation {
    condition     = length(var.app_subnet_cidrs) == length(var.azs)
    error_message = "app_subnet_cidrs needs exactly one CIDR per entry in azs."
  }
}

variable "db_subnet_cidrs" {
  description = "CIDR blocks for private db subnets (one per AZ, same order as var.azs)"
  type        = list(string)

  validation {
    condition     = length(var.db_subnet_cidrs) == length(var.azs)
    error_message = "db_subnet_cidrs needs exactly one CIDR per entry in azs."
  }
}

variable "interface_endpoints" {
  description = "AWS services to reach through interface endpoints in the app subnets, instead of a NAT Gateway"
  type        = set(string)
  default     = ["ssm", "ssmmessages", "ec2messages", "secretsmanager"]
}

variable "s3_endpoint_policy" {
  description = "JSON policy for the S3 gateway endpoint. Pass one that lists only the buckets the app needs -- null leaves the endpoint open to every bucket in the region"
  type        = string
  default     = null
}
