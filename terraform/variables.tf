# Shared across every resource file (networking.tf, and later compute.tf,
# database.tf, storage.tf...) — kept here rather than duplicated per file.

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
  description = "Port the database listens on (3306 = MySQL, 5432 = Postgres)"
  type        = number
  default     = 3306
}
