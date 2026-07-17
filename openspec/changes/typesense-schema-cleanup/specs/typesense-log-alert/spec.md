# typesense-log-alert (delta)

## MODIFIED Requirements

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

### Requirement: Notification rate limiting

The alert policy SHALL include a `notification_rate_limit` in its `alert_strategy`, controlled by the `logmatch_notification_rate_limit_seconds` field (number of seconds, default: `300`).

#### Scenario: Default rate limit

- **WHEN** `logmatch_notification_rate_limit_seconds` is not specified
- **THEN** the alert strategy uses `notification_rate_limit.period = "300s"`

#### Scenario: Custom rate limit

- **WHEN** `logmatch_notification_rate_limit_seconds = 600` is specified
- **THEN** the alert strategy uses `notification_rate_limit.period = "600s"`

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
