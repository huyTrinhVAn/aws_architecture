# Phase 3, cost-optimization part: a Gateway VPC Endpoint for S3 costs
# nothing (no hourly charge, no data processing charge) and lets the app/db
# subnets reach S3 entirely within the AWS network, without a NAT Gateway.
# It works by adding a route to S3's address range into the given route
# tables — that's why it takes route_table_ids instead of subnet_ids.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.app.id, aws_route_table.db.id]

  tags = {
    Name    = "${var.project_name}-s3-endpoint"
    Project = var.project_name
  }
}

# --- SSM Interface Endpoints -------------------------------------------------
# Unlike the Gateway Endpoint above, these create a real ENI inside the app
# subnets, so they need a security group and (unlike route-table-based
# Gateway Endpoints) only serve traffic reaching that ENI on 443.

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpce-sg"
  description = "Allow HTTPS from inside the VPC to interface VPC endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from within the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-vpce-sg"
    Project = var.project_name
  }
}

# ssm: control-plane API (session start, agent registration)
# ssmmessages: the live data channel for an open Session Manager session
# ec2messages: the channel the SSM Agent polls for commands to run
resource "aws_vpc_endpoint" "ssm" {
  for_each            = toset(["ssm", "ssmmessages", "ec2messages"])
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.app[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name    = "${var.project_name}-${each.value}-endpoint"
    Project = var.project_name
  }
}
