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

# Every module in the plan's configuration, with the address prefix its
# resources get: "" for the root module, "module.storage." for a module
# call named storage, "module.a.module.b." for a nested one. In the JSON,
# a module call's body sits at <parent>.module_calls.<name>.module, so a
# module's path is made of ["module_calls", <name>, "module"] triples.
modules contains [prefix, mod] if {
	walk(input.configuration.root_module, [path, mod])
	is_module_path(path)
	prefix := concat("", [sprintf("module.%s.", [path[i + 1]]) | some i, step in path; step == "module_calls"])
}

is_module_path(path) if count(path) == 0

is_module_path(path) if {
	count(path) > 0
	count(path) % 3 == 0
	every i in numbers.range_step(0, count(path) - 3, 3) {
		path[i] == "module_calls"
		path[i + 2] == "module"
	}
}

# Buckets with an aws_s3_bucket_server_side_encryption_configuration
# pointing at them, as full addresses (module prefix + aws_s3_bucket.x).
# Read from the plan's `configuration` section because the link between
# the two is a reference (`aws_s3_bucket.x.id`) -- the actual bucket id
# isn't known until apply. Limitation: an SSE config in a different module
# from its bucket (bucket passed in as a variable) isn't matched, and the
# bucket is reported -- a false alarm, never a silent pass.
encrypted_buckets contains address if {
	some [prefix, mod] in modules
	some r in object.get(mod, "resources", [])
	r.type == "aws_s3_bucket_server_side_encryption_configuration"
	some ref in r.expressions.bucket.references
	regex.match(`^aws_s3_bucket\.[^.]+$`, ref)
	address := concat("", [prefix, ref])
}

deny contains msg if {
	some bucket in terraform.resources_of_type("aws_s3_bucket")

	# Configuration addresses carry no instance keys, so strip every
	# [0] / ["key"] (on the bucket and on any module call in its path).
	base := regex.replace(bucket.address, `\[[^\]]*\]`, "")
	not base in encrypted_buckets
	msg := sprintf("%s: no aws_s3_bucket_server_side_encryption_configuration references this bucket", [bucket.address])
}
