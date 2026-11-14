# Unit tests: `conftest verify --policy policy`
package terraform.gcp_compute_test

import data.terraform.gcp_compute

template(access_config, secure_boot, sa_email) := {
	"address": "google_compute_instance_template.app",
	"mode": "managed",
	"type": "google_compute_instance_template",
	"change": {"actions": ["create"], "after": {
		"network_interface": [{"access_config": access_config}],
		"shielded_instance_config": [{"enable_secure_boot": secure_boot}],
		"service_account": [{"email": sa_email}],
	}},
}

plan(resources) := {"resource_changes": resources}

own_sa := "sa-app-vm@sa-dev-app.iam.gserviceaccount.com"

test_hardened_template_allowed if {
	count(gcp_compute.deny) == 0 with input as plan([template([], true, own_sa)])
}

# A service account created in the same plan has no email yet: Terraform
# leaves unknown values out of `after`. That must not count as a violation.
test_unknown_service_account_allowed if {
	t := json.remove(template([], true, own_sa), ["change/after/service_account"])
	count(gcp_compute.deny) == 0 with input as plan([t])
}

test_external_ip_denied if {
	inp := plan([template([{"nat_ip": ""}], true, own_sa)])
	some msg in gcp_compute.deny with input as inp
	contains(msg, "external IP")
}

test_secure_boot_off_denied if {
	inp := plan([template([], false, own_sa)])
	some msg in gcp_compute.deny with input as inp
	contains(msg, "Secure Boot")
}

test_missing_shielded_config_denied if {
	t := json.remove(template([], true, own_sa), ["change/after/shielded_instance_config"])
	some msg in gcp_compute.deny with input as plan([t])
	contains(msg, "Secure Boot")
}

test_default_service_account_denied if {
	inp := plan([template([], true, "123456789-compute@developer.gserviceaccount.com")])
	some msg in gcp_compute.deny with input as inp
	contains(msg, "default service account")
}
