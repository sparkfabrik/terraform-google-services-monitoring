# Proposal: typesense-per-check-notifications

## Why

Typesense notification routing is all-or-nothing at the service level: every check of every app notifies the same resolved channel list. Real operations need finer control — some alerts should exist purely as visible incidents without notifying anyone (dashboards and incident history still work), and others should notify a different or narrower channel set than the service default (for example a low-urgency channel for stage saturation warnings). Tracking: refs platform/#4649.

## What Changes

- Every Typesense check block (`uptime_check`, `container_check`, `log_check`, `flood_check`, `workload_check`) gains two optional fields:
  - `notification_enabled = optional(bool, null)` — tri-state; `null` inherits the service-level setting, `false` makes the check's policies silent (no channels), `true` forces notifications on even when the service level disables them.
  - `notification_channels = optional(list(string), null)` — `null` inherits (service override, then root); a non-null list is used as-is for that check's policies.
- Resolution order, block-explicit always wins: `effective_enabled = coalesce(block, service)`; `effective_channels = effective_enabled ? coalesce(block_channels, service_or_root_channels) : []`.
- `uptime_check` passes the resolved list to the `http_monitoring` submodule via its existing `alert_notification_channels` input; failure alert policies of the submodule follow it. No submodule interface change.
- Within `workload_check`, all policies of the block (threshold families and replica availability) share the block's setting.
- Non-breaking: both fields default to `null`, reproducing today's behavior exactly; consumers upgrading without config changes get a zero-change plan.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `typesense-config-schema`: the notification resolution contract (per-check tri-state toggle and channel override, inheritance rules) joins the cross-cutting schema spec.
- `typesense-workload-vitals`: the notification cascade requirement extends with the per-block override and silent-alert scenarios.
- `typesense-log-alert`: log and flood policies honor the per-block notification fields.

## Impact

- `variables.tf`: two new optional fields on each of the five check blocks; no validation changes (an empty override list is legal and equivalent to disabling notifications for that check).
- `typesense.tf`: per-app-per-check channel resolution locals replace the single service-level local where policies reference channels.
- `examples/main.tf` / `examples/test.tfvars`: one silent check and one channel-override example.
- `README.md` regenerated; `CHANGELOG.md` Added entries under `[Unreleased]`; ships as a normal (non-breaking) minor release.
