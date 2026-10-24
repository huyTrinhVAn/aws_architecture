# Unit tests: `conftest verify --policy policy`
package terraform.security_groups_test

import data.terraform.security_groups

sg(address, ingress, tags) := {
	"address": address,
	"mode": "managed",
	"type": "aws_security_group",
	"change": {"actions": ["create"], "after": {"ingress": ingress, "tags_all": tags}},
}

rule(from, to, protocol, cidrs) := {
	"from_port": from,
	"to_port": to,
	"protocol": protocol,
	"cidr_blocks": cidrs,
	"ipv6_cidr_blocks": [],
}

plan(resources) := {"resource_changes": resources}

internet_facing := {"Exposure": "internet-facing"}

test_internet_facing_web_ports_allowed if {
	inp := plan([sg(
		"aws_security_group.alb", [
			rule(80, 80, "tcp", ["0.0.0.0/0"]),
			rule(443, 443, "tcp", ["0.0.0.0/0"]),
		],
		internet_facing,
	)])
	count(security_groups.deny) == 0 with input as inp
}

test_public_ingress_on_untagged_group_denied if {
	inp := plan([sg("aws_security_group.app", [rule(8080, 8080, "tcp", ["0.0.0.0/0"])], {})])
	count(security_groups.deny) == 1 with input as inp
}

test_internet_facing_group_non_web_port_denied if {
	inp := plan([sg("aws_security_group.alb", [rule(8080, 8080, "tcp", ["0.0.0.0/0"])], internet_facing)])
	count(security_groups.deny) == 1 with input as inp
}

test_internet_facing_group_port_range_denied if {
	inp := plan([sg("aws_security_group.alb", [rule(0, 65535, "tcp", ["0.0.0.0/0"])], internet_facing)])
	some msg in security_groups.deny with input as inp
	contains(msg, "only ports 80 and 443")
}

test_ssh_from_inside_vpc_still_denied if {
	inp := plan([sg("aws_security_group.app", [rule(22, 22, "tcp", ["10.0.0.0/16"])], {})])
	some msg in security_groups.deny with input as inp
	contains(msg, "admin port 22")
}

test_all_protocols_rule_covers_ssh_and_rdp if {
	inp := plan([sg("aws_security_group.app", [rule(0, 0, "-1", ["10.0.0.0/16"])], {})])
	count(security_groups.deny) == 2 with input as inp
}

test_private_app_port_allowed if {
	inp := plan([sg("aws_security_group.db", [rule(3306, 3306, "tcp", ["10.0.10.0/24"])], {})])
	count(security_groups.deny) == 0 with input as inp
}

test_standalone_rule_cannot_dodge_policy if {
	inp := plan([{
		"address": "aws_vpc_security_group_ingress_rule.ssh",
		"mode": "managed",
		"type": "aws_vpc_security_group_ingress_rule",
		"change": {"actions": ["create"], "after": {
			"from_port": 22, "to_port": 22, "ip_protocol": "tcp",
			"cidr_ipv4": "0.0.0.0/0", "tags_all": {},
		}},
	}])

	# one deny for the public CIDR, one for the admin port
	count(security_groups.deny) == 2 with input as inp
}

test_destroyed_group_ignored if {
	inp := plan([{
		"address": "aws_security_group.old",
		"mode": "managed",
		"type": "aws_security_group",
		"change": {"actions": ["delete"], "after": null},
	}])
	count(security_groups.deny) == 0 with input as inp
}
