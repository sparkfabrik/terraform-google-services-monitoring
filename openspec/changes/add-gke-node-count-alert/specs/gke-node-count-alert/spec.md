## Purpose

Provides a reusable Cloud Monitoring alert that warns when a GKE cluster runs more nodes than expected for a sustained period, catching runaway autoscaling and its cost impact before it goes unnoticed.

## ADDED Requirements

### Requirement: Configurable GKE node count alert

The module SHALL expose a `gke_node_count` input variable and, when enabled, create a `google_monitoring_alert_policy` that fires when a GKE cluster's total node count exceeds a configurable threshold for a configurable sustained duration.

The variable SHALL follow the module's per-service convention: `enabled` (bool, default `false`), `project_id` (string, default `null`, falling back to `var.project_id`), `notification_enabled` (bool, default `true`), `notification_channels` (list(string), default `[]`, falling back to `var.notification_channels`), and `user_labels` (map(string), default `{}`). It SHALL also expose alert-specific fields: `cluster_name` (string, required when enabled), `node_pool_name` (string, default `null`), `threshold` (number, default `16`), `duration` (string, default `"86400s"`), `alignment_period` (string, default `"3600s"`), `severity` (string, default `"WARNING"`), and `auto_close` (string, optional).

#### Scenario: Alert disabled by default

- **WHEN** the consumer does not set `gke_node_count` or sets `enabled = false`
- **THEN** the module creates no node-count alert policy

#### Scenario: Alert enabled with defaults

- **WHEN** the consumer sets `gke_node_count = { enabled = true, cluster_name = "my-cluster" }`
- **THEN** the module creates one alert policy that fires when the cluster's total node count exceeds 16 for 24 hours (`duration = "86400s"`)

### Requirement: Total node count across all pools

When `node_pool_name` is unset (`null`), the alert SHALL count the total number of nodes across all node pools of the named cluster, without restriction to any single pool.

The count SHALL be derived by counting the per-node time series of the `k8s_node` resource (one series per node), so that the alerted value equals the number of nodes rather than an aggregate of a per-node metric value.

#### Scenario: Counts every pool

- **WHEN** the cluster has nodes spread across multiple node pools and `node_pool_name` is `null`
- **THEN** the alert condition evaluates the sum of nodes across all pools of that cluster

#### Scenario: Value equals node count

- **WHEN** the cluster runs N nodes
- **THEN** the alert condition's evaluated value equals N (not the sum of a per-node metric such as allocatable cores)

### Requirement: Optional single node pool scope

When `node_pool_name` is set, the alert SHALL restrict the node count to that single node pool of the named cluster.

#### Scenario: Scoped to one pool

- **WHEN** the consumer sets `node_pool_name = "default-pool"`
- **THEN** the alert counts only nodes belonging to `default-pool` in the named cluster and ignores nodes in other pools

### Requirement: Cluster scoping

The alert SHALL filter by the required `cluster_name` so that only nodes belonging to the named cluster are counted, even when the monitored project contains multiple clusters.

#### Scenario: Ignores other clusters

- **WHEN** the project contains two clusters and `cluster_name` names one of them
- **THEN** nodes of the other cluster do not contribute to the count

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
