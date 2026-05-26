## Why

Typesense clusters running in GKE can enter degraded states that are not visible through uptime checks or pod restart counters — the application continues to run and respond to requests while emitting ERROR-level logs. There is currently no alert coverage for this signal. The need was surfaced by a billing incident (#4258) in which a Typesense Raft consensus storm flooded Cloud Logging, and confirmed by issue #4261 which calls for log-based monitoring to be added to the generic GCP monitoring module.

## What Changes

- Add an optional `log_check` configuration object to each Typesense app in the `typesense` variable, enabling a `condition_matched_log` alert policy per app.
- The alert fires when GKE container logs from the `typesense` container match `severity >= <min_severity>` (default: `ERROR`) in the configured namespace.
- Notification flooding is controlled via a configurable `logmatch_notification_rate_limit` (default: `300s`), consistent with the Kyverno and cert-manager patterns already in this module.
- Add an optional `flood_check` configuration object to each Typesense app, enabling a log volume alert via a user-defined `google_logging_metric` (counting log entries per minute from the Typesense container) paired with a `condition_threshold` alert policy.
- The flood alert fires when the log entry rate exceeds a configurable `threshold_entries_per_minute` (required, no default) sustained over a configurable duration.
- New outputs expose created alert policy names for both `log_check` and `flood_check`.
- The `examples/` directory is updated to demonstrate both `log_check` and `flood_check` usage.

## Capabilities

### New Capabilities

- `typesense-log-alert`: Per-app log-based error alert for Typesense GKE containers, triggered on configurable minimum severity (default `ERROR`), with rate-limited notifications and configurable auto-close.
- `typesense-flood-alert`: Per-app log volume alert for Typesense GKE containers, triggered when the log entry rate exceeds a required entries-per-minute threshold over a sustained window, using a user-defined log-based metric.

### Modified Capabilities

## Impact

- **`variables.tf`**: `typesense` variable extended with `log_check` and `flood_check` per app; `cluster_name` validation updated to require it when either is configured.
- **`typesense.tf`**: New locals and resources for both `log_check` (`typesense_logmatch_alert`) and `flood_check` (`google_logging_metric.typesense_log_flood` + `google_monitoring_alert_policy.typesense_flood_alert`).
- **`outputs.tf`**: New outputs `typesense_logmatch_alert_policy_names` and `typesense_flood_alert_policy_names`.
- **`examples/main.tf`**: Updated to show `log_check` and `flood_check` usage.
- No provider version changes required. No breaking changes to existing configurations.
