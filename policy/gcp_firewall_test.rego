# Unit tests: `conftest verify --policy policy`
package terraform.gcp_firewall_test

import data.terraform.gcp_firewall

fw(address, action, protocol, ports, sources) := {
	"address": address,
	"mode": "managed",
	"type": "google_compute_firewall",
	"change": {"actions": ["create"], "after": {
		"direction": "INGRESS",
		"disabled": false,
		action: [{"protocol": protocol, "ports": ports}],
		"source_ranges": sources,
	}},
}

plan(resources) := {"resource_changes": resources}

test_health_check_ranges_allowed if {
	inp := plan([fw("google_compute_firewall.hc", "allow", "tcp", ["8080"], ["35.191.0.0/16", "130.211.0.0/22"])])
	count(gcp_firewall.deny) == 0 with input as inp
}

test_ssh_from_iap_allowed if {
	inp := plan([fw("google_compute_firewall.iap", "allow", "tcp", ["22"], ["35.235.240.0/20"])])
	count(gcp_firewall.deny) == 0 with input as inp
}

test_baseline_deny_from_internet_ignored if {
	inp := plan([fw("google_compute_firewall.deny_all", "deny", "all", [], ["0.0.0.0/0"])])
	count(gcp_firewall.deny) == 0 with input as inp
}

test_allow_from_internet_denied if {
	inp := plan([fw("google_compute_firewall.web", "allow", "tcp", ["443"], ["0.0.0.0/0"])])
	count(gcp_firewall.deny) == 1 with input as inp
}

test_ssh_from_vpc_range_denied if {
	inp := plan([fw("google_compute_firewall.ssh", "allow", "tcp", ["22"], ["10.10.0.0/24"])])
	some msg in gcp_firewall.deny with input as inp
	contains(msg, "admin port 22")
}

test_port_range_covering_rdp_denied if {
	inp := plan([fw("google_compute_firewall.wide", "allow", "tcp", ["3000-4000"], ["10.10.0.0/24"])])
	some msg in gcp_firewall.deny with input as inp
	contains(msg, "admin port 3389")
}

test_tcp_without_ports_covers_ssh_and_rdp if {
	inp := plan([fw("google_compute_firewall.any", "allow", "tcp", [], ["10.10.0.0/24"])])
	count(gcp_firewall.deny) == 2 with input as inp
}

test_ssh_from_internet_reports_both_problems if {
	inp := plan([fw("google_compute_firewall.ssh", "allow", "tcp", ["22"], ["0.0.0.0/0"])])
	count(gcp_firewall.deny) == 2 with input as inp
}
