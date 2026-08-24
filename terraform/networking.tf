# Phase 1: VPC, 3-tier subnets (public / app / db) across 2 AZs, and their
# route tables. The app and db route tables intentionally get no default
# route yet — Phase 3 replaces a NAT Gateway with VPC Endpoints instead.

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

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name    = "${var.project_name}-igw"
    Project = var.project_name
  }
}

# --- Subnets ---------------------------------------------------------------

resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name    = "${var.project_name}-public-${var.azs[count.index]}"
    Project = var.project_name
    Tier    = "public"
  }
}

resource "aws_subnet" "app" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name    = "${var.project_name}-app-${var.azs[count.index]}"
    Project = var.project_name
    Tier    = "app"
  }
}

resource "aws_subnet" "db" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name    = "${var.project_name}-db-${var.azs[count.index]}"
    Project = var.project_name
    Tier    = "db"
  }
}

# --- Route tables ------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name    = "${var.project_name}-public-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# No route out yet — app instances will reach AWS services via VPC
# Endpoints added in Phase 3, not a NAT Gateway.
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name    = "${var.project_name}-app-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "app" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

# Fully isolated — no route out at all, ever.
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name    = "${var.project_name}-db-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "db" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}
