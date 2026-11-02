# A plan may never delete (or replace, which is delete + create) a resource
# that holds data, unless that deletion was approved beforehand.
#
# Why: Terraform matches resources by address. A refactor that forgets a
# `moved` block, a renamed resource, or a change to a "forces replacement"
# argument all show up in the plan as a delete of the old object -- and for
# RDS with skip_final_snapshot, that's permanent data loss.
#
# Approving a deletion is a two-step, two-PR process on purpose: first
# merge a PR that only adds the tag AllowDestroy = "true" to the resource
# (reviewed on its own, visible in the plan), then the PR that deletes it
# passes. The tag is read from the resource's state (`before`), so it can't
# be added in the same PR that deletes the resource.
package terraform.stateful_deletes

stateful_types := {
	"aws_db_instance",
	"aws_rds_cluster",
	"aws_s3_bucket",
	"aws_dynamodb_table",
	"aws_efs_file_system",
	"aws_ebs_volume",
	"aws_elasticache_replication_group",
}

deny contains msg if {
	some rc in input.resource_changes
	rc.mode == "managed"
	rc.type in stateful_types
	"delete" in rc.change.actions
	not destroy_approved(rc)
	msg := sprintf(
		"%s: plan would %s a stateful resource -- data loss. If this is a rename, add a `moved` block; to delete it on purpose, first merge a PR that tags it AllowDestroy=true",
		[rc.address, verb(rc.change.actions)],
	)
}

destroy_approved(rc) if object.get(rc.change.before, ["tags_all", "AllowDestroy"], "") == "true"

verb(actions) := "REPLACE (delete + re-create)" if "create" in actions

verb(actions) := "DELETE" if not "create" in actions
