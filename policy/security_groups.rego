# Network exposure rules for security groups:
#   1. Nothing may accept traffic from the whole internet, except a group
#      explicitly tagged Exposure=internet-facing (the ALB) -- and even that
#      one only on 80/443.
#   2. No ingress may ever cover SSH (22) or RDP (3389), from any source.
#      Instance access goes through SSM Session Manager instead.
package terraform.security_groups

import data.lib.terraform

public_cidrs := {"0.0.0.0/0", "::/0"}

web_ports := {80, 443}

admin_ports := {22, 3389}

# Every ingress rule in the plan normalised to one shape, whether it's
# written inline in aws_security_group or as a standalone rule resource --
# otherwise a rule could dodge the policy just by being written differently.
ingress_rules contains rule if {
	some sg in terraform.resources_of_type("aws_security_group")
	some r in object.get(sg.change.after, "ingress", [])
	rule := {
		"address": sg.address,
		"from": r.from_port,
		"to": r.to_port,
		"protocol": r.protocol,
		"cidrs": cidrs(object.get(r, "cidr_blocks", []), object.get(r, "ipv6_cidr_blocks", [])),
		"internet_facing": internet_facing(sg.change.after),
	}
}

ingress_rules contains rule if {
	some r in terraform.resources_of_type("aws_security_group_rule")
	r.change.after.type == "ingress"
	rule := {
		"address": r.address,
		"from": r.change.after.from_port,
		"to": r.change.after.to_port,
		"protocol": r.change.after.protocol,
		"cidrs": cidrs(object.get(r.change.after, "cidr_blocks", []), object.get(r.change.after, "ipv6_cidr_blocks", [])),
		"internet_facing": false,
	}
}

ingress_rules contains rule if {
	some r in terraform.resources_of_type("aws_vpc_security_group_ingress_rule")
	after := r.change.after
	rule := {
		"address": r.address,
		"from": object.get(after, "from_port", null),
		"to": object.get(after, "to_port", null),
		"protocol": after.ip_protocol,
		"cidrs": {c | some c in [object.get(after, "cidr_ipv4", null), object.get(after, "cidr_ipv6", null)]; c != null},
		"internet_facing": internet_facing(after),
	}
}

cidrs(v4, v6) := {c | some c in v4} | {c | some c in v6}

# Must return false (not undefined) for untagged groups: an undefined value
# inside the rule object above would make OPA silently drop the whole rule,
# and the policy would never see any non-ALB group at all.
internet_facing(after) := object.get(after, ["tags_all", "Exposure"], "") == "internet-facing"

# Does this rule let traffic in on `port`? Protocol "-1" means every
# protocol and every port, so it always does.
covers(rule, _) if rule.protocol in {"-1", "all"}

covers(rule, port) if {
	rule.protocol in {"tcp", "6"}
	rule.from <= port
	port <= rule.to
}

web_only(rule) if {
	rule.protocol in {"tcp", "6"}
	rule.from == rule.to
	rule.from in web_ports
}

deny contains msg if {
	some rule in ingress_rules
	some cidr in rule.cidrs
	cidr in public_cidrs
	not rule.internet_facing
	msg := sprintf(
		"%s: ingress from %s is not allowed -- only a security group tagged Exposure=internet-facing may accept internet traffic",
		[rule.address, cidr],
	)
}

deny contains msg if {
	some rule in ingress_rules
	rule.internet_facing
	some cidr in rule.cidrs
	cidr in public_cidrs
	not web_only(rule)
	msg := sprintf(
		"%s: internet-facing group opens %v-%v/%s to %s -- only ports 80 and 443 may be public",
		[rule.address, rule.from, rule.to, rule.protocol, cidr],
	)
}

deny contains msg if {
	some rule in ingress_rules
	some port in admin_ports
	covers(rule, port)
	msg := sprintf(
		"%s: ingress covers admin port %d -- use SSM Session Manager instead of SSH/RDP",
		[rule.address, port],
	)
}
