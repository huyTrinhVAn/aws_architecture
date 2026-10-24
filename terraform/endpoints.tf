# Phase 3, cost-optimization part: a Gateway VPC Endpoint for S3 costs
# nothing (no hourly charge, no data processing charge) and lets the app/db
# subnets reach S3 entirely within the AWS network, without a NAT Gateway.
# It works by adding a route to S3's address range into the given route
# tables — that's why it takes route_table_ids instead of subnet_ids.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  # App tier only. The db tier never calls S3 itself (RDS backups travel
  # over AWS's own network, not this VPC's route tables), so an S3 route in
  # the db route table was only ever a way for data to leave.
  route_table_ids = [aws_route_table.app.id]

  # Without a policy, a gateway endpoint lets anything in the subnet reach
  # *any* bucket in the region -- including one an attacker owns, which is
  # an exfiltration path that needs no internet access at all. This is the
  # network-layer half of the control; the app role's IAM policy in
  # security.tf is the identity half, and a request needs both to allow it.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ReceiptsReadWrite"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"]
        Resource  = "${aws_s3_bucket.receipts.arn}/*"
      },
      {
        Sid       = "DeployBundleRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = "${aws_s3_bucket.deploy.arn}/*"
      },
      {
        # AWS-operated bucket backing AL2023's dnf repos (user_data.sh.tftpl
        # installs python3-pip from it at boot).
        Sid       = "AmazonLinuxRepos"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = "arn:aws:s3:::al2023-repos-${var.aws_region}-de612dc2/*"
      },
    ]
  })

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

  # Endpoint ENIs only answer requests; replies are allowed by SG
  # statefulness, so they never need to open a connection themselves.
  egress = []

  tags = {
    Name    = "${var.project_name}-vpce-sg"
    Project = var.project_name
  }
}

# ssm: control-plane API (session start, agent registration)
# ssmmessages: the live data channel for an open Session Manager session
# ec2messages: the channel the SSM Agent polls for commands to run
# secretsmanager: added after user_data's GetSecretValue call was found
# hanging indefinitely at boot -- no route existed to reach it at all,
# unlike a rejected/failed connection, which is why it looked like a hang
# rather than an error. Same pattern as the other three: reuses this
# security group, still no NAT Gateway needed.
resource "aws_vpc_endpoint" "ssm" {
  for_each            = toset(["ssm", "ssmmessages", "ec2messages", "secretsmanager"])
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
