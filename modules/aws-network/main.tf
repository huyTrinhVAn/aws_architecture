# VPC, 3-tier subnets (public / app / db) across the given AZs, their route
# tables, and the VPC endpoints that replace a NAT Gateway. The app and db
# route tables get no default route: app instances reach AWS services
# through the endpoints, and the db tier reaches nothing at all.

locals {
  # Subnets are keyed by AZ, not by list index. With count, removing the
  # first AZ would shift every remaining index down by one, and Terraform
  # would destroy and re-create the subnets in the AZs that stayed. With
  # for_each, only the removed AZ's subnets are touched.
  subnets = {
    for index, az in var.azs : az => {
      public = var.public_subnet_cidrs[index]
      app    = var.app_subnet_cidrs[index]
      db     = var.db_subnet_cidrs[index]
    }
  }
}

resource "aws_vpc" "this" {
  #checkov:skip=CKV2_AWS_11:Flow Logs are scheduled for roadmap Phase 5 (observability), together with their retention/cost decision

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}

# AWS creates a "default" security group in every VPC that allows all
# traffic between its members plus all egress. Nothing here uses it, but
# anything launched without an explicit SG silently lands in it. Adopting
# it with no ingress/egress blocks makes Terraform strip every rule, so
# that silent fallback means "no traffic at all" instead.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-default-sg-locked"
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
  for_each          = local.subnets
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.public
  availability_zone = each.key
  # Only the ALB lives here, and it gets its public IPs from the load
  # balancer service itself, not from this setting -- leaving it on would
  # only matter for an instance launched here by mistake, giving it a
  # public IP nobody asked for.
  map_public_ip_on_launch = false

  tags = {
    Name    = "${var.project_name}-public-${each.key}"
    Project = var.project_name
    Tier    = "public"
  }
}

resource "aws_subnet" "app" {
  for_each          = local.subnets
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.app
  availability_zone = each.key

  tags = {
    Name    = "${var.project_name}-app-${each.key}"
    Project = var.project_name
    Tier    = "app"
  }
}

resource "aws_subnet" "db" {
  for_each          = local.subnets
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.db
  availability_zone = each.key

  tags = {
    Name    = "${var.project_name}-db-${each.key}"
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
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# No default route -- app instances reach AWS services through the VPC
# endpoints below, not a NAT Gateway.
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name    = "${var.project_name}-app-rt"
    Project = var.project_name
  }
}

resource "aws_route_table_association" "app" {
  for_each       = aws_subnet.app
  subnet_id      = each.value.id
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
  for_each       = aws_subnet.db
  subnet_id      = each.value.id
  route_table_id = aws_route_table.db.id
}
