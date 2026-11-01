# Phase 2 refactor: every resource from the old flat terraform/ folder,
# mapped to its new address inside a module. A `moved` block tells
# Terraform "same object, new name" -- without it, the plan would destroy
# each resource at its old address and create it again at the new one.
#
# Subnets and their route table associations also switch from count
# (index [0], [1]) to for_each (keyed by AZ), so each instance is moved
# individually.
#
# Keep these blocks until every copy of the state (every environment and
# every teammate's branch) has been applied past this refactor; removing
# one early turns that rename back into destroy + create.

# --- network ------------------------------------------------------------------

moved {
  from = aws_vpc.this
  to   = module.network.aws_vpc.this
}

moved {
  from = aws_default_security_group.default
  to   = module.network.aws_default_security_group.default
}

moved {
  from = aws_internet_gateway.this
  to   = module.network.aws_internet_gateway.this
}

moved {
  from = aws_subnet.public[0]
  to   = module.network.aws_subnet.public["us-east-1a"]
}

moved {
  from = aws_subnet.public[1]
  to   = module.network.aws_subnet.public["us-east-1b"]
}

moved {
  from = aws_subnet.app[0]
  to   = module.network.aws_subnet.app["us-east-1a"]
}

moved {
  from = aws_subnet.app[1]
  to   = module.network.aws_subnet.app["us-east-1b"]
}

moved {
  from = aws_subnet.db[0]
  to   = module.network.aws_subnet.db["us-east-1a"]
}

moved {
  from = aws_subnet.db[1]
  to   = module.network.aws_subnet.db["us-east-1b"]
}

moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}

moved {
  from = aws_route_table.app
  to   = module.network.aws_route_table.app
}

moved {
  from = aws_route_table.db
  to   = module.network.aws_route_table.db
}

moved {
  from = aws_route_table_association.public[0]
  to   = module.network.aws_route_table_association.public["us-east-1a"]
}

moved {
  from = aws_route_table_association.public[1]
  to   = module.network.aws_route_table_association.public["us-east-1b"]
}

moved {
  from = aws_route_table_association.app[0]
  to   = module.network.aws_route_table_association.app["us-east-1a"]
}

moved {
  from = aws_route_table_association.app[1]
  to   = module.network.aws_route_table_association.app["us-east-1b"]
}

moved {
  from = aws_route_table_association.db[0]
  to   = module.network.aws_route_table_association.db["us-east-1a"]
}

moved {
  from = aws_route_table_association.db[1]
  to   = module.network.aws_route_table_association.db["us-east-1b"]
}

moved {
  from = aws_vpc_endpoint.s3
  to   = module.network.aws_vpc_endpoint.s3
}

moved {
  from = aws_security_group.vpc_endpoints
  to   = module.network.aws_security_group.vpc_endpoints
}

# Renamed as well as moved (ssm -> interface: it holds more than SSM).
# Moving the whole resource carries every for_each key (["ssm"],
# ["secretsmanager"], ...) across unchanged.
moved {
  from = aws_vpc_endpoint.ssm
  to   = module.network.aws_vpc_endpoint.interface
}

# --- storage ------------------------------------------------------------------

moved {
  from = random_id.bucket_suffix
  to   = module.storage.random_id.bucket_suffix
}

moved {
  from = aws_s3_bucket.receipts
  to   = module.storage.aws_s3_bucket.receipts
}

moved {
  from = aws_s3_bucket_public_access_block.receipts
  to   = module.storage.aws_s3_bucket_public_access_block.receipts
}

moved {
  from = aws_s3_bucket_versioning.receipts
  to   = module.storage.aws_s3_bucket_versioning.receipts
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.receipts
  to   = module.storage.aws_s3_bucket_server_side_encryption_configuration.receipts
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.receipts
  to   = module.storage.aws_s3_bucket_lifecycle_configuration.receipts
}

moved {
  from = aws_s3_bucket.deploy
  to   = module.storage.aws_s3_bucket.deploy
}

moved {
  from = aws_s3_bucket_public_access_block.deploy
  to   = module.storage.aws_s3_bucket_public_access_block.deploy
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.deploy
  to   = module.storage.aws_s3_bucket_server_side_encryption_configuration.deploy
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.deploy
  to   = module.storage.aws_s3_bucket_lifecycle_configuration.deploy
}

# --- database -----------------------------------------------------------------

moved {
  from = aws_security_group.db
  to   = module.database.aws_security_group.db
}

moved {
  from = aws_db_subnet_group.this
  to   = module.database.aws_db_subnet_group.this
}

moved {
  from = random_password.db_master
  to   = module.database.random_password.db_master
}

moved {
  from = aws_db_instance.this
  to   = module.database.aws_db_instance.this
}

moved {
  from = aws_secretsmanager_secret.db_credentials
  to   = module.database.aws_secretsmanager_secret.db_credentials
}

moved {
  from = aws_secretsmanager_secret_version.db_credentials
  to   = module.database.aws_secretsmanager_secret_version.db_credentials
}

# --- app ----------------------------------------------------------------------

moved {
  from = aws_security_group.alb
  to   = module.app.aws_security_group.alb
}

moved {
  from = aws_security_group.app
  to   = module.app.aws_security_group.app
}

moved {
  from = aws_iam_role.app
  to   = module.app.aws_iam_role.app
}

moved {
  from = aws_iam_role_policy_attachment.ssm
  to   = module.app.aws_iam_role_policy_attachment.ssm
}

moved {
  from = aws_iam_role_policy.s3_access
  to   = module.app.aws_iam_role_policy.s3_access
}

moved {
  from = aws_iam_role_policy.db_secret_access
  to   = module.app.aws_iam_role_policy.db_secret_access
}

moved {
  from = aws_iam_instance_profile.app
  to   = module.app.aws_iam_instance_profile.app
}

moved {
  from = aws_launch_template.app
  to   = module.app.aws_launch_template.app
}

moved {
  from = aws_lb.this
  to   = module.app.aws_lb.this
}

moved {
  from = aws_lb_target_group.app
  to   = module.app.aws_lb_target_group.app
}

moved {
  from = aws_lb_listener.http
  to   = module.app.aws_lb_listener.http
}

moved {
  from = aws_autoscaling_group.app
  to   = module.app.aws_autoscaling_group.app
}

moved {
  from = aws_autoscaling_policy.cpu_target_tracking
  to   = module.app.aws_autoscaling_policy.cpu_target_tracking
}

# --- github_oidc (renamed inside the module: github_actions_ci -> ci, ...) ----

moved {
  from = aws_iam_openid_connect_provider.github
  to   = module.github_oidc.aws_iam_openid_connect_provider.github
}

moved {
  from = aws_iam_role.github_actions_ci
  to   = module.github_oidc.aws_iam_role.ci
}

moved {
  from = aws_iam_role_policy_attachment.github_actions_ci_readonly
  to   = module.github_oidc.aws_iam_role_policy_attachment.ci_readonly
}

moved {
  from = aws_iam_role_policy.github_actions_ci_state_lock
  to   = module.github_oidc.aws_iam_role_policy.ci_state_lock
}

moved {
  from = aws_iam_role.github_actions_deploy
  to   = module.github_oidc.aws_iam_role.deploy
}

moved {
  from = aws_iam_role_policy.github_actions_deploy_s3
  to   = module.github_oidc.aws_iam_role_policy.deploy_s3
}

moved {
  from = aws_iam_role_policy.github_actions_deploy_refresh
  to   = module.github_oidc.aws_iam_role_policy.deploy_refresh
}

moved {
  from = aws_iam_role.github_actions_apply
  to   = module.github_oidc.aws_iam_role.apply
}

moved {
  from = aws_iam_role_policy_attachment.github_actions_apply_admin
  to   = module.github_oidc.aws_iam_role_policy_attachment.apply_admin
}
