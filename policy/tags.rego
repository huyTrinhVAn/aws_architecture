# Every taggable AWS resource must carry the tags cost reports and
# ownership lookups depend on. In practice the provider's default_tags
# (terraform/provider.tf) supply them -- this policy catches a resource
# that ends up outside that provider, or a default_tags block removed.
package terraform.tags

import data.lib.terraform

required_tags := {"Project", "ManagedBy"}

deny contains msg if {
	some rc in terraform.resources
	startswith(rc.type, "aws_")

	# Only taggable resources have tags_all, so this line also skips
	# associations, policies and other untaggable types.
	tags := rc.change.after.tags_all
	is_object(tags)

	some tag in required_tags
	object.get(tags, tag, "") == ""
	msg := sprintf("%s: missing required tag %q", [rc.address, tag])
}
