## Context

The module hosts one `google_monitoring_alert_policy` per concern, each driven by a per-service input object variable (`ssl_alert`, `cloud_sql`, `memorystore`, typesense alerts). The established pattern: a `locals` block resolves `project` and `notification_channels` with fallback to the module-level defaults, then a resource uses `for_each` guarded by `enabled` (`ssl_alert.tf` is the closest single-alert template).

The source implementation to port lives in `zambon-ops` at `infra/terraform/cost-monitoring.tf` (`google_monitoring_alert_policy.gke_node_count`). It filters `resource.type="k8s_node"` and `resource.labels.cluster_name` on metric `kubernetes.io/node/cpu/allocatable_cores`, aggregates with `alignment_period=3600s`, `per_series_aligner=ALIGN_MEAN`, `cross_series_reducer=REDUCE_COUNT`, `comparison=COMPARISON_GT`, `duration=86400s`. `REDUCE_COUNT` collapses the per-node series into a single count of nodes.

## Goals / Non-Goals

**Goals:**

- Reproduce the validated `zambon-ops` node-count alert as a configurable module feature.
- Single-threshold, single-duration config (one alert), matching the module's simplest per-service shape.
- Optional narrowing to one node pool; default counts all pools.
- Keep the consuming project's behavior identical after rewire.

**Non-Goals:**

- Multi-severity / multi-threshold ladders (deferred; can be added later as a list like `cloud_sql`).
- Monitoring per-pool counts simultaneously in one policy.
- Changing any other module alert.

## Decisions

**Counting method — `allocatable_cores` + `REDUCE_COUNT`.** Reuse the `zambon-ops` filter verbatim. Each node emits exactly one `k8s_node` series for `kubernetes.io/node/cpu/allocatable_cores`; `cross_series_reducer=REDUCE_COUNT` returns the node count. `per_series_aligner=ALIGN_MEAN` is irrelevant to the count value, but `alignment_period` is not: `REDUCE_COUNT` tallies every series with a point in the aligned window, so a terminated node stays counted for the length of that window. The ported `3600s` overcounts on churny pools (spot/preemptible), where terminated nodes linger up to an hour. Default lowered to `60s` (the metric sample interval) so the count reflects currently running nodes. The issue's `core_usage_time` PromQL is an equivalent count-of-series but rate-based and less directly a node count, so it is not used.

**Variable shape.** New `gke_node_count` object with module-standard fields plus: `cluster_name` (required when enabled), `node_pool_name` (default `null`), `threshold` (default `16`), `duration` (default `"86400s"`), `alignment_period` (default `"60s"`), `severity` (default `"WARNING"`), `auto_close` (optional). No `for_each` fan-out is needed for a single alert; use `count = var.gke_node_count.enabled ? 1 : 0` to match the `enabled`-guard pattern while keeping a single policy. A `locals` block resolves project and notification channels exactly as `ssl_alert.tf` does.

**Filter assembly.** Base filter:

```
resource.type = "k8s_node"
AND resource.labels.cluster_name = "<cluster_name>"
AND metric.type = "kubernetes.io/node/cpu/allocatable_cores"
```

When `node_pool_name != null`, append the node-pool selector. The `k8s_node` monitored resource does not carry the pool as a resource label, so pool scoping uses the system metadata label:

```
AND metadata.system_labels."cloud.google.com/gke-nodepool" = "<node_pool_name>"
```

Metadata-label filtering requires the project to have system metadata enabled (default on GKE). This is the documented mechanism for pool-level filtering on `k8s_node`.

**File layout.** New `gke_node_count.tf` (locals + resource), `gke_node_count` variable appended to `variables.tf`, `gke_node_count_alert_policy_name` output in `outputs.tf`, an `examples/gke-node-count/` (or an added block in the existing generic example), regenerated `README.md` via terraform-docs, `CHANGELOG.md` entry.

**Consumer rewire (`zambon-ops`).** Bump the module version to the new release, set `gke_node_count = { enabled = true, cluster_name = var.cluster_name, threshold = 16, notification_channels = <platform channels> }` in `terraform.tfvars`, delete `google_monitoring_alert_policy.gke_node_count` (and its `locals.cost_monitoring_gke_node_count_threshold`) from `cost-monitoring.tf`. Because the resource address moves from the root module to the child module, `terraform plan` shows destroy-then-create of the policy. Optionally a `moved {}` block cannot cross the root↔module boundary for a differently-named resource, so a clean recreate is expected and acceptable (the alert is stateless).

## Risks / Trade-offs

- **Node-pool metadata filter feasibility.** If `metadata.system_labels."cloud.google.com/gke-nodepool"` is not accepted in a metric-threshold filter for a given project, `node_pool_name` scoping fails while the default all-pools path (no pool filter, the primary requirement) still works. Validate with a real `terraform plan` / test-apply during implementation; if unsupported, document `node_pool_name` as best-effort or drop it.
- **Recreate on rewire.** The consumer's existing policy is destroyed and recreated. Harmless for a stateless alert, but note it in the `zambon-ops` MR so reviewers expect the diff.
- **Single-threshold limitation.** No CRITICAL/WARNING ladder yet. Acceptable per the issue's estimate; the variable can grow into a list later without breaking the simple case if introduced as an additional optional field.
- **Threshold defaults.** Default `16` and the "max 22 nodes" note are `zambon-ops`-specific; other consumers must set their own `threshold`. The default is a sane starting point, not a universal truth.
