# Helpers shared by every policy. Policies run against the JSON form of a
# plan (`terraform show -json tfplan`), not against .tf files -- so they see
# final values after variables, count/for_each and default_tags are applied.
package lib.terraform

# Every managed resource that will exist once this plan is applied
# (created, updated or unchanged). A resource being destroyed has
# `after == null`, so it can't violate anything and is skipped.
resources contains rc if {
	some rc in input.resource_changes
	rc.mode == "managed"
	rc.change.after != null
}

resources_of_type(type) := {rc | some rc in resources; rc.type == type}
