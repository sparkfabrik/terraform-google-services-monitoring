## Purpose

Cross-cutting configuration contract of the `typesense` variable: app-level `namespace` placement and resolution for every Kubernetes-based check, and the uniform `_seconds` numeric convention for all duration-like fields.

## Requirements

### Requirement: App-level namespace

The `typesense` app object SHALL declare `namespace` once at the app level (`apps[*].namespace`, optional string, next to `cluster_name`). The check blocks (`container_check`, `log_check`, `flood_check`, `workload_check`) MUST NOT accept a `namespace` attribute; every Kubernetes-based filter of the app SHALL use the app-level value.

#### Scenario: Namespace declared once

- **WHEN** an app sets `namespace = "ts-ns"` and configures `container_check`, `log_check`, `flood_check` and `workload_check`
- **THEN** all four checks filter `namespace_name="ts-ns"` without repeating the value

#### Scenario: Legacy block-level namespace

- **WHEN** a configuration sets `namespace` inside any check block
- **THEN** Terraform's object conversion silently discards the attribute and the app-level `namespace` governs all filters; if the app has no app-level `namespace`, validation fails

### Requirement: Namespace required only for Kubernetes-based checks

Validation SHALL fail when an app configures any of `container_check`, `log_check`, `flood_check` or `workload_check` and has no app-level `namespace`. The error message is static (Terraform below 1.9 cannot reference the variable in `error_message`, and the module supports `>= 1.5`), so it does not name the offending app. An app with only `uptime_check` SHALL be valid without a namespace.

#### Scenario: Kubernetes check without namespace

- **WHEN** an app configures `workload_check` and no `namespace`
- **THEN** Terraform validation fails for the missing app-level `namespace`

#### Scenario: Uptime-only app

- **WHEN** an app configures only `uptime_check` and no `namespace`
- **THEN** validation passes and the uptime check is created

### Requirement: Uniform timing convention

Every duration-like field of the `typesense` variable SHALL be a number of seconds with a `_seconds` name suffix. This covers `container_check.pod_restart.alignment_period_seconds` and `duration_seconds`, the `alignment_period_seconds` and `duration_seconds` entries of the `workload_check` threshold lists, `log_check.logmatch_notification_rate_limit_seconds`, and all pre-existing `_seconds` fields. The schema SHALL NOT declare any Go-duration string or bare unsuffixed duration field; legacy attribute names are not part of the type and are silently discarded by Terraform's object conversion (a Terraform limitation: extra object attributes cannot be rejected), so the UPGRADING.md migration table is the contract for carrying values over.

#### Scenario: Workload threshold timing as numbers

- **WHEN** an app sets `workload_check.memory_utilization = [{ threshold = 0.85, alignment_period_seconds = 300, duration_seconds = 300 }]`
- **THEN** the created policy uses `alignment_period = "300s"` and `duration = "300s"`

#### Scenario: Legacy string value

- **WHEN** a configuration sets `alignment_period = "300s"` in a workload threshold entry
- **THEN** Terraform's object conversion silently discards the attribute and `alignment_period_seconds` takes its default (`300`); a string assigned to `alignment_period_seconds` itself fails with a number conversion error

#### Scenario: Rate limit as number

- **WHEN** `log_check = { logmatch_notification_rate_limit_seconds = 600 }` is configured on an app with a namespace
- **THEN** the log alert strategy uses `notification_rate_limit.period = "600s"`

### Requirement: Timing values validated as positive integers

Validation SHALL fail at plan time when any `_seconds` timing field is zero or negative.

#### Scenario: Negative duration

- **WHEN** an app sets `workload_check.replica_availability.duration_seconds = -60`
- **THEN** Terraform validation fails naming the field

### Requirement: Per-check notification resolution

Every Typesense check block (`uptime_check`, `container_check`, `log_check`, `flood_check`, `workload_check`) SHALL accept `notification_enabled = optional(bool, null)` and `notification_channels = optional(list(string), null)`. The effective routing for a check's policies SHALL be resolved as: effective enablement is the check-level `notification_enabled` when non-null, otherwise the service-level `typesense.notification_enabled`; when effectively disabled the channel list is empty; when effectively enabled the channel list is the check-level `notification_channels` when non-null, otherwise the service-level list when non-empty, otherwise the root `notification_channels`. The most specific non-null setting always wins.

#### Scenario: Defaults inherit current behavior

- **WHEN** a check sets neither `notification_enabled` nor `notification_channels`
- **THEN** its policies use the service-level resolution unchanged and an upgrading consumer sees no plan diff

#### Scenario: Silent check

- **WHEN** a check sets `notification_enabled = false` on a service with channels configured
- **THEN** that check's policies are created with an empty notification channel list while other checks keep the service routing

#### Scenario: Check-level channel override

- **WHEN** a check sets `notification_channels = ["projects/p/notificationChannels/123"]` and leaves `notification_enabled` null on a service with `notification_enabled = true`
- **THEN** that check's policies notify only the overridden channel

#### Scenario: Check re-enables over a disabled service

- **WHEN** `typesense.notification_enabled = false` and a check sets `notification_enabled = true` with `notification_channels = ["projects/p/notificationChannels/123"]`
- **THEN** that check's policies notify the overridden channel while all other checks stay silent

#### Scenario: Empty override list

- **WHEN** a check sets `notification_channels = []` and is effectively enabled
- **THEN** its policies are created with no notification channels and validation does not reject the empty list
