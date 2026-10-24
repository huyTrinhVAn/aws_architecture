package terraform.tags_test

import data.terraform.tags

resource(type, after) := {
	"address": sprintf("%s.this", [type]),
	"mode": "managed",
	"type": type,
	"change": {"actions": ["create"], "after": after},
}

test_fully_tagged_resource_allowed if {
	inp := {"resource_changes": [resource("aws_vpc", {"tags_all": {"Project": "p", "ManagedBy": "terraform"}})]}
	count(tags.deny) == 0 with input as inp
}

test_missing_tags_denied_once_per_tag if {
	inp := {"resource_changes": [resource("aws_vpc", {"tags_all": {"Name": "x"}})]}
	count(tags.deny) == 2 with input as inp
}

test_empty_tag_value_denied if {
	inp := {"resource_changes": [resource("aws_vpc", {"tags_all": {"Project": "", "ManagedBy": "terraform"}})]}
	count(tags.deny) == 1 with input as inp
}

test_untaggable_resource_ignored if {
	inp := {"resource_changes": [resource("aws_route_table_association", {"subnet_id": "x"})]}
	count(tags.deny) == 0 with input as inp
}

test_non_aws_resource_ignored if {
	inp := {"resource_changes": [resource("random_id", {"tags_all": {}})]}
	count(tags.deny) == 0 with input as inp
}
