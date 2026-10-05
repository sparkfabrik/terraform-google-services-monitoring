## Why

Cloud Armor Adaptive Protection detects layer 7 DDoS attacks on every project where it is enabled, but its alerts only land in Cloud Logging and Security Command Center, where nobody watches them. Projects that want a notification have to write the same log-based alert policy locally (LUISS did in operations-gcp!233). A module alert gives every Cloud Armor project the same versioned, Renovate-propagated notification.

## What Changes

- Add a `cloud_armor_adaptive_protection` alert: a log-based `google_monitoring_alert_policy` on the `networksecurity.googleapis.com/dos_attack` log, scoped to the listed security policies.
- Add a `cloud_armor_adaptive_protection` input variable following the per-service convention (`enabled` default `false`, `project_id`, `notification_enabled`, `notification_channels`, `user_labels`) plus `security_policies`, `verify_adaptive_protection_enabled`, `severity`, `auto_close_seconds` and `notification_rate_limit_seconds`.
- Verify at plan time that Adaptive Protection is enabled on every listed policy, through the `google_compute_security_policy` data source, and fail with the names of the policies where it is not.
- Add a `cloud_armor_adaptive_protection_alert_policy_name` output, an example, the regenerated README and a CHANGELOG entry.

## Capabilities

### New Capabilities

- `cloud-armor-adaptive-protection-alert`: a notification on every attack Cloud Armor Adaptive Protection detects on the listed security policies, refused at plan time when Adaptive Protection is not enabled on them.

### Modified Capabilities

<!-- None. -->

## Impact

- **Module**: new `cloud_armor_adaptive_protection.tf`, new variable, new output, example, README, CHANGELOG. Additive, no consumer action.
- **Consumers**: opt-in. A consumer that already has a local copy of the alert can adopt the module one with a `moved` block, so the alert policy is moved instead of destroyed and recreated.
