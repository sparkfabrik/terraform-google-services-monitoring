# typesense-workload-vitals (delta)

## MODIFIED Requirements

### Requirement: Workload check gating

The module SHALL create workload vitals resources for a Typesense app only when `typesense.enabled` is `true`, the app's `workload_check` is non-null, and `workload_check.enabled` is `true`. The namespace used by all workload filters SHALL come from the app-level `namespace`.

#### Scenario: workload_check not configured

- **WHEN** a Typesense app has no `workload_check` attribute
- **THEN** no workload vitals alert policy is created for that app and the plan is identical to the previous release

#### Scenario: workload_check disabled

- **WHEN** a Typesense app has `namespace = "ns"` and `workload_check = { enabled = false, expected_replicas = 3 }`
- **THEN** no workload vitals alert policy is created for that app

#### Scenario: service disabled

- **WHEN** `typesense.enabled` is `false` and an app has a fully configured `workload_check`
- **THEN** no workload vitals alert policy is created

### Requirement: Memory utilization alert

The module SHALL create one `google_monitoring_alert_policy` per entry in `workload_check.memory_utilization`, thresholding `kubernetes.io/container/memory/limit_utilization` with `metric.labels.memory_type = "non-evictable"`, filtered by project, cluster, the app-level namespace and container name.

#### Scenario: Default thresholds

- **WHEN** an app has `namespace = "ns"` and `workload_check = { expected_replicas = 3 }`
- **THEN** two memory alert policies are created: WARNING at threshold 0.85 and CRITICAL at threshold 0.95

#### Scenario: Family disabled by empty list

- **WHEN** an app sets `memory_utilization = []`
- **THEN** no memory alert policy is created for that app

### Requirement: CPU utilization alert

The module SHALL create one `google_monitoring_alert_policy` per entry in `workload_check.cpu_utilization`, thresholding `kubernetes.io/container/cpu/limit_utilization`, filtered by project, cluster, the app-level namespace and container name.

#### Scenario: Default threshold

- **WHEN** an app has `namespace = "ns"` and `workload_check = { expected_replicas = 3 }`
- **THEN** one CPU alert policy is created: WARNING at threshold 0.90

### Requirement: Volume utilization alert

The module SHALL create one `google_monitoring_alert_policy` per entry in `workload_check.volume_utilization`, thresholding `kubernetes.io/pod/volume/utilization`, filtered by project, cluster, the app-level namespace and `metric.labels.volume_name`.

#### Scenario: Default thresholds and volume name

- **WHEN** an app has `namespace = "ns"` and `workload_check = { expected_replicas = 3 }`
- **THEN** two volume alert policies are created (WARNING 0.75, CRITICAL 0.85) filtering `volume_name = "data"`

#### Scenario: Custom volume name

- **WHEN** an app sets `workload_check.volume_name = "storage"`
- **THEN** the volume alert policies filter `metric.labels.volume_name = "storage"`

### Requirement: Replica availability alert

The module SHALL create PromQL-based alert policies (`condition_prometheus_query_language`) counting running Typesense pods via `kubernetes_io:container_uptime`, scoped by project, cluster, the app-level namespace and container name: a CRITICAL policy firing when the count drops below raft quorum `floor(expected_replicas / 2) + 1`, and a WARNING policy firing when the count drops below `expected_replicas`, created only when `expected_replicas` is greater than the quorum.

#### Scenario: Three replicas

- **WHEN** an app has `namespace = "ns"` and `workload_check = { expected_replicas = 3 }`
- **THEN** a CRITICAL policy fires below 2 running pods and a WARNING policy fires below 3 running pods

#### Scenario: Single replica deduplication

- **WHEN** an app has `expected_replicas = 1`
- **THEN** only the CRITICAL policy is created (fires below 1 running pod) and no WARNING policy exists

#### Scenario: Replica alert disabled

- **WHEN** an app sets `workload_check.replica_availability = { enabled = false }`
- **THEN** no replica availability policy is created while threshold-based families remain unaffected
