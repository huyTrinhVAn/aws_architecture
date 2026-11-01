variable "project_name" {
  description = "Short project name, used as a prefix for resource names and tags"
  type        = string
}

variable "vpc_id" {
  description = "VPC the database security group is created in"
  type        = string
}

variable "subnet_ids" {
  description = "Isolated subnets (one per AZ) for the DB subnet group"
  type        = list(string)
}

variable "port" {
  description = "Port the database listens on (3306 = MySQL)"
  type        = number
  default     = 3306
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect on the database port -- the app tier, and nothing else"
  type        = list(string)
}
