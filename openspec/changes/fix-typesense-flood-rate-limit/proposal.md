# Proposal: fix-typesense-flood-rate-limit

## Why

The Typesense flood alert policy (`typesense_flood_alert`) sets `alert_strategy.notification_rate_limit`, but its condition is a `condition_threshold` on a user-defined log-based metric, which the Cloud Monitoring API classifies as a metric alert. The API rejects the policy at apply time with `Error 400: only log-based alert policies may specify a notification rate limit`, so any consumer enabling `flood_check` cannot apply (first observed in production adoption; the bug has been latent since the flood check was introduced because no consumer had enabled it). The module already documents this API constraint about itself in a comment on the Kyverno service. Tracking: refs platform/#4649.

## What Changes

- Remove the `notification_rate_limit` block from the `typesense_flood_alert` policy's `alert_strategy` (the `auto_close` setting stays).
- Remove the `flood_check.notification_rate_limit` variable field entirely. Keeping it as an inert deprecated field would silently ignore user intent (a consumer setting it expects throttling and gets none); a plan-time type error is explicit and self-explanatory. The break has effectively zero blast radius: the flood check has never applied successfully, so no consumer can be relying on the field.
- Notification frequency remains bounded by the alert's own dynamics: `ALIGN_RATE` over `alignment_period_seconds`, `duration_seconds` debounce, and `auto_close_seconds`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `typesense-log-alert`: the flood alert policy requirement changes — it MUST NOT render a notification rate limit, and the `notification_rate_limit` input is removed from the `flood_check` schema.

## Impact

- `typesense.tf`: delete the `notification_rate_limit` block from `typesense_flood_alert`.
- `variables.tf`: remove `flood_check.notification_rate_limit` from the object schema.
- `examples/main.tf`: drop the field from the flood_check example.
- `README.md`: regenerated terraform-docs block.
- `CHANGELOG.md`: Removed and Fixed entries under `[Unreleased]`; ships as a minor release (0.19.0, breaking interface change under 0.x semver).
- Consumers with `flood_check` enabled: apply succeeds; a consumer that sets `notification_rate_limit` gets a plan-time type error and must delete the attribute. Consumers not using `flood_check`: no plan diff.
