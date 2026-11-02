package terraform.stateful_deletes_test

import data.terraform.stateful_deletes

change(type, actions, before) := {"resource_changes": [{
	"address": sprintf("%s.this", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": actions, "before": before, "after": null},
}]}

db_state := {"identifier": "sa-portfolio-db", "tags_all": {"Project": "sa-portfolio"}}

test_deleting_database_denied if {
	some msg in stateful_deletes.deny with input as change("aws_db_instance", ["delete"], db_state)
	contains(msg, "DELETE")
}

test_replacing_database_denied if {
	# a "forces replacement" change is a delete too, just with a create after it
	some msg in stateful_deletes.deny with input as change("aws_db_instance", ["delete", "create"], db_state)
	contains(msg, "REPLACE")
}

test_create_before_destroy_replacement_denied if {
	count(stateful_deletes.deny) == 1 with input as change("aws_s3_bucket", ["create", "delete"], {"tags_all": {}})
}

test_deletion_approved_by_tag_allowed if {
	approved := {"identifier": "sa-portfolio-db", "tags_all": {"AllowDestroy": "true"}}
	count(stateful_deletes.deny) == 0 with input as change("aws_db_instance", ["delete"], approved)
}

test_tag_with_other_value_not_approved if {
	approved := {"tags_all": {"AllowDestroy": "yes"}}
	count(stateful_deletes.deny) == 1 with input as change("aws_db_instance", ["delete"], approved)
}

test_deleting_stateless_resource_allowed if {
	count(stateful_deletes.deny) == 0 with input as change("aws_security_group", ["delete"], {"tags_all": {}})
}

test_updating_database_allowed if {
	inp := {"resource_changes": [{
		"address": "aws_db_instance.this",
		"mode": "managed",
		"type": "aws_db_instance",
		"change": {"actions": ["update"], "before": db_state, "after": db_state},
	}]}
	count(stateful_deletes.deny) == 0 with input as inp
}

test_moved_database_allowed if {
	# what a correct `moved` block produces: no-op at the new address
	inp := {"resource_changes": [{
		"address": "module.database.aws_db_instance.this",
		"previous_address": "aws_db_instance.this",
		"mode": "managed",
		"type": "aws_db_instance",
		"change": {"actions": ["no-op"], "before": db_state, "after": db_state},
	}]}
	count(stateful_deletes.deny) == 0 with input as inp
}

test_data_source_ignored if {
	inp := {"resource_changes": [{
		"address": "data.aws_db_instance.this",
		"mode": "data",
		"type": "aws_db_instance",
		"change": {"actions": ["delete"], "before": {}, "after": null},
	}]}
	count(stateful_deletes.deny) == 0 with input as inp
}
