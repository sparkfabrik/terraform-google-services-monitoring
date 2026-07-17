# typesense-config-schema

## ADDED Requirements

### Requirement: App-level namespace

The `typesense` app object SHALL declare `namespace` once at the app level (`apps[*].namespace`, optional string, next to `cluster_name`). The check blocks (`container_check`, `log_check`, `flood_check`, `workload_check`) MUST NOT accept a `namespace` attribute; every Kubernetes-based filter of the app SHALL use the app-level value.

#### Scenario: Namespace declared once

- **WHEN** an app sets `namespace = "ts-ns"` and configures `container_check`, `log_check`, `flood_check` and `workload_check`
- **THEN** all four checks filter `namespace_name="ts-ns"` without repeating the value

#### Scenario: Legacy block-level namespace

- **WHEN** a configuration sets `namespace` inside any check block
- **THEN** `terraform plan` fails with a type error naming the unexpected `namespace` attribute

### Requirement: Namespace required only for Kubernetes-based checks

Validation SHALL fail, naming the app key, when an app configures any of `container_check`, `log_check`, `flood_check` or `workload_check` and has no app-level `namespace`. An app with only `uptime_check` SHALL be valid without a namespace.

#### Scenario: Kubernetes check without namespace

- **WHEN** an app configures `workload_check` and no `namespace`
- **THEN** Terraform validation fails naming the app and the missing `namespace`

#### Scenario: Uptime-only app

- **WHEN** an app configures only `uptime_check` and no `namespace`
- **THEN** validation passes and the uptime check is created

### Requirement: Uniform timing convention

Every duration-like field of the `typesense` variable SHALL be a number of seconds with a `_seconds` name suffix. This covers `container_check.pod_restart.alignment_period_seconds` and `duration_seconds`, the `alignment_period_seconds` and `duration_seconds` entries of the `workload_check` threshold lists, `log_check.logmatch_notification_rate_limit_seconds`, and all pre-existing `_seconds` fields. Go-duration strings and bare unsuffixed numbers MUST NOT be accepted anywhere in the schema.

#### Scenario: Workload threshold timing as numbers

- **WHEN** an app sets `workload_check.memory_utilization = [{ threshold = 0.85, alignment_period_seconds = 300, duration_seconds = 300 }]`
- **THEN** the created policy uses `alignment_period = "300s"` and `duration = "300s"`

#### Scenario: Legacy string value

- **WHEN** a configuration sets `alignment_period = "300s"` in a workload threshold entry
- **THEN** `terraform plan` fails with a type error naming the unexpected attribute

#### Scenario: Rate limit as number

- **WHEN** `log_check = { logmatch_notification_rate_limit_seconds = 600 }` is configured on an app with a namespace
- **THEN** the log alert strategy uses `notification_rate_limit.period = "600s"`

### Requirement: Timing values validated as positive integers

Validation SHALL fail at plan time when any `_seconds` timing field is zero or negative.

#### Scenario: Negative duration

- **WHEN** an app sets `workload_check.replica_availability.duration_seconds = -60`
- **THEN** Terraform validation fails naming the field
