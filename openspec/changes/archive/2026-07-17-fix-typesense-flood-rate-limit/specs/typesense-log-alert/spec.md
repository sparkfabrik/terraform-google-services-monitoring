# typesense-log-alert (delta)

## MODIFIED Requirements

### Requirement: Flood alert policy per Typesense app with flood_check

The module SHALL create a `google_monitoring_alert_policy` with a `condition_threshold` condition for each Typesense app that has `flood_check` configured and enabled. The condition SHALL use `ALIGN_RATE` on the user-defined log metric and fire when the rate exceeds `threshold_entries_per_minute`. The policy's `alert_strategy` MUST NOT set `notification_rate_limit` (the Cloud Monitoring API rejects it on metric-threshold policies) and SHALL keep `auto_close`. The `flood_check` object schema MUST NOT accept a `notification_rate_limit` attribute; a configuration that sets it SHALL fail at plan time with a type error.

#### Scenario: Flood alert fires above threshold

- **WHEN** the log entry rate from the Typesense container exceeds `threshold_entries_per_minute` for the configured `duration`
- **THEN** the alert policy fires and an incident is opened

#### Scenario: Flood alert applies successfully

- **WHEN** a Typesense app has `flood_check` configured with defaults
- **THEN** `terraform apply` creates the policy without error and its `alert_strategy` contains `auto_close` and no `notification_rate_limit`

#### Scenario: Removed field set explicitly

- **WHEN** a consumer sets `flood_check.notification_rate_limit = "600s"`
- **THEN** `terraform plan` fails with a type error naming the unexpected `notification_rate_limit` attribute
