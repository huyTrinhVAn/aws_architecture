variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name, used as a prefix for resource names and tags"
  type        = string
  default     = "sa-portfolio"
}

variable "app_port" {
  description = "Port the Budget Tracker API listens on"
  type        = number
  default     = 8080
}

variable "db_port" {
  description = "Port the database listens on (3306 = MySQL)"
  type        = number
  default     = 3306
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ, same order as var.azs)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "app_subnet_cidrs" {
  description = "CIDR blocks for private app subnets (one per AZ, same order as var.azs)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "db_subnet_cidrs" {
  description = "CIDR blocks for private db subnets (one per AZ, same order as var.azs)"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}
