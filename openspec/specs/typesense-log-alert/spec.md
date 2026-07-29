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

The alert policy SHALL resolve notification routing per check as defined by the Typesense per-check notification resolution: check-level `notification_enabled`/`notification_channels` when non-null, otherwise per-service `notification_channels` if non-empty, otherwise root `notification_channels`, with an empty list when the effective `notification_enabled` is false. `log_check` and `flood_check` resolve independently of each other.

#### Scenario: Notification channels inherited from root

- **WHEN** `typesense.notification_channels` is empty, root `notification_channels` is set, and the check sets no notification fields
- **THEN** the alert uses root `notification_channels`

#### Scenario: Notifications disabled

- **WHEN** `typesense.notification_enabled = false` and the check sets no notification fields
- **THEN** the alert uses an empty notification channel list

#### Scenario: Silent flood check with notifying log check

- **WHEN** an app sets `flood_check.notification_enabled = false` and leaves `log_check` notification fields null on a service with channels configured
- **THEN** the flood policy has no notification channels while the log severity policy keeps the service routing

#### Scenario: Log check channel override

- **WHEN** an app sets `log_check.notification_channels = ["projects/p/notificationChannels/123"]`
- **THEN** the log severity policy notifies only that channel

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

### Requirement: Log alert exclusion patterns

The `log_check` object SHALL accept an `exclude_patterns` field (list of strings, default: `[]`). The effective exclusion list SHALL be `exclude_patterns` optionally extended by the transient-errors preset (see "Transient error exclusion preset"). When the effective list is non-empty, the log-match alert filter SHALL exclude entries whose message contains any of the patterns, by appending a single clause of the form `AND NOT (jsonPayload.message:"<p1>" OR textPayload:"<p1>" OR jsonPayload.message:"<p2>" OR textPayload:"<p2>" ...)`. Matching SHALL use the Cloud Logging substring operator (`:`), which is case-insensitive. When the effective list is empty, the rendered filter SHALL be identical to the filter produced without the field.

#### Scenario: Exclusion patterns configured

- **WHEN** an app has `namespace = "ts-ns"` and `log_check = { exclude_patterns = ["Peer refresh failed", "> healthy write lag of"] }` configured
- **THEN** the log filter contains `AND NOT (jsonPayload.message:"Peer refresh failed" OR textPayload:"Peer refresh failed" OR jsonPayload.message:"> healthy write lag of" OR textPayload:"> healthy write lag of")`

#### Scenario: Default empty list preserves filter

- **WHEN** `exclude_patterns` is not specified or is `[]` and `exclude_transient_errors` is not `true`
- **THEN** the rendered log filter contains no `NOT` clause and is byte-identical to the filter produced before this field existed

#### Scenario: Exclusions do not affect other log-based resources

- **WHEN** an app has `exclude_patterns` configured together with `flood_check` and the dashboard error-log counter metric
- **THEN** the flood check filter and the `google_logging_metric` filter remain unfiltered by the patterns

### Requirement: Transient error exclusion preset

The `log_check` object SHALL accept an `exclude_transient_errors` field (bool, default: `false`). When `true`, the module SHALL append a module-maintained preset of exclusion patterns to the user-provided `exclude_patterns` when building the effective exclusion list for the log-match alert filter. The preset SHALL be exactly, in order: `Peer refresh failed`, `> healthy write lag of`, `> healthy read lag of`. The preset SHALL be defined as a module constant, not configurable by consumers, and the module SHALL assert at plan time, for any configuration that renders the log-match alert, that every preset entry satisfies the exclusion pattern validation invariant (non-empty after trimming; no double quote, backslash, or control character). The effective list SHALL be the user patterns followed by the preset patterns, deduplicated byte-exact preserving first occurrence. When `false`, the effective list SHALL be the user patterns exactly as provided (no deduplication) and the rendered filter SHALL be identical to the filter produced before this field existed.

#### Scenario: Toggle enabled with no user patterns

- **WHEN** an app has `log_check = { exclude_transient_errors = true }` and no `exclude_patterns`
- **THEN** the log filter contains `AND NOT (jsonPayload.message:"Peer refresh failed" OR textPayload:"Peer refresh failed" OR jsonPayload.message:"> healthy write lag of" OR textPayload:"> healthy write lag of" OR jsonPayload.message:"> healthy read lag of" OR textPayload:"> healthy read lag of")`

#### Scenario: Toggle enabled with user patterns

- **WHEN** an app has `log_check = { exclude_patterns = ["custom noise"], exclude_transient_errors = true }`
- **THEN** the effective exclusion list is `["custom noise", "Peer refresh failed", "> healthy write lag of", "> healthy read lag of"]` and the filter clause renders the user pattern first

#### Scenario: Overlap deduplicated

- **WHEN** an app has `log_check = { exclude_patterns = ["Peer refresh failed"], exclude_transient_errors = true }`
- **THEN** the effective exclusion list contains `Peer refresh failed` exactly once, followed by the two remaining preset patterns

#### Scenario: Toggle disabled preserves current behavior

- **WHEN** `exclude_transient_errors` is not specified or is `false`
- **THEN** the rendered filter is byte-identical to the filter produced without the field, for any value of `exclude_patterns`

#### Scenario: Toggle disabled keeps duplicate user patterns

- **WHEN** an app has `log_check = { exclude_patterns = ["x", "x"] }` and `exclude_transient_errors` unset or `false`
- **THEN** the rendered clause repeats the pattern verbatim, byte-identical to the pre-change rendering

#### Scenario: Preset entry violating the pattern invariant

- **WHEN** the module-maintained preset contains an entry that is empty after trimming or contains `"`, `\`, or a control character, and at least one app has an enabled `log_check`
- **THEN** `terraform plan` fails with a message stating the preset invariant and identifying it as a module defect

#### Scenario: Preset does not affect other log-based resources

- **WHEN** an app has `exclude_transient_errors = true` together with `flood_check` and the dashboard error-log counter metric
- **THEN** the flood check filter and the `google_logging_metric` filters remain unfiltered by the preset

### Requirement: Exclusion pattern validation

The `typesense` variable validation SHALL reject, at plan time, any `log_check.exclude_patterns` entry that is `null`, empty after trimming whitespace, or contains a double-quote character (`"`), a backslash (`\`), or any control character (newline, carriage return, tab, NUL, and the rest of the C0/C1 classes), with an error message stating the constraint and pointing at `log_check.exclude_patterns`. A `null` entry SHALL surface the validation error message, not an internal function error. The message is a constant string (dynamic `error_message` expressions require Terraform >= 1.9 while the module supports >= 1.5), following the `notification_prompts` validation precedent.

#### Scenario: Pattern with embedded double quote

- **WHEN** an app configures `log_check = { exclude_patterns = ["bad\"pattern"] }`
- **THEN** `terraform plan` fails with a validation error stating the constraint

#### Scenario: Empty pattern

- **WHEN** an app configures `log_check = { exclude_patterns = [""] }`
- **THEN** `terraform plan` fails with a validation error stating the constraint

#### Scenario: Whitespace-only pattern

- **WHEN** an app configures `log_check = { exclude_patterns = ["  "] }`
- **THEN** `terraform plan` fails with a validation error stating the constraint

#### Scenario: Pattern with trailing backslash

- **WHEN** an app configures `log_check = { exclude_patterns = ["trailing\\"] }`
- **THEN** `terraform plan` fails with a validation error stating the constraint (a backslash escapes the closing quote in the Cloud Logging filter grammar)

#### Scenario: Pattern with control character

- **WHEN** an app configures `log_check = { exclude_patterns = ["a\rb"] }` (or any other raw control character such as NUL or form feed)
- **THEN** `terraform plan` fails with a validation error stating the constraint

#### Scenario: Null pattern entry

- **WHEN** an app configures `log_check = { exclude_patterns = ["a", null] }`
- **THEN** `terraform plan` fails with the validation error message, not an internal function error

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
