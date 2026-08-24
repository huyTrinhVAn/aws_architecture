# Shared across every resource file (networking.tf, and later compute.tf,
# database.tf, storage.tf...) — kept here rather than duplicated per file.

variable "project_name" {
  description = "Short project name, used as a prefix for resource names and tags"
  type        = string
  default     = "sa-portfolio"
}
