# Data at rest must be encrypted: RDS storage, EBS volumes, and every S3
# bucket must have an explicit server-side encryption configuration.
package terraform.encryption

import data.lib.terraform

deny contains msg if {
	some type in {"aws_db_instance", "aws_rds_cluster"}
	some db in terraform.resources_of_type(type)
	object.get(db.change.after, "storage_encrypted", false) != true
	msg := sprintf("%s: storage_encrypted must be true", [db.address])
}

deny contains msg if {
	some vol in terraform.resources_of_type("aws_ebs_volume")
	object.get(vol.change.after, "encrypted", false) != true
	msg := sprintf("%s: encrypted must be true", [vol.address])
}

# Buckets with an aws_s3_bucket_server_side_encryption_configuration
# pointing at them. Read from the plan's `configuration` section because
# the link between the two is a reference (`aws_s3_bucket.x.id`) -- the
# actual bucket id isn't known until apply. Covers the root module only;
# revisit when Phase 2 moves buckets into modules.
encrypted_buckets contains ref if {
	some r in input.configuration.root_module.resources
	r.type == "aws_s3_bucket_server_side_encryption_configuration"
	some ref in r.expressions.bucket.references
	regex.match(`^aws_s3_bucket\.[^.]+$`, ref)
}

deny contains msg if {
	some bucket in terraform.resources_of_type("aws_s3_bucket")
	not bucket.module_address
	base := regex.replace(bucket.address, `\[[^\]]*\]$`, "")
	not base in encrypted_buckets
	msg := sprintf("%s: no aws_s3_bucket_server_side_encryption_configuration references this bucket", [bucket.address])
}
