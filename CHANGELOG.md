# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.20.0] - 2026-07-23

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.19.1...0.20.0)

### Added

- `notification_prompts` (optional, `null` keeps the API default of notifying on incident open only) on the Typesense `log_check` and `flood_check` blocks, wired to `alert_strategy.notification_prompts` of the log-match and flood alert policies; set `["OPENED", "CLOSED"]` to also receive a notification when the incident auto-closes.

## [0.19.1] - 2026-07-17

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.19.0...0.19.1)

### Fixed

- Typesense flood alert policy creation rejected by the Cloud Monitoring API with `Error 400: The supplied filter does not specify a valid combination of metric and monitored resource descriptors`; the condition filter now targets `resource.type="k8s_container"` (the monitored resource of the backing log-based metric) instead of `global`.

## [0.19.0] - 2026-07-17

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.18.0...0.19.0)

### Added

- `UPGRADING.md` with migration notes for breaking changes.
- Per-check `notification_enabled` (tri-state, `null` inherits the service-level setting) on every Typesense check block (`uptime_check`, `container_check`, `log_check`, `flood_check`, `workload_check`); `false` creates the check's policies with no notification channels, `true` forces notifications on even when the service level disables them.
- Per-check `notification_channels` override (`null` inherits) on every Typesense check block; resolution order is check level, then service level, then root `notification_channels`, and an empty override list is legal.
- Per-app Typesense Cloud Monitoring dashboard via the optional `apps[*].dashboard` block (`enabled`, `display_name`); widgets are built from the checks the app configures (replica and uptime scorecards, per-pod memory/CPU/PVC utilization and restart charts, log-volume, error-log rate and uptime latency charts).
- Per-app log-based counter metric `typesense_error_logs_<app>` (`severity>=ERROR`), created only for apps with both `log_check` and the dashboard enabled, backing the dashboard's error-log rate chart.
- `typesense_dashboard_ids` output with the created dashboard ids keyed by app.
- `uptime_check_id` output on the `http_monitoring` submodule.
- `enabled = true` on the Typesense example so the example configuration actually plans Typesense resources.

### Changed

- **Breaking:** the Typesense `namespace` is declared once at the app level (`apps[*].namespace`, next to `cluster_name`) and is removed from `container_check`, `log_check`, `flood_check` and `workload_check`; migration in [UPGRADING.md](UPGRADING.md).
- **Breaking:** every Typesense duration-like field is a number of seconds with a `_seconds` name suffix (`pod_restart.alignment_period_seconds`/`duration_seconds`, workload threshold `alignment_period_seconds`/`duration_seconds`, `log_check.logmatch_notification_rate_limit_seconds`); field mapping and before/after example in [UPGRADING.md](UPGRADING.md).
- Every `_seconds` timing field of the Typesense variable is validated as a positive number at plan time.

### Removed

- `flood_check.notification_rate_limit` input on Typesense apps; the flood alert policy no longer sets a notification rate limit and configurations that set the field fail validation at plan time.

### Fixed

- Typesense flood alert policy creation rejected by the Cloud Monitoring API with `Error 400: only log-based alert policies may specify a notification rate limit`; the `notification_rate_limit` block is removed from the policy's `alert_strategy`.

## [0.18.0] - 2026-07-16

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.17.0...0.18.0)

### Added

- Typesense `workload_check` per-app block with alert policies on container memory limit utilization (WARNING 85% / CRITICAL 95%), container CPU limit utilization (WARNING 90%), PVC volume utilization (WARNING 75% / CRITICAL 85%), and replica availability via PromQL on `kubernetes_io:container_uptime` (CRITICAL below raft quorum `floor(n/2)+1`, WARNING below `expected_replicas`).
- Plan-time validation of `workload_check` threshold `severity` values (`WARNING`, `ERROR`, `CRITICAL`, any casing) with uppercase normalization in policy names, keys and severity attributes.
- `content_matchers` input on the `http_monitoring` submodule and `content_match` field on the Typesense `uptime_check` for response-content assertions.
- Per-app `cluster_name` override on Typesense apps, falling back to the service-level `typesense.cluster_name`, honored by workload, container, log and flood checks.
- `typesense.alert_documentation` rendered into the `documentation` block of every Typesense alert policy; `alert_documentation` input on the `http_monitoring` submodule.
- Outputs `typesense_workload_memory_alert_policy_names`, `typesense_workload_cpu_alert_policy_names`, `typesense_workload_volume_alert_policy_names` and `typesense_workload_replicas_alert_policy_names`.

## [0.17.0] - 2026-06-17

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.16.0...0.17.0)

### Added

- `AGENTS.md` with coding-agent instructions for this module.
- `CLAUDE.md` symlink to `AGENTS.md`.
- OpenSpec toolkit updates under `.github/prompts/`, `.github/skills/`, `.claude/`, and `.opencode/`.
- Kyverno health alert on the GKE system metric `kubernetes.io/container/restart_count`, scoped to the `kyverno-admission-controller` pods (`restart_check`).
- Kyverno tier-1 "service errors" alert: a `google_logging_metric` over `severity=ERROR` logs in the kyverno namespace, excluding the engine logger and a list of measured benign noise classes (matched on `jsonPayload.message` OR `jsonPayload.error`), with a low count threshold (`service_errors_check`).
- Kyverno tier-2 "volume catch-all" alert: a `google_logging_metric` over the same source with no exclusions (still excluding the engine logger), with a sustained-rate threshold so the exclusion list can never hide a flood (`volume_check`).
- Kyverno "broken policies" engine alert: a `google_logging_metric` over engine-logger ERROR logs, labeled by `policy` (extracted from `jsonPayload."policy.name"`), with the alert grouped by that label so each broken policy opens its own incident (`engine_check`).
- Kyverno policy review dashboard (`google_monitoring_dashboard`, the first in this module). Section A (violated policies) lists distinct violating resources per policy and per namespace, plus a namespace-to-policy map for triage, from `PolicyViolation` events (Log Analytics SQL widgets). Section B (broken policies) lists engine evaluation errors per policy and per namespace with the engine error message, and charts the per-policy engine-error rate (`dashboard`). Both sections are scoped to the current state over `dashboard.window_hours`; there is no long-range trend widget and no single-number scorecards, so each query stays cheap and every widget is actionable.

### Breaking change

- The `kyverno` variable is restructured. The log-match interface (`error_patterns_include`, `error_patterns_exclude`, `logmatch_notification_rate_limit`) is replaced by per-signal objects (`restart_check`, `service_errors_check`, `volume_check`, `engine_check`, `dashboard`). All Kyverno alerts inherit the module notification channels unless overridden.
- **Removed:** the legacy `kyverno_logmatch_alert` resource and its 16 message patterns. The metric-based alerts above replace it; clusters move atomically on module bump (rollback by pinning the previous version).

## [0.16.0] - 2026-05-26

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.15.0...0.16.0)

### Added

- Typesense `log_check` alert on Cloud Logging entries from the Typesense container at or above `min_severity` (default `ERROR`).
- Typesense `flood_check` alert that detects log-flooding failure modes (e.g. Raft consensus storms) via a `google_logging_metric` counting container log entries, with a threshold on entries-per-minute.
- Outputs `typesense_logmatch_alert_policy_names` and `typesense_flood_alert_policy_names`.
- OpenSpec change-management scaffolding under `openspec/`.

### Changed

- Typesense validation: when any app sets `container_check`, `log_check`, or `flood_check`, `cluster_name` is required and each check needs a non-empty `namespace`.

## [0.15.0] - 2026-02-09

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.14.0...0.15.0)

### Added

- refs platform/#3911: add CPU utilization and Memory usage monitoring alerts for Redis instances and clusters

## [0.14.0] - 2026-02-05

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.13.0...0.14.0)

### Breaking change

- **Kyverno log matching now uses `jsonPayload.message` instead of `jsonPayload.error`**. This provides more precise control over which log messages trigger alerts and enables proper exclusion of specific messages.
  - Error-detail patterns like `"is forbidden"`, `"context deadline exceeded"`, `"timeout"` have been removed as they appear in the `error` field, not the `message` field.
  - Patterns are now specific (e.g., `"failed to update lock"`) instead of generic (e.g., `"failed to update"`) to avoid overlap when excluding.
  - To migrate:
    - Review your `error_patterns_exclude` and `error_patterns_include` configurations and update pattern names/values if needed so that they correctly match `jsonPayload.message` instead of `jsonPayload.error`.
    - The variable names remain `error_patterns_exclude` and `error_patterns_include` for backwards compatibility, even though they now operate on the `message` field; no variable renaming is required.

### Changed

- Add `severity=ERROR` filter condition to ensure only error-level logs trigger alerts.
- Update Kyverno default patterns to message-based matching:
  - `"failed to list resources"`, `"failed to watch resource"`, `"failed to start watcher"`
  - `"failed to sync"`, `"failed to run warmup"`, `"failed to load certificate"`
  - `"failed to update lock"`, `"failed to process request"`
  - `"failed to check permissions"`, `"failed to scan resource"`, `"failed to fetch data"`
  - `"failed to substitute variables"`, `"failed calling webhook"`
  - `"leader election lost"`, `"dropping request"`, `"panic"`

## [0.13.0] - 2026-02-04

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.12.0...0.13.0)

### Changed

- Adjust Kyverno log filter to reduce false positives from normal transient errors such as `i/o timeout` and `failed to acquire lease`, including removal of the explicit `failed to acquire lease` condition.
- Rename error pattern `list resources failed` to `failed to list resources` for consistency with other error patterns.

### Added

- Add `error_patterns_exclude` to Kyverno configuration to allow excluding specific error patterns from the default set.
- Add `error_patterns_include` to Kyverno configuration to allow adding custom error patterns to the default set.
- Add validation for `error_patterns_exclude` to ensure only valid default patterns can be excluded.

### Breaking change

- The `filter_extra` variable has been removed and replaced with `error_patterns_include` and `error_patterns_exclude`. To migrate:
  - If you were using `filter_extra` to add custom error patterns for `jsonPayload.error` matching, use `error_patterns_include` instead.
  - If you need to exclude specific default error patterns, use `error_patterns_exclude`.
  - **Note:** The new options are specifically designed for error pattern matching against `jsonPayload.error`.
  - See [examples/main.tf](examples/main.tf) for usage examples.

## [0.12.0] - 2026-01-28

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.11.0...0.12.0)

### Changed

- refs platform/board#4071: remove dependencies from [`terraform-sparkfabrik-gcp-http-monitoring`](https://github.com/sparkfabrik/terraform-sparkfabrik-gcp-http-monitoring) terraform module.

## [0.11.0] - 2026-01-14

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.10.0...0.11.0)

### Changed

- Update Kyverno log alert filter to use explicit AND/OR grouping for controller selectors and to match error patterns via `jsonPayload.error`.
- Add konnectivity agent replica alert with a PromQL-based condition that counts pods via `kubernetes_io:container_uptime`.
- Standardize alert filter/query style for consistency across configuration.

## [0.10.0] - 2026-01-05

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.9.0...0.10.0)

### Changed

- Add `no agent available` to Kyverno log alert filter to capture control plane-to-node connectivity failures via Konnectivity (upstream Kubernetes); commonly seen on GKE (especially private nodes), but not GKE-specific.

## [0.9.0] - 2025-12-15

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.8.0...0.9.0)

### Added

- Add `notification_prompts` param for LiteLLM and Typesense

### Changed

- Modify the default values of the pod restart alerts `duration` and `alignment_period`

## [0.8.0] - 2025-12-12

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.7.0...0.8.0)

### Added

- refs platform/board#4051: add LiteLLM monitoring

## [0.7.0] - 2025-12-11

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.6.0...0.7.0)

### Added

- refs platform/board#4071: add SSL certificate expiration alert configuration

## [0.6.0] - 2025-12-11

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.5.0...0.6.0)

### Added

- refs platform/board#4052: add Typesense monitoring alerts and configuration for uptime checks and container checks

## [0.5.0] - 2025-12-01

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.4.0...0.5.0)

### Changed

- refs platform/board#3935: Kyverno log alert filter updated with explicit error patterns.

### Breaking change

- The previous `severity>=ERROR` filter for Kyverno log alerts has been removed and replaced with explicit text pattern matching. This significantly alters alert behavior, as alerts are now triggered based on specific error patterns rather than severity level. Please review and update your alert expectations accordingly.

## [0.4.0] - 2025-10-13

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.3.0...0.4.0)

### changed

- Rename tf file from `cloud-sql.tf` to `cloud_sql.tf`.
- Rename tf file from `kyverno_log_alert.tf` to `kyverno.tf`.
- Add cert-manager missing issuer alert log.

## [0.3.0] - 2025-10-07

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.2.0...0.3.0)

### Changed

- Add kyverno alert log.
- Update module documentation.

## [0.2.0] - 2024-10-17

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.1.1...0.2.0)

### Changed

- Increase default alert thresholds for Cloud SQL CPU, memory and disk utilization.

## [0.1.1] - 2024-06-25

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.1.0...0.1.1)

### Fixed

- Fixed Google provider minimum required version.

## [0.1.0] - 2024-06-19

### Added

- Add support for Cloud SQL monitoring:
  - CPU utilization
  - Memory utilization
  - Disk utilization
