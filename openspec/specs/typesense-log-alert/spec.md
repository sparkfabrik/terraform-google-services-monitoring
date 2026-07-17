## Purpose

Log-based monitoring for Typesense GKE containers. Provides two capabilities: (1) a log severity alert (`log_check`) that fires on ERROR or higher log entries, and (2) a log flood alert (`flood_check`) that fires when log entry rate exceeds a configured threshold, catching Raft consensus storms and similar failure modes before they impact billing.

## Requirements

### Requirement: Log-based alert per Typesense app

The module SHALL create a `google_monitoring_alert_policy` with a `condition_matched_log` condition for each Typesense app that has `log_check` configured and enabled. The namespace in the log filter SHALL come from the app-level `namespace`.

#### Scenario: log_check enabled with defaults

- **WHEN** a Typesense app has `namespace = "typesense-prod"` and `log_check = {}` configured
- **THEN** the module creates an alert policy with a log filter matching `resource.type="k8s_container"`, `cluster_name`, `namespace_name="typesense-prod"`, `container_name="typesense"`, and `severity>=ERROR`

#### Scenario: log_check disabled

- **WHEN** a Typesense app has `log_check = { enabled = false }` configured
- **THEN** no alert policy is created for that app's log_check

#### Scenario: log_check not configured

- **WHEN** a Typesense app does not include `log_check` (null)
- **THEN** no alert policy is created for that app's log_check

### Requirement: Configurable minimum severity

The `log_check` object SHALL accept a `min_severity` field (default: `"ERROR"`) that controls the severity threshold in the log filter.

#### Scenario: Custom severity threshold

- **WHEN** an app has `namespace = "ts-ns"` and `log_check = { min_severity = "WARNING" }` configured
- **THEN** the log filter uses `severity>=WARNING` instead of the default `severity>=ERROR`

#### Scenario: Default severity

- **WHEN** `min_severity` is not specified
- **THEN** the log filter uses `severity>=ERROR`

### Requirement: Notification rate limiting

The alert policy SHALL include a `notification_rate_limit` in its `alert_strategy`, controlled by the `logmatch_notification_rate_limit_seconds` field (number of seconds, default: `300`).

#### Scenario: Default rate limit

- **WHEN** `logmatch_notification_rate_limit_seconds` is not specified
- **THEN** the alert strategy uses `notification_rate_limit.period = "300s"`

#### Scenario: Custom rate limit

- **WHEN** `logmatch_notification_rate_limit_seconds = 600` is specified
- **THEN** the alert strategy uses `notification_rate_limit.period = "600s"`

### Requirement: Auto-close configuration

The alert policy SHALL include an `auto_close` duration in its `alert_strategy`, controlled by `auto_close_seconds` (default: `3600`).

#### Scenario: Default auto-close

- **WHEN** `auto_close_seconds` is not specified
- **THEN** the alert strategy uses `auto_close = "3600s"`

### Requirement: Notification channel cascade

The alert policy SHALL use the same notification channel cascade as other Typesense alerts: per-service `notification_channels` if non-empty, otherwise root `notification_channels`, unless `notification_enabled = false`.

#### Scenario: Notification channels inherited from root

- **WHEN** `typesense.notification_channels` is empty and root `notification_channels` is set
- **THEN** the alert uses root `notification_channels`

#### Scenario: Notifications disabled

- **WHEN** `typesense.notification_enabled = false`
- **THEN** the alert uses an empty notification channel list

### Requirement: cluster_name validation includes log_check

The `typesense` variable validation SHALL require a resolvable GKE cluster name for every app that has `log_check` configured (in addition to the existing `container_check` requirement): the app-level `cluster_name` when set, otherwise the service-level `typesense.cluster_name`. Log-based filters SHALL use the resolved per-app value.

#### Scenario: log_check without any cluster_name

- **WHEN** an app has `log_check` configured, no app-level `cluster_name`, and `typesense.cluster_name` is not set
- **THEN** Terraform validation fails with an error message indicating that a cluster name must be provided

#### Scenario: log_check with app-level override

- **WHEN** an app has `log_check` configured and sets `cluster_name = "other-cluster"` while `typesense.cluster_name = "main-cluster"`
- **THEN** that app's log filter matches `resource.labels.cluster_name="other-cluster"` and other apps keep `"main-cluster"`

#### Scenario: log_check with service-level fallback

- **WHEN** an app has `log_check` configured without an app-level `cluster_name` and `typesense.cluster_name = "main-cluster"`
- **THEN** that app's log filter matches `resource.labels.cluster_name="main-cluster"`, identical to the previous release

### Requirement: Alert documentation on log-based policies

When `typesense.alert_documentation` is set, the log severity and log flood alert policies SHALL render it in their `documentation` block; when unset, no `documentation` block is rendered and existing consumers see no plan diff.

#### Scenario: Documentation set on log alerts

- **WHEN** `typesense.alert_documentation = "See runbook X"` and an app has `log_check` and `flood_check` enabled
- **THEN** both policies carry that text in their documentation content

#### Scenario: Documentation unset

- **WHEN** `typesense.alert_documentation` is null
- **THEN** the log severity and flood policies render no documentation block

### Requirement: Output for log alert policies

The module SHALL expose an output `typesense_logmatch_alert_policy_names` mapping app names to their alert policy resource names.

#### Scenario: Multiple apps with log_check

- **WHEN** two apps have `log_check` enabled
- **THEN** the output contains a map with two entries keyed by app name

### Requirement: Log-based metric per Typesense app with flood_check

The module SHALL create a `google_logging_metric` counter resource for each Typesense app that has `flood_check` configured and enabled. The metric SHALL count all log entries from all containers in the app-level `namespace` and the resolved cluster (not scoped to `container_name`).

#### Scenario: flood_check enabled

- **WHEN** a Typesense app has `namespace = "typesense-stage"` and `flood_check = { threshold_entries_per_minute = 3000 }` configured
- **THEN** the module creates a `google_logging_metric` with a filter scoped to `resource.type="k8s_container"`, `cluster_name`, and `namespace_name="typesense-stage"` (no `container_name` filter — counts all containers in the namespace)

#### Scenario: flood_check disabled

- **WHEN** a Typesense app has `flood_check = { enabled = false, threshold_entries_per_minute = 3000 }` configured
- **THEN** no logging metric or alert policy is created for that app's flood_check

#### Scenario: flood_check not configured

- **WHEN** a Typesense app does not include `flood_check` (null)
- **THEN** no logging metric or alert policy is created for that app's flood_check

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

### Requirement: threshold_entries_per_minute defaults to 1000

The `flood_check.threshold_entries_per_minute` field SHALL default to `1000` entries per minute. Operators SHOULD override with a value appropriate for their environment's baseline log volume.

#### Scenario: Default threshold

- **WHEN** `flood_check` is configured without specifying `threshold_entries_per_minute`
- **THEN** the threshold defaults to `1000` entries per minute

#### Scenario: Custom threshold

- **WHEN** an app has `namespace = "ts-ns"` and `flood_check = { threshold_entries_per_minute = 3000 }` configured
- **THEN** the alert fires when the log rate exceeds `3000` entries per minute

### Requirement: Configurable flood_check alignment and duration

The `flood_check` object SHALL accept `alignment_period_seconds` (default: `60`) and `duration_seconds` (default: `300`) to control how the rate is measured and how long it must be sustained before the alert fires.

#### Scenario: Default alignment and duration

- **WHEN** `alignment_period_seconds` and `duration_seconds` are not specified
- **THEN** the alert uses `alignment_period = "60s"` and `duration = "300s"`

### Requirement: Flood check auto-close

The flood alert policy SHALL include `auto_close` (default: `86400s`) in its `alert_strategy`. The longer default reflects that a log storm is a sustained operational event, not a transient spike.

#### Scenario: Default auto-close

- **WHEN** `auto_close_seconds` is not specified in `flood_check`
- **THEN** the alert strategy uses `auto_close = "86400s"`

### Requirement: Output for flood alert policies

The module SHALL expose an output `typesense_flood_alert_policy_names` mapping app names to their flood alert policy resource names.

#### Scenario: Multiple apps with flood_check

- **WHEN** two apps have `flood_check` enabled
- **THEN** the output contains a map with two entries keyed by app name
