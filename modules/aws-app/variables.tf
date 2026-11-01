variable "project_name" {
  description = "Short project name, used as a prefix for resource names and tags"
  type        = string
}

variable "aws_region" {
  description = "Region passed to the instances' AWS CLI calls at boot"
  type        = string
}

# --- Network (from the aws-network module) -----------------------------------

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Subnets for the internet-facing ALB"
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Private subnets for the Auto Scaling Group"
  type        = list(string)
}

variable "app_subnet_cidrs" {
  description = "CIDRs of app_subnet_ids -- the only destination the ALB may send traffic to"
  type        = list(string)
}

variable "db_subnet_cidrs" {
  description = "CIDRs of the db subnets -- the app tier's only egress on the database port"
  type        = list(string)
}

variable "vpc_endpoints_security_group_id" {
  description = "SG of the interface endpoints (SSM, Secrets Manager) the instances call on 443"
  type        = string
}

variable "s3_prefix_list_id" {
  description = "Prefix list of the S3 gateway endpoint the instances call on 443"
  type        = string
}

# --- App wiring ----------------------------------------------------------------

variable "app_port" {
  description = "Port the app listens on"
  type        = number
  default     = 8080
}

variable "db_port" {
  description = "Port the database listens on"
  type        = number
  default     = 3306
}

variable "receipts_bucket_name" {
  type = string
}

variable "receipts_bucket_arn" {
  type = string
}

variable "deploy_bucket_name" {
  description = "Bucket the instances download the app bundle from at boot"
  type        = string
}

variable "deploy_bucket_arn" {
  type = string
}

variable "db_credentials_secret_arn" {
  description = "Secret the instances read the DB connection details from at boot"
  type        = string
}

# --- Capacity ------------------------------------------------------------------

variable "instance_type" {
  description = "Graviton (arm64) instance type -- the AMI lookup only returns arm64 images"
  type        = string
  default     = "t4g.micro"
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 3
}

variable "desired_capacity" {
  description = "Initial capacity only; afterwards the CPU target-tracking policy owns it"
  type        = number
  default     = 2
}
