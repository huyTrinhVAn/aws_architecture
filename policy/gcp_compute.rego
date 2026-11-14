# Hardening rules for GCP VMs, whether defined directly (google_compute_instance)
# or through an instance template used by a managed instance group:
#   1. No external IP: VMs are reached through the load balancer or IAP,
#      and go out through Cloud NAT.
#   2. Shielded VM with Secure Boot on.
#   3. Never the Compute Engine default service account -- every workload
#      gets its own, least-privilege identity.
package terraform.gcp_compute

import data.lib.terraform

vm_types := {"google_compute_instance", "google_compute_instance_template", "google_compute_region_instance_template"}

vms contains vm if {
	some t in vm_types
	some vm in terraform.resources_of_type(t)
}

deny contains msg if {
	some vm in vms
	some nic in object.get(vm.change.after, "network_interface", [])
	count(object.get(nic, "access_config", [])) > 0
	msg := sprintf("%s: has an external IP (access_config) -- use the load balancer, IAP and Cloud NAT instead", [vm.address])
}

deny contains msg if {
	some vm in vms
	not secure_boot(vm.change.after)
	msg := sprintf("%s: Shielded VM Secure Boot must be enabled", [vm.address])
}

deny contains msg if {
	some vm in vms
	some sa in object.get(vm.change.after, "service_account", [])
	endswith(object.get(sa, "email", ""), "-compute@developer.gserviceaccount.com")
	msg := sprintf("%s: uses the Compute Engine default service account -- give the workload its own", [vm.address])
}

secure_boot(after) if {
	some cfg in object.get(after, "shielded_instance_config", [])
	cfg.enable_secure_boot == true
}
