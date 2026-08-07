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

**Variable shape.** New `gke_node_count` object with module-standard fields plus: `cluster_name` (required when enabled), `threshold` (default `16`), `duration` (default `"86400s"`), `alignment_period` (default `"60s"`), `severity` (default `"WARNING"`), `auto_close` (optional). No `for_each` fan-out is needed for a single alert; use `count = var.gke_node_count.enabled ? 1 : 0` to match the `enabled`-guard pattern while keeping a single policy. A `locals` block resolves project and notification channels exactly as `ssl_alert.tf` does.

**Filter assembly.** Single total-count filter, scoped by project and cluster:

```
resource.type = "k8s_node"
AND resource.labels.project_id = "<project>"
AND resource.labels.cluster_name = "<cluster_name>"
AND metric.type = "kubernetes.io/node/cpu/allocatable_cores"
```

**Per-pool scoping is deliberately not offered.** On GKE the node pool is not a queryable label on `k8s_node` metric series: the resource labels are only `project_id`/`location`/`cluster_name`/`node_name`; the pool is exposed only through Cloud Monitoring metadata labels, which the (now deprecated) MQL and the Monitoring filter language can read but the PromQL bridge cannot. `node_name` embeds the pool but GKE truncates it (`stable-pool-medium` becomes `stable-pool-medi`), so a `node_name` regex silently mismatches. The clean per-pool source is kube-state-metrics (`kube_node_labels`) queried in PromQL, but kube-state-metrics is off on the target cluster and enabling it bills Managed Prometheus sample ingestion, which is a poor trade for a cost alert. Per-pool is therefore a documented follow-up (enable kube-state-metrics, add a `condition_prometheus_query_language` per pool), not part of this change.

**File layout.** New `gke_node_count.tf` (locals + resource), `gke_node_count` variable appended to `variables.tf`, `gke_node_count_alert_policy_name` output in `outputs.tf`, an `examples/gke-node-count/` (or an added block in the existing generic example), regenerated `README.md` via terraform-docs, `CHANGELOG.md` entry.

**Consumer rewire (`zambon-ops`).** Bump the module version to the new release, set `gke_node_count = { enabled = true, cluster_name = var.cluster_name, threshold = 16, notification_channels = <platform channels> }` in `terraform.tfvars`, delete `google_monitoring_alert_policy.gke_node_count` (and its `locals.cost_monitoring_gke_node_count_threshold`) from `cost-monitoring.tf`. Because the resource address moves from the root module to the child module, `terraform plan` shows destroy-then-create of the policy. Optionally a `moved {}` block cannot cross the root↔module boundary for a differently-named resource, so a clean recreate is expected and acceptable (the alert is stateless).

## Risks / Trade-offs

- **Total-only scope.** Per-pool alerting is not delivered here (see Filter assembly). A future follow-up can add it via kube-state-metrics plus a `condition_prometheus_query_language` per pool, at the cost of enabling and paying for kube-state-metrics ingestion.
- **Dynamic baseline is out of scope.** "Alert when current is above the trailing 14-day average" has no native Cloud Monitoring condition; it needs a PromQL `avg_over_time([14d])` subquery (heavy) or a Managed Prometheus recording rule plus a PromQL alert. Noted as a possible follow-up; the static 75%-of-max threshold used by `zambon-ops` is simpler and better suited to a "approaching the ceiling" signal.
- **Churn overcount.** `REDUCE_COUNT` counts every node series present in the alignment window, so a long `alignment_period` counts terminated spot/preemptible nodes and overcounts. Default is `60s` (the metric sample interval) so the count tracks live nodes; consumers can raise it to smooth sampling jitter at the cost of some ghosting.
- **Recreate on rewire.** The consumer's existing policy is destroyed and recreated. Harmless for a stateless alert, but note it in the `zambon-ops` MR so reviewers expect the diff.
- **Single-threshold limitation.** No CRITICAL/WARNING ladder yet. Acceptable per the issue's estimate; the variable can grow into a list later without breaking the simple case if introduced as an additional optional field.
- **Threshold defaults.** Default `16` and the "max 22 nodes" note are `zambon-ops`-specific; other consumers must set their own `threshold`. The default is a sane starting point, not a universal truth.
