# typesense-log-alert (delta)

## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Alert documentation on log-based policies

When `typesense.alert_documentation` is set, the log severity and log flood alert policies SHALL render it in their `documentation` block; when unset, no `documentation` block is rendered and existing consumers see no plan diff.

#### Scenario: Documentation set on log alerts

- **WHEN** `typesense.alert_documentation = "See runbook X"` and an app has `log_check` and `flood_check` enabled
- **THEN** both policies carry that text in their documentation content

#### Scenario: Documentation unset

- **WHEN** `typesense.alert_documentation` is null
- **THEN** the log severity and flood policies render no documentation block
