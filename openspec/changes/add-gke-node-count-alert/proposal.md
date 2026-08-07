## Why

GKE clusters with autoscaling can grow their total node count unexpectedly, which drives up cost without any single node breaching a utilization threshold. There is no reusable alert in this module for "the cluster has too many nodes for too long", so projects (for example `zambon-ops`) have implemented the check locally and cannot share fixes or defaults. Porting it into the module gives every consumer a single, versioned, Renovate-propagated alert.

## What Changes

- Add a new `gke_node_count` alert to the module: a `google_monitoring_alert_policy` that fires when the total number of GKE nodes in a cluster stays above a configurable threshold for a sustained duration (default 24 hours).
- Add a `gke_node_count` input variable following the module's per-service object convention (`enabled` default `false`, `project_id`, `notification_enabled`, `notification_channels`, `user_labels`, plus alert-specific fields).
- Count total nodes across all node pools by counting the per-node series of `kubernetes.io/node/cpu/allocatable_cores` on the `k8s_node` resource (`REDUCE_COUNT`). Support an optional `node_pool_name` to narrow the count to a single pool; when unset, all pools are counted.
- Add a `gke_node_count_alert_policy_name` output.
- Update `examples/`, `README.md` (terraform-docs), and `CHANGELOG.md`; tag a new module release.
- Rewire `zambon-ops` to consume the new module alert: bump the module version, wire the `gke_node_count` variable in `terraform.tfvars`, and remove the local `google_monitoring_alert_policy.gke_node_count` from `infra/terraform/cost-monitoring.tf`.

## Capabilities

### New Capabilities

- `gke-node-count-alert`: A configurable Cloud Monitoring alert that notifies the configured channels when a GKE cluster's total node count (optionally scoped to one node pool) exceeds a threshold for a sustained duration.

### Modified Capabilities

<!-- None: no existing module capability changes its requirements. -->

## Impact

- **Module (`terraform-google-services-monitoring`)**: new `gke_node_count.tf`, new `gke_node_count` variable in `variables.tf`, new output in `outputs.tf`, new example, regenerated `README.md`, `CHANGELOG.md` entry, new release tag.
- **Consumer (`zambon-ops`)**: module version bump, new `gke_node_count` config in `terraform.tfvars`, removal of the local alert in `infra/terraform/cost-monitoring.tf`. The alert's identity changes (module-managed resource address), so the plan will show the old policy destroyed and the new one created.
- **Metric feasibility risk**: the optional `node_pool_name` filter depends on the `k8s_node` resource exposing the node pool via `metadata.system_labels."cloud.google.com/gke-nodepool"`. If unsupported in a metric-threshold filter, the total-cluster count (no pool filter) remains the guaranteed path. Resolved in design.
