## Purpose

Per-app workload saturation and availability alerting for self-hosted Typesense clusters in GKE, driven by the `workload_check` block. Covers the vitals that kill a Typesense cluster: container memory limit utilization (in-memory store, OOMKill removes a raft member), container CPU limit utilization, PVC volume utilization (raft log growth fills the disk and rejects writes), and replica availability against the expected count and the raft quorum. Built entirely on free GKE system metrics (`kubernetes.io/*`, `kubernetes_io:container_uptime`). Requires containers to declare resource limits (`limit_utilization` has no series otherwise).

## Requirements

### Requirement: Workload check gating

The module SHALL create workload vitals resources for a Typesense app only when `typesense.enabled` is `true`, the app's `workload_check` is non-null, and `workload_check.enabled` is `true`.

#### Scenario: workload_check not configured

- **WHEN** a Typesense app has no `workload_check` attribute
- **THEN** no workload vitals alert policy is created for that app and the plan is identical to the previous release

#### Scenario: workload_check disabled

- **WHEN** a Typesense app has `workload_check = { enabled = false, namespace = "ns", expected_replicas = 3 }`
- **THEN** no workload vitals alert policy is created for that app

#### Scenario: service disabled

- **WHEN** `typesense.enabled` is `false` and an app has a fully configured `workload_check`
- **THEN** no workload vitals alert policy is created

### Requirement: Memory utilization alert

The module SHALL create one `google_monitoring_alert_policy` per entry in `workload_check.memory_utilization`, thresholding `kubernetes.io/container/memory/limit_utilization` with `metric.labels.memory_type = "non-evictable"`, filtered by project, cluster, namespace and container name.

#### Scenario: Default thresholds

- **WHEN** an app has `workload_check = { namespace = "ns", expected_replicas = 3 }`
- **THEN** two memory alert policies are created: WARNING at threshold 0.85 and CRITICAL at threshold 0.95

#### Scenario: Family disabled by empty list

- **WHEN** an app sets `memory_utilization = []`
- **THEN** no memory alert policy is created for that app

### Requirement: CPU utilization alert

The module SHALL create one `google_monitoring_alert_policy` per entry in `workload_check.cpu_utilization`, thresholding `kubernetes.io/container/cpu/limit_utilization`, filtered by project, cluster, namespace and container name.

#### Scenario: Default threshold

- **WHEN** an app has `workload_check = { namespace = "ns", expected_replicas = 3 }`
- **THEN** one CPU alert policy is created: WARNING at threshold 0.90

### Requirement: Volume utilization alert

The module SHALL create one `google_monitoring_alert_policy` per entry in `workload_check.volume_utilization`, thresholding `kubernetes.io/pod/volume/utilization`, filtered by project, cluster, namespace and `metric.labels.volume_name`.

#### Scenario: Default thresholds and volume name

- **WHEN** an app has `workload_check = { namespace = "ns", expected_replicas = 3 }`
- **THEN** two volume alert policies are created (WARNING 0.75, CRITICAL 0.85) filtering `volume_name = "data"`

#### Scenario: Custom volume name

- **WHEN** an app sets `workload_check.volume_name = "storage"`
- **THEN** the volume alert policies filter `metric.labels.volume_name = "storage"`

### Requirement: Replica availability alert

The module SHALL create PromQL-based alert policies (`condition_prometheus_query_language`) counting running Typesense pods via `kubernetes_io:container_uptime`, scoped by project, cluster, namespace and container name: a CRITICAL policy firing when the count drops below raft quorum `floor(expected_replicas / 2) + 1`, and a WARNING policy firing when the count drops below `expected_replicas`, created only when `expected_replicas` is greater than the quorum.

#### Scenario: Three replicas

- **WHEN** an app has `workload_check = { namespace = "ns", expected_replicas = 3 }`
- **THEN** a CRITICAL policy fires below 2 running pods and a WARNING policy fires below 3 running pods

#### Scenario: Single replica deduplication

- **WHEN** an app has `expected_replicas = 1`
- **THEN** only the CRITICAL policy is created (fires below 1 running pod) and no WARNING policy exists

#### Scenario: Replica alert disabled

- **WHEN** an app sets `workload_check.replica_availability = { enabled = false }`
- **THEN** no replica availability policy is created while threshold-based families remain unaffected

### Requirement: Workload selection

Workload vitals filters SHALL select pods by namespace and `container_name` (default `"typesense"`). When `workload_check.controller_name` is set, filters SHALL additionally constrain the top-level controller (`metadata.system_labels.top_level_controller_name` in threshold filters, `metadata_system_top_level_controller_name` in PromQL).

#### Scenario: Default selection

- **WHEN** `controller_name` is not set
- **THEN** all filters select only by namespace and container name

#### Scenario: Two Typesense clusters in one namespace

- **WHEN** two apps share a namespace and each sets its own `controller_name`
- **THEN** each app's policies select only pods belonging to its controller

### Requirement: Per-app GKE cluster resolution

Workload vitals SHALL target the GKE cluster resolved as the app-level `cluster_name` when set, otherwise the service-level `typesense.cluster_name`. Validation SHALL fail when an app has `workload_check` configured and neither value is set.

#### Scenario: Service-level fallback

- **WHEN** an app has no `cluster_name` and `typesense.cluster_name = "main-cluster"`
- **THEN** its workload policies filter `resource.labels.cluster_name = "main-cluster"`

#### Scenario: Per-app override

- **WHEN** an app sets `cluster_name = "other-cluster"` in a module instance where `typesense.cluster_name = "main-cluster"`
- **THEN** its workload policies filter `resource.labels.cluster_name = "other-cluster"` while other apps keep the service-level value

#### Scenario: No cluster resolvable

- **WHEN** an app has `workload_check` configured, no app-level `cluster_name`, and no service-level `cluster_name`
- **THEN** Terraform validation fails naming the missing input

### Requirement: Threshold severity validation

The `typesense` variable validation SHALL reject any `workload_check` threshold entry (in `memory_utilization`, `cpu_utilization` or `volume_utilization`) whose `severity` is not one of `WARNING`, `ERROR`, `CRITICAL` (the values accepted by `google_monitoring_alert_policy.severity`), so misconfiguration fails at plan time instead of apply time.

#### Scenario: Invalid severity

- **WHEN** an app sets `workload_check.memory_utilization = [{ severity = "critical", threshold = 0.95 }]`
- **THEN** Terraform validation fails naming the accepted severity values

#### Scenario: Valid severities

- **WHEN** threshold entries use any of `WARNING`, `ERROR`, `CRITICAL`
- **THEN** validation passes and one policy is created per entry with that severity

### Requirement: Notification channel cascade and alert strategy

Workload vitals policies SHALL reuse the existing Typesense notification cascade (app check disabled → none; override list → service list → root list) and SHALL apply `workload_check.auto_close_seconds` (default 3600) and optional `workload_check.notification_prompts` to every policy of the block.

#### Scenario: Notifications inherited

- **WHEN** `typesense.notification_enabled = true` and no override list is set
- **THEN** workload policies use the root `notification_channels`

### Requirement: Alert documentation on Typesense policies

When `typesense.alert_documentation` is set, every Typesense alert policy (workload, container, log, flood, uptime failure) SHALL render it in its `documentation` block; when unset, no `documentation` block is rendered.

#### Scenario: Documentation unset

- **WHEN** `typesense.alert_documentation` is null
- **THEN** existing consumers see no plan diff on their Typesense policies

#### Scenario: Documentation set

- **WHEN** `typesense.alert_documentation = "See runbook X"`
- **THEN** each Typesense alert policy carries that text in its documentation content

### Requirement: Outputs for workload policies

The module SHALL export the names of created workload vitals alert policies keyed by app and alert family.

#### Scenario: Two apps with workload_check

- **WHEN** two apps configure `workload_check`
- **THEN** the workload policy output map contains entries for both apps' memory, CPU, volume and replica policies
