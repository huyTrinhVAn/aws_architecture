package terraform.encryption_test

import data.terraform.encryption

resource(type, address, after) := {
	"address": address,
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after},
}

sse_config(bucket_name) := {
	"type": "aws_s3_bucket_server_side_encryption_configuration",
	"expressions": {"bucket": {"references": [
		sprintf("aws_s3_bucket.%s.id", [bucket_name]),
		sprintf("aws_s3_bucket.%s", [bucket_name]),
	]}},
}

plan(resources, config) := {
	"resource_changes": resources,
	"configuration": {"root_module": {"resources": config}},
}

test_unencrypted_rds_denied if {
	inp := plan([resource("aws_db_instance", "aws_db_instance.this", {"storage_encrypted": false})], [])
	count(encryption.deny) == 1 with input as inp
}

test_rds_missing_flag_denied if {
	inp := plan([resource("aws_db_instance", "aws_db_instance.this", {})], [])
	count(encryption.deny) == 1 with input as inp
}

test_encrypted_rds_allowed if {
	inp := plan([resource("aws_db_instance", "aws_db_instance.this", {"storage_encrypted": true})], [])
	count(encryption.deny) == 0 with input as inp
}

test_unencrypted_ebs_denied if {
	inp := plan([resource("aws_ebs_volume", "aws_ebs_volume.data", {"encrypted": false})], [])
	count(encryption.deny) == 1 with input as inp
}

test_bucket_without_sse_config_denied if {
	inp := plan([resource("aws_s3_bucket", "aws_s3_bucket.logs", {})], [sse_config("other")])
	some msg in encryption.deny with input as inp
	contains(msg, "aws_s3_bucket.logs")
}

test_bucket_with_sse_config_allowed if {
	inp := plan([resource("aws_s3_bucket", "aws_s3_bucket.receipts", {})], [sse_config("receipts")])
	count(encryption.deny) == 0 with input as inp
}

test_counted_bucket_matched_by_base_address if {
	inp := plan([resource("aws_s3_bucket", "aws_s3_bucket.logs[0]", {})], [sse_config("logs")])
	count(encryption.deny) == 0 with input as inp
}

# Buckets inside modules: the Phase 2 refactor moved every bucket into
# module.storage, and the first version of this policy only looked at the
# root module -- it silently passed a module bucket with no encryption.

module_plan(resources, module_name, config) := {
	"resource_changes": resources,
	"configuration": {"root_module": {
		"resources": [],
		"module_calls": {module_name: {"module": {"resources": config}}},
	}},
}

test_module_bucket_with_sse_config_allowed if {
	inp := module_plan(
		[resource("aws_s3_bucket", "module.storage.aws_s3_bucket.receipts", {})],
		"storage", [sse_config("receipts")],
	)
	count(encryption.deny) == 0 with input as inp
}

test_module_bucket_without_sse_config_denied if {
	inp := module_plan(
		[resource("aws_s3_bucket", "module.storage.aws_s3_bucket.deploy", {})],
		"storage", [sse_config("receipts")],
	)
	some msg in encryption.deny with input as inp
	contains(msg, "module.storage.aws_s3_bucket.deploy")
}

test_same_bucket_name_in_other_module_does_not_count if {
	# an SSE config for aws_s3_bucket.deploy in module.other must not
	# satisfy module.storage's aws_s3_bucket.deploy
	inp := module_plan(
		[resource("aws_s3_bucket", "module.storage.aws_s3_bucket.deploy", {})],
		"other", [sse_config("deploy")],
	)
	count(encryption.deny) == 1 with input as inp
}

test_nested_module_bucket_allowed if {
	inp := {
		"resource_changes": [resource("aws_s3_bucket", "module.app.module.logs.aws_s3_bucket.this", {})],
		"configuration": {"root_module": {"module_calls": {"app": {"module": {"module_calls": {"logs": {"module": {"resources": [sse_config("this")]}}}}}}}},
	}
	count(encryption.deny) == 0 with input as inp
}

test_for_each_module_instance_matched if {
	inp := module_plan(
		[resource("aws_s3_bucket", `module.storage["eu"].aws_s3_bucket.receipts`, {})],
		"storage", [sse_config("receipts")],
	)
	count(encryption.deny) == 0 with input as inp
}
