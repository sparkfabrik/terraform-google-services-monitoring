## 1. Module: variable

- [x] 1.1 Add `gke_node_count` object variable to `variables.tf` with fields: `enabled` (bool, default `false`), `project_id` (string, default `null`), `notification_enabled` (bool, default `true`), `notification_channels` (list(string), default `[]`), `user_labels` (map(string), default `{}`), `cluster_name` (string, default `null`), `node_pool_name` (string, default `null`), `threshold` (number, default `16`), `duration` (string, default `"86400s"`), `alignment_period` (string, default `"3600s"`), `severity` (string, default `"WARNING"`), `auto_close` (string, default `null`).
- [x] 1.2 Add a validation that `cluster_name` is non-null when `enabled = true`.

## 2. Module: alert resource

- [x] 2.1 Create `gke_node_count.tf` with a `locals` block resolving `gke_node_count_project` (fallback to `var.project_id`) and `gke_node_count_notification_channels` (fallback to `var.notification_channels`, empty when `notification_enabled = false`), mirroring `ssl_alert.tf`.
- [x] 2.2 Build the condition `filter` from `resource.type="k8s_node"`, `resource.labels.cluster_name`, `metric.type="kubernetes.io/node/cpu/allocatable_cores"`, appending `metadata.system_labels."cloud.google.com/gke-nodepool"` only when `node_pool_name != null`.
- [x] 2.3 Add `google_monitoring_alert_policy.gke_node_count` guarded by `count = var.gke_node_count.enabled ? 1 : 0`, with `comparison="COMPARISON_GT"`, `threshold_value=threshold`, `duration`, aggregation `alignment_period` + `per_series_aligner="ALIGN_MEAN"` + `cross_series_reducer="REDUCE_COUNT"`, `severity`, `user_labels`, resolved `project` and `notification_channels`, and an `alert_strategy { auto_close }` only when `auto_close != null`.
- [x] 2.4 Add a `documentation` block explaining the alert (cluster name, threshold, 24h duration, cost context).

## 3. Module: output, example, docs

- [x] 3.1 Add output `gke_node_count_alert_policy_name` to `outputs.tf` returning the policy `name` (empty when disabled).
- [x] 3.2 Add an example under `examples/` showing `gke_node_count` enabled (all pools) and a commented `node_pool_name` variant.
- [x] 3.3 Regenerate `README.md` (`make docs` / terraform-docs) and add a `CHANGELOG.md` entry under `## [Unreleased]` (Added).

## 3b. Module: per-pool thresholds

- [x] 3b.1 Add `node_pool_thresholds` (map(number), default `{}`) to the `gke_node_count` variable, and a validation making it mutually exclusive with `node_pool_name`.
- [x] 3b.2 Refactor the resource to a `dynamic "conditions"` over a normalized `gke_node_count_conditions` map: per-pool mode (non-empty map) emits one condition per pool scoped by the nodepool label with its own threshold; otherwise a single total/`node_pool_name` condition with `threshold`.
- [x] 3b.3 Reflect the mode in the policy and condition display names and documentation.
- [x] 3b.4 Update the example (`node_pool_thresholds` variant), `CHANGELOG.md`, regenerate `README.md`.
- [x] 3b.5 Scope pools by a `node_name` regex (`monitoring.regex.full_match(".*-<pool>-.*")`) instead of the `cloud.google.com/gke-nodepool` metadata label, which is not attached to `k8s_node` metric series in practice.

## 4. Module: QA and release

- [x] 4.1 Run `terraform fmt`, `tflint`, `terraform validate` (module `make` QA targets).
- [ ] 4.2 Validate the alert filter against Cloud Monitoring: confirm `REDUCE_COUNT` yields node count and the `24h` (`86400s`) duration is accepted; confirm the `node_pool_name` metadata-label filter works or downgrade it per design. (Requires a live GCP project; defer to review/apply.)
- [ ] 4.3 Open the module PR, merge, and tag a new release (SemVer minor: new backward-compatible feature). (PR opened; merge + tag are human steps.)

## 5. Consumer rewire (`zambon-ops`)

- [ ] 5.1 Bump the `terraform-google-services-monitoring` module version to the new release.
- [ ] 5.2 Set `gke_node_count = { enabled = true, cluster_name = ..., threshold = 16, notification_channels = <platform channels> }` in `terraform.tfvars` (matching the current local alert's threshold and platform notification channels).
- [ ] 5.3 Remove `google_monitoring_alert_policy.gke_node_count` and `local.cost_monitoring_gke_node_count_threshold` from `infra/terraform/cost-monitoring.tf`.
- [ ] 5.4 Run `just qa` and `just run "terraform plan -lock=false"`; confirm the plan destroys the old root-module policy and creates the module-managed one, with no other unexpected diff. Note the recreate in the MR description.

## 6. Propagation

- [ ] 6.1 Propagate the module bump to other consuming projects via Renovate (or note them for follow-up), enabling `gke_node_count` per project only where a GKE cluster exists.

## 7. Archive

- [ ] 7.1 After both PRs merge, archive this OpenSpec change (`openspec archive add-gke-node-count-alert`).
