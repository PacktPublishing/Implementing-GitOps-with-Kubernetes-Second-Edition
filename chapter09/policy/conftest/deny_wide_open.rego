# Policy evaluated against an OpenTofu plan in JSON, in CI, before the change
# is merged. The controller applies what is in the default branch, so the
# branch is where the gate belongs.
#
#   tofu show -json tfplan > plan.json
#   conftest test --policy policy/conftest plan.json
#
# No `import rego.v1`: since OPA 1.0 that import has been a no-op, and current
# Conftest defaults to Rego v1 syntax.

package main

# Storage accounts being created or changed. Deletions carry no `after` object,
# so filtering them out here keeps every rule below from having to.
storage_account_changes contains change if {
	some change in input.resource_changes
	change.type == "azurerm_storage_account"
	not "delete" in change.change.actions
}

# A storage account reachable from the public internet is never intended here.
deny contains msg if {
	some change in storage_account_changes
	change.change.after.public_network_access_enabled == true
	msg := sprintf("%s allows public network access", [change.address])
}

# `after` omits any value that is still unknown at plan time -- those appear in
# `after_unknown` instead. A gate that reads only `after` passes silently when
# the setting comes from an unresolved reference, which is the failure mode
# that matters most for a rule like this one.
deny contains msg if {
	some change in storage_account_changes
	change.change.after_unknown.public_network_access_enabled
	msg := sprintf("%s leaves public network access unknown at plan time", [change.address])
}

# Shared keys defeat the point of federated identity.
deny contains msg if {
	some change in storage_account_changes
	change.change.after.shared_access_key_enabled == true
	msg := sprintf("%s enables shared access keys", [change.address])
}

deny contains msg if {
	some change in storage_account_changes
	change.change.after_unknown.shared_access_key_enabled
	msg := sprintf("%s leaves shared access keys unknown at plan time", [change.address])
}

# Anything that deletes rather than replaces should be seen by a human first.
warn contains msg if {
	some change in input.resource_changes
	"delete" in change.change.actions
	not "create" in change.change.actions
	msg := sprintf("%s will be destroyed", [change.address])
}

# Every resource carries the environment tag the estate is queried by.
deny contains msg if {
	some change in input.resource_changes
	startswith(change.type, "azurerm_")
	change.change.after.tags
	not change.change.after.tags.environment
	msg := sprintf("%s has no environment tag", [change.address])
}
