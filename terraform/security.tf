# Phase 2: security groups chained by tier (alb -> app -> db), each only
# trusting the tier directly in front of it — never a broad CIDR. No rule
# here ever opens port 22: instance access goes through SSM Session Manager
# instead (IAM role below; the VPC endpoints it needs are added in Phase 3).

# Egress is least-privilege too, not just ingress: each tier may only open
# connections to the exact next hop it needs. Egress rules use CIDRs or
# prefix lists rather than SG references where the target SG already
# references this one (app <-> db, alb <-> app) -- two inline SGs pointing
# at each other is a dependency cycle Terraform can't create.

resource "aws_security_group" "alb" {
  #checkov:skip=CKV_AWS_260:Internet-facing ALB -- accepting port 80 from anywhere is its job (and it's needed for the HTTP->HTTPS redirect)

  name        = "${var.project_name}-alb-sg"
  description = "Allow inbound HTTP/HTTPS from the internet"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # The ALB only ever talks to the app instances (requests + health checks).
  egress {
    description = "Forward requests and health checks to the app tier"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = var.app_subnet_cidrs
  }

  tags = {
    Name    = "${var.project_name}-alb-sg"
    Project = var.project_name
    # Read by policy/security_groups.rego: the only SG allowed to accept
    # 0.0.0.0/0, and even then only on 80/443. Any other SG opening itself
    # to the internet fails the PR.
    Exposure = "internet-facing"
  }
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Allow inbound app traffic from the ALB only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "App port from ALB"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # DELIBERATELY BAD -- test PR to prove the policy gate blocks it. Never merge.
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSM, ssmmessages, ec2messages and Secrets Manager via the interface
  # endpoints. DNS (VPC resolver), IMDS and NTP use link-local addresses
  # that security groups never filter, so they need no rule here.
  egress {
    description     = "HTTPS to interface VPC endpoints"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_endpoints.id]
  }

  # Receipts/deploy buckets and the AL2023 dnf repos, through the S3
  # gateway endpoint -- its prefix list is S3's regional IP ranges.
  egress {
    description     = "HTTPS to S3 via the gateway endpoint"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]
  }

  egress {
    description = "MySQL to the db tier"
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = var.db_subnet_cidrs
  }

  tags = {
    Name    = "${var.project_name}-app-sg"
    Project = var.project_name
  }
}

resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Allow inbound DB traffic from the app tier only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "DB port from app tier"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  # No egress at all: RDS only answers connections, it never opens them,
  # and SGs are stateful so replies to the app tier still flow. `egress =
  # []` (not just deleting the block) is what makes Terraform actually
  # remove AWS's default allow-all rule from an existing group.
  egress = []

  tags = {
    Name    = "${var.project_name}-db-sg"
    Project = var.project_name
  }
}

# --- IAM role for EC2: SSM access only, no SSH ------------------------------

resource "aws_iam_role" "app" {
  name = "${var.project_name}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name    = "${var.project_name}-app-role"
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Scoped narrowly to exactly the 2 buckets this role needs, and to exactly
# the actions each one needs -- read+write receipts (the app uploads them),
# read-only on deploy (the instance only ever downloads the bundle, never
# writes to it).
resource "aws_iam_role_policy" "s3_access" {
  name = "${var.project_name}-app-s3-access"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReceiptsReadWrite"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.receipts.arn}/*",
        ]
      },
      {
        Sid      = "DeployBundleReadOnly"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.deploy.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "db_secret_access" {
  name = "${var.project_name}-app-db-secret-access"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "ReadDbSecret"
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.db_credentials.arn
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.project_name}-app-profile"
  role = aws_iam_role.app.name
}
