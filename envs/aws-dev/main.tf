# The aws-dev environment: no resources of its own, only module calls and
# the wiring between them. Another environment (e.g. aws-prod) would be a
# sibling folder calling the same modules with different inputs and its
# own state file.

module "network" {
  source = "../../modules/aws-network"

  project_name        = var.project_name
  aws_region          = var.aws_region
  vpc_cidr            = var.vpc_cidr
  azs                 = var.azs
  public_subnet_cidrs = var.public_subnet_cidrs
  app_subnet_cidrs    = var.app_subnet_cidrs
  db_subnet_cidrs     = var.db_subnet_cidrs

  # Built here rather than inside the network module because it names this
  # environment's buckets: the S3 gateway endpoint may only reach the
  # project's own buckets plus the AWS-operated bucket backing AL2023's dnf
  # repos (the instances install python3-pip from it at boot).
  s3_endpoint_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ReceiptsReadWrite"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:PutObject", "s3:AbortMultipartUpload"]
        Resource  = "${module.storage.receipts_bucket_arn}/*"
      },
      {
        Sid       = "DeployBundleRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = "${module.storage.deploy_bucket_arn}/*"
      },
      {
        Sid       = "AmazonLinuxRepos"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = "arn:aws:s3:::al2023-repos-${var.aws_region}-de612dc2/*"
      },
    ]
  })
}

module "storage" {
  source = "../../modules/aws-storage"

  project_name = var.project_name
}

module "database" {
  source = "../../modules/aws-database"

  project_name               = var.project_name
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.db_subnet_ids
  port                       = var.db_port
  allowed_security_group_ids = [module.app.app_security_group_id]
}

module "app" {
  source = "../../modules/aws-app"

  project_name = var.project_name
  aws_region   = var.aws_region
  app_port     = var.app_port
  db_port      = var.db_port

  vpc_id                          = module.network.vpc_id
  public_subnet_ids               = module.network.public_subnet_ids
  app_subnet_ids                  = module.network.app_subnet_ids
  app_subnet_cidrs                = module.network.app_subnet_cidrs
  db_subnet_cidrs                 = module.network.db_subnet_cidrs
  vpc_endpoints_security_group_id = module.network.vpc_endpoints_security_group_id
  s3_prefix_list_id               = module.network.s3_prefix_list_id

  receipts_bucket_name      = module.storage.receipts_bucket_name
  receipts_bucket_arn       = module.storage.receipts_bucket_arn
  deploy_bucket_name        = module.storage.deploy_bucket_name
  deploy_bucket_arn         = module.storage.deploy_bucket_arn
  db_credentials_secret_arn = module.database.credentials_secret_arn
}

module "github_oidc" {
  source = "../../modules/aws-github-oidc"

  project_name          = var.project_name
  github_subject_prefix = "repo:huyTrinhVAn@*/aws_architecture@*"
  state_lock_object_arn = "arn:aws:s3:::sa-portfolio-tfstate-42ac9a0e/sa-portfolio/*"
  deploy_bucket_arn     = module.storage.deploy_bucket_arn
  deploy_asg_arn        = module.app.asg_arn
}
