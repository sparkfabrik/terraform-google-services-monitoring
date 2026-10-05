## ADDED Requirements

### Requirement: Configurable Adaptive Protection alert

The module SHALL expose a `cloud_armor_adaptive_protection` input variable and, when enabled, create one log-based `google_monitoring_alert_policy` that fires on every Adaptive Protection alert written to the `networksecurity.googleapis.com/dos_attack` log for the listed security policies.

The variable SHALL follow the per-service convention: `enabled` (default `false`), `project_id` (default `null`, falling back to `var.project_id`), `notification_enabled` (default `true`), `notification_channels` (default `[]`, falling back to `var.notification_channels`) and `user_labels` (default `{}`). It SHALL also expose `security_policies` (list of policy names, required when enabled), `verify_adaptive_protection_enabled` (default `true`), `severity` (default `CRITICAL`), `auto_close_seconds` (default `1800`) and `notification_rate_limit_seconds` (default `300`).

#### Scenario: Alert disabled by default

- **WHEN** the consumer does not set `cloud_armor_adaptive_protection` or sets `enabled = false`
- **THEN** the module creates no alert policy and reads no security policy

#### Scenario: Enabled without policies

- **WHEN** the consumer sets `enabled = true` and leaves `security_policies` empty
- **THEN** variable validation fails at plan time

#### Scenario: Alert scoped to the listed policies

- **WHEN** the consumer lists one or more security policies
- **THEN** the alert filter matches the `dos_attack` log of the resolved project, resource type `network_security_policy`, and only those policy names

### Requirement: Adaptive Protection prerequisite check

When `verify_adaptive_protection_enabled` is true, the module SHALL read each listed policy at plan time and SHALL fail when layer 7 DDoS defense is not enabled on any of them, naming those policies in the error.

#### Scenario: Prerequisite met

- **WHEN** every listed policy has layer 7 DDoS defense enabled
- **THEN** the plan creates the alert policy

#### Scenario: Prerequisite missing

- **WHEN** a listed policy does not have layer 7 DDoS defense enabled
- **THEN** the plan fails with a precondition error that lists that policy

#### Scenario: Check skipped for a policy created in the same apply

- **WHEN** the consumer sets `verify_adaptive_protection_enabled = false`
- **THEN** the module reads no policy and creates the alert policy

### Requirement: Alert content and routing

The alert SHALL extract the security policy, the backend service, the confidence and the attack size from each log entry and show them in its documentation. It SHALL notify `notification_channels` when set, otherwise `var.notification_channels`, and no channel when `notification_enabled = false`, with the configured severity, auto close and notification rate limit.

#### Scenario: Notification content

- **WHEN** Adaptive Protection writes an alert for a listed policy
- **THEN** the notification names the backend service, the policy, the confidence and the attack size in requests per second
