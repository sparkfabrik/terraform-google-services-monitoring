# Design: typesense-workload-check

## Context

The `typesense` service file follows the module's established idioms: one object variable with `optional(...)` sub-attributes, per-app sub-check objects that are off when `null`, locals that filter enabled checks into `for_each` maps, and a notification-channel fallback chain (check → service → root). Two condition styles exist in the codebase: `condition_threshold` with Monitoring filter strings (dominant) and `condition_prometheus_query_language` (konnectivity agent only). The uptime check is delegated to `modules/http_monitoring`. This change adds a fifth per-app sub-check (`workload_check`) plus small extensions to the existing ones, and must leave every current consumer's plan untouched.

## Goals / Non-Goals

**Goals**

- Saturation and availability alerting for Typesense workloads using only non-chargeable GKE system metrics (`kubernetes.io/*`, `kubernetes_io:container_uptime`).
- Topology-agnostic: the same configuration shape serves 1-, 3- and 5-replica clusters; raft quorum is derived, never hand-configured.
- Zero plan diff for consumers upgrading from the previous release without config changes.
- Support multiple GKE clusters per GCP project and multiple Typesense clusters per GKE cluster from one module instance.

**Non-Goals**

- Alerts on scraped application metrics (`prometheus.googleapis.com/typesense_*`): a later change.
- Dashboards: a later change.
- Generic reusable "workload monitoring" submodule: deliberately Typesense-scoped, consistent with the one-file-per-service layout.

## Decisions

1. **One `workload_check` block, not separate blocks per alert family.** Namespace and `expected_replicas` are declared once and every alert family derives from them. Families are individually disabled by emptying their threshold list (or `replica_availability.enabled = false`). Alternative (one top-level block per family) rejected: triples the adoption surface and duplicates namespace declarations.

2. **cloud_sql-style threshold lists** (`list(object({ severity, threshold, alignment_period, duration }))`) for memory, CPU and volume, instead of fixed `warning`/`critical` fields. This is the proven shape in `cloud_sql.tf` (flattened `for_each` keyed `<app>--<severity>--<threshold>`), supports N tiers, and `[]` is a natural per-family kill switch.

3. **Defaults on.** Thresholds ship pre-filled (memory 0.85 WARNING / 0.95 CRITICAL, CPU 0.90 WARNING, volume 0.75 WARNING / 0.85 CRITICAL, grounded in the Typesense production guide). Adopting the block requires only `namespace` and `expected_replicas`. Alternative (empty defaults, everything explicit) rejected: the module's value is curated defaults; consumers can still override or empty any list.

4. **Ratio metrics, not absolute bytes.** `kubernetes.io/container/memory/limit_utilization` (with `memory_type="non-evictable"`), `container/cpu/limit_utilization`, `pod/volume/utilization`. Ratios self-adjust when consumers resize limits or PVCs, so thresholds survive vertical scaling. Requires containers to declare resource limits, which the Typesense operator CRD always does; documented as a precondition.

5. **Replica availability via PromQL on `kubernetes_io:container_uptime`**, cloning the konnectivity pattern (`count(max by (pod_name)(...)) or on() vector(0)`). Two policies: WARNING `< expected_replicas`, CRITICAL `< floor(expected_replicas/2) + 1` (raft quorum). The WARNING policy is created only when `expected_replicas > quorum`, so a 1-replica cluster gets a single "pod down" CRITICAL instead of two identical alerts. Caveat: `container_uptime` counts running containers, not ready ones; readiness regressions are covered by the uptime check content matcher (decision 7), while this alert covers absence and crash-loops.

6. **Workload selection by `namespace` + `container_name` (default `"typesense"`), with optional `controller_name`.** Consumers must not need to know operator-generated StatefulSet names in the common case. When two TypesenseClusters share a namespace, `controller_name` disambiguates via `metadata.system_labels.top_level_controller_name` (filter conditions) and `metadata_system_top_level_controller_name` (PromQL) — the same label the konnectivity alert already uses. Volume alerts filter `metric.labels.volume_name` (default `"data"`, the operator's PVC template name) so configmap/secret mounts do not alert; overridable for other layouts.

7. **Uptime content assertion as a generic submodule feature.** `modules/http_monitoring` gains `content_matchers = optional(list(object({ content, matcher = optional(string, "CONTAINS_STRING") })), [])` mapped 1:1 to `content_matchers` blocks. The Typesense `uptime_check` exposes a single `content_match = optional(string)` convenience field. No auto-defaulting: silently adding a matcher on upgrade would mutate existing uptime checks and break non-JSON health endpoints. Alternative (Typesense-only implementation inside `typesense.tf`) rejected: the submodule is the single owner of `google_monitoring_uptime_check_config`.

8. **Per-app `cluster_name` with service-level fallback.** Resolution happens once, in the per-app locals (`coalesce(app.cluster_name, var.typesense.cluster_name)`), and feeds workload, container, log and flood checks alike. Validation: every app with any Kubernetes-based check enabled must resolve a non-empty cluster name. `null` default keeps existing configurations valid unchanged.

9. **`alert_documentation` on all Typesense policies.** Optional service-level string rendered into each policy's `documentation` block (kyverno precedent). Applied uniformly, including the pre-existing restart/log/flood policies; a `null` default renders no block, so existing plans stay clean.

## Risks / Trade-offs

- [Containers without resource limits produce no `limit_utilization` series → silent non-coverage] → documented precondition; the replica-availability alert still fires on pod loss, and the README notes the requirement.
- [`container_uptime` counts running-but-unready pods as present → quorum loss with pods Running is not caught by the replica alert] → mitigated by the uptime check content matcher on cluster status, which is quorum-aware end to end.
- [Volume alert default `volume_name = "data"` is operator-specific → custom deployments with differently named PVC volumes silently unmonitored] → overridable field, called out in the variable description.
- [Threshold-list defaults change alert cardinality if a consumer later enables the block expecting one alert per family] → display names embed severity and threshold, and `examples/main.tf` shows the default expansion.
- [PromQL conditions cannot use `trigger.count`-style aggregation options → duration is the only debounce] → default `duration_seconds = 300` balances flap suppression against time-to-page; overridable.

## Migration Plan

- Purely additive minor release. Consumers bump the `ref` with no config change: plan shows no diff.
- Adoption per app: add `workload_check = { namespace = "...", expected_replicas = N }` (+ `content_match` on the uptime check where the health endpoint exposes cluster status).
- Rollback: pin the module `ref` back to the previous release; all new resources are destroyed cleanly (no state moves, no shared resources touched).

## Open Questions

- None blocking. Threshold defaults may be revisited after the first weeks of production signal (tracked as follow-up in refs platform/#4649).
