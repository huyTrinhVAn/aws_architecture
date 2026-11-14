# Network exposure rules for GCP firewall rules -- the GCP counterpart of
# security_groups.rego:
#   1. No ALLOW ingress rule may take traffic from the whole internet. The
#      public entry point is the external load balancer, which runs on
#      Google's edge and needs no firewall rule; the VMs only ever see
#      Google's health-check/proxy ranges.
#   2. SSH (22) and RDP (3389) may only be opened to IAP's range
#      (35.235.240.0/20), so every admin session goes through IAP's IAM check.
# DENY rules are ignored: a deny from 0.0.0.0/0 is the baseline, not a hole.
package terraform.gcp_firewall

import data.lib.terraform

public_cidrs := {"0.0.0.0/0", "::/0"}

iap_range := "35.235.240.0/20"

admin_ports := {22, 3389}

ingress_allows contains rule if {
	some fw in terraform.resources_of_type("google_compute_firewall")
	after := fw.change.after
	object.get(after, "direction", "INGRESS") == "INGRESS"
	not object.get(after, "disabled", false)
	some allow in object.get(after, "allow", [])
	rule := {
		"address": fw.address,
		"protocol": allow.protocol,
		"ports": object.get(allow, "ports", []),
		"sources": {r | some r in object.get(after, "source_ranges", [])},
	}
}

# Does this allow block let traffic in on `port`? "all" means every protocol;
# an empty ports list means every port of that protocol.
covers(rule, _) if rule.protocol in {"all", "-1"}

covers(rule, _) if {
	rule.protocol in {"tcp", "6"}
	count(rule.ports) == 0
}

covers(rule, port) if {
	rule.protocol in {"tcp", "6"}
	some p in rule.ports
	in_range(p, port)
}

in_range(p, port) if {
	not contains(p, "-")
	to_number(p) == port
}

in_range(p, port) if {
	bounds := split(p, "-")
	to_number(bounds[0]) <= port
	port <= to_number(bounds[1])
}

deny contains msg if {
	some rule in ingress_allows
	some cidr in rule.sources
	cidr in public_cidrs
	msg := sprintf(
		"%s: allows ingress from %s -- VMs must only be reachable through the load balancer or IAP",
		[rule.address, cidr],
	)
}

deny contains msg if {
	some rule in ingress_allows
	some port in admin_ports
	covers(rule, port)
	some cidr in rule.sources
	cidr != iap_range
	msg := sprintf(
		"%s: opens admin port %d to %s -- only IAP's range %s may reach SSH/RDP",
		[rule.address, port, cidr, iap_range],
	)
}
