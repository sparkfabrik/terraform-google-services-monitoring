## Purpose

Provides a reusable Cloud Monitoring alert that warns when a GKE cluster runs more nodes than expected for a sustained period, catching runaway autoscaling and its cost impact before it goes unnoticed.

## ADDED Requirements

### Requirement: Configurable GKE node count alert

The module SHALL expose a `gke_node_count` input variable and, when enabled, create a `google_monitoring_alert_policy` that fires when a GKE cluster's total node count exceeds a configurable threshold for a configurable sustained duration.

The variable SHALL follow the module's per-service convention: `enabled` (bool, default `false`), `project_id` (string, default `null`, falling back to `var.project_id`), `notification_enabled` (bool, default `true`), `notification_channels` (list(string), default `[]`, falling back to `var.notification_channels`), and `user_labels` (map(string), default `{}`). It SHALL also expose alert-specific fields: `cluster_name` (string, required when enabled), `threshold` (number, default `16`), `duration` (string, default `"86400s"`), `alignment_period` (string, default `"60s"`), `severity` (string, default `"WARNING"`), and `auto_close` (string, optional). The alert is total-count only: it does not offer per-pool scoping, because the node pool is not a queryable label on `k8s_node` metric series without kube-state-metrics.

#### Scenario: Alert disabled by default

- **WHEN** the consumer does not set `gke_node_count` or sets `enabled = false`
- **THEN** the module creates no node-count alert policy

#### Scenario: Alert enabled with defaults

- **WHEN** the consumer sets `gke_node_count = { enabled = true, cluster_name = "my-cluster" }`
- **THEN** the module creates one alert policy that fires when the cluster's total node count exceeds 16 for 24 hours (`duration = "86400s"`)

### Requirement: Total node count across all pools

The alert SHALL count the total number of nodes across all node pools of the named cluster, without restriction to any single pool.

The count SHALL be derived by counting the per-node time series of the `k8s_node` resource (one series per node), so that the alerted value equals the number of nodes rather than an aggregate of a per-node metric value.

#### Scenario: Counts every pool

- **WHEN** the cluster has nodes spread across multiple node pools
- **THEN** the alert condition evaluates the sum of nodes across all pools of that cluster

#### Scenario: Value equals node count

- **WHEN** the cluster runs N nodes
- **THEN** the alert condition's evaluated value equals N (not the sum of a per-node metric such as allocatable cores)

#### Scenario: Count reflects currently running nodes

- **WHEN** a pool churns nodes (for example spot or preemptible) so that terminated node series still hold recent points
- **THEN** the aggregation SHALL use an alignment period close to the metric sample interval (default 60s) so `REDUCE_COUNT` counts currently running nodes rather than every node seen within a long window

### Requirement: Project and cluster scoping

The alert filter SHALL scope by both the resolved project (`project_id`, falling back to `var.project_id`) and the required `cluster_name`, so that only nodes belonging to the named cluster in that project are counted, even when metrics from other clusters or projects are visible.

#### Scenario: Ignores other clusters

- **WHEN** the project contains two clusters and `cluster_name` names one of them
- **THEN** nodes of the other cluster do not contribute to the count

#### Scenario: Filter includes project id

- **WHEN** the alert is enabled
- **THEN** the condition filter contains `resource.labels.project_id` set to the resolved project alongside `resource.labels.cluster_name`

### Requirement: Notification routing and metadata

The alert SHALL send notifications to `notification_channels` when set, otherwise to the module-level `var.notification_channels`, and SHALL send no notification when `notification_enabled = false`. The policy SHALL apply `user_labels` and SHALL be created in `project_id` when set, otherwise in `var.project_id`. The policy SHALL carry the configured `severity` and, when `auto_close` is set, an `alert_strategy` with that `auto_close`.

#### Scenario: Falls back to module notification channels

- **WHEN** `gke_node_count.notification_channels` is empty and `notification_enabled = true`
- **THEN** the alert uses `var.notification_channels`

#### Scenario: Notifications suppressed

- **WHEN** `notification_enabled = false`
- **THEN** the alert policy is created with no notification channels

### Requirement: Exposed output

The module SHALL expose an output `gke_node_count_alert_policy_name` giving the created policy's `name`, empty when the alert is disabled.

#### Scenario: Output present when enabled

- **WHEN** the alert is enabled
- **THEN** `gke_node_count_alert_policy_name` returns the created policy's resource name
