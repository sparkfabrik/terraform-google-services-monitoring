## Context

This module (`terraform-google-services-monitoring`) provides GCP monitoring alert policies for a curated set of GCP and Kubernetes workload services. The Typesense service currently has two monitoring capabilities: HTTP uptime checks (via the `http_monitoring` submodule) and pod restart alerts (via a `condition_threshold` on `kubernetes.io/container/restart_count`).

Log-based alerting already exists for two other services in this module — Kyverno and cert-manager — both using GCP's native `condition_matched_log` condition type with `notification_rate_limit` in the alert strategy. The Typesense log alert follows these same patterns.

The immediate consumer is the Luiss project (`sito-luiss` GCP project), which runs Typesense in two namespaces: `typesense-clusters-stage` and `typesense-clusters-main`.

## Goals / Non-Goals

**Goals:**

- Alert when Typesense containers produce logs at or above a configurable severity threshold (default: ERROR).
- Alert when Typesense log entry volume exceeds a configurable rate threshold (entries per minute), enabling early detection of log storms before they impact billing.
- Rate-limit notifications to prevent alert fatigue during sustained error or flood conditions.
- Follow the same configuration patterns as Kyverno/cert-manager log alerts for consistency.
- Support per-app configuration so different Typesense instances can have independent settings.

**Non-Goals:**

- Log exclusions for billing protection (handled per-project in infrastructure repos, not in this module).
- Custom message pattern matching (unlike Kyverno, Typesense has no well-defined set of error message patterns to match; a severity filter is sufficient).

## Decisions

### 1. Use `condition_matched_log` for error alerting (not a custom log metric + threshold)

**Choice:** Use the native log-match condition type for `log_check`, same as Kyverno and cert-manager.

**Alternatives considered:**
- `google_logging_metric` + `condition_threshold`: Would enable "alert when error count > N in window W". More sophisticated but overkill for error-level alerting where zero tolerance is the right stance.

**Rationale:** Consistency with existing module patterns. Simpler to configure. The `notification_rate_limit` handles the notification flooding concern adequately.

### 2. Use `google_logging_metric` + `condition_threshold` for flood alerting

**Choice:** For `flood_check`, create a user-defined `google_logging_metric` (counter, counting log entries matching the Typesense namespace/container filter) paired with a `condition_threshold` alert on `ALIGN_RATE`.

**Alternatives considered:**
- `logging.googleapis.com/billing/log_bucket_bytes_ingested` metric: Investigated against the actual #4258 incident data. This metric only breaks down by `resource_type` (e.g., `k8s_container`) — not by namespace or container. Cannot be scoped to Typesense specifically; would fire for any k8s container flood in the project.

**Rationale:** A user-defined log metric is the only GCP primitive that allows namespace + container-scoped volume counting. Cost is negligible (~345 KB/month of metric data per time series, within the 150 MiB free tier per billing account).

### 3. Threshold expressed in entries per minute (required, no default)

**Choice:** `flood_check.threshold_entries_per_minute` is a required field with no default value.

**Rationale:** From the #4258 incident data (caleffi-production-cluster, Apr 1–3 2026): normal Typesense log volume was ~400–800 entries/minute project-wide; the storm peaked at ~7,000–13,000 entries/minute from the Typesense namespace alone. A safe threshold is ~3,000 entries/minute for that project, but this is environment-specific. A wrong default (too high = misses the storm; too low = constant noise) is worse than requiring explicit configuration. Operators must set a value that makes sense for their baseline.

### 4. Independent `namespace` field on `flood_check`

**Choice:** `flood_check` has its own `namespace` field, independent from `container_check` and `log_check`.

**Rationale:** Consistent with the `log_check` design decision. Explicit over implicit; not every app will have all three checks configured.

### 5. Filter scoped to `container_name="typesense"`

**Choice:** Both `log_check` and `flood_check` filters include `resource.labels.container_name="typesense"`.

**Rationale:** Typesense pods may have sidecar containers. Filtering by container name prevents sidecar logs from polluting the signal.

## Risks / Trade-offs

- **[Risk] Typesense may not emit ERROR-level logs during degraded states** → Mitigation: The `min_severity` variable allows operators to lower to `WARNING` if they observe that relevant signals come at that level.

- **[Risk] Alert fatigue if error logs are frequent in a non-critical scenario** → Mitigation: `notification_rate_limit` (default 300s) ensures at most one notification per 5 minutes. `auto_close` (default 3600s) ensures incidents auto-resolve.

- **[Trade-off] No message pattern filtering on `log_check`** → Keeps the interface simple but means all errors trigger the alert equally. A Kyverno-style `error_patterns_include/exclude` can be added in a future iteration without breaking changes.

- **[Risk] Wrong `flood_check` threshold causes alert noise or misses the storm** → Mitigation: Threshold is required with no default, forcing operators to set an environment-specific value. The #4258 incident data provides a concrete reference: ~3,000 entries/minute is a reasonable starting point for a Typesense cluster that peaks at ~800 entries/minute under normal conditions.

- **[Risk] `google_logging_metric` has ~1 minute propagation delay** → The flood alert may fire 1–2 minutes after the storm starts. Acceptable for the billing-protection use case where the relevant timescale is hours, not seconds.

- **[Trade-off] Two resources per app for `flood_check`** (metric + alert policy) → More state in `terraform state`, slightly more complexity. Unavoidable given the GCP primitive required for namespace-scoped volume counting.
