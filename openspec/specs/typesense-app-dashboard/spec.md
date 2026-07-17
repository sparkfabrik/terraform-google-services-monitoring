# typesense-app-dashboard

## Purpose

Per-app Cloud Monitoring dashboard for self-hosted Typesense apps, driven by the `dashboard` block. One `google_monitoring_dashboard` per enabled app, assembled strictly from data the module already wires at zero metric cost: free `kubernetes.io` system metrics, the flood log-based metric, a dedicated error-log counter metric and the uptime check. Widgets render only for the checks the app configures, and the JSON is authored drift-safe so a plan immediately after apply shows no changes.

## Requirements

### Requirement: Dashboard gating

The module SHALL create one `google_monitoring_dashboard` per Typesense app whose `dashboard` block is non-null with `enabled = true`, and only when `typesense.enabled` is true. Validation SHALL fail when an app configures `dashboard` but no check at all (nothing to render).

#### Scenario: Dashboard not configured

- **WHEN** an app has no `dashboard` attribute
- **THEN** no dashboard resource is created and an upgrading consumer sees no plan diff

#### Scenario: Dashboard adopted

- **WHEN** an app with `workload_check` sets `dashboard = {}`
- **THEN** exactly one new `google_monitoring_dashboard` is planned and no other resource changes

#### Scenario: Dashboard on a checkless app

- **WHEN** an app configures `dashboard` and none of `uptime_check`, `container_check`, `log_check`, `flood_check`, `workload_check`
- **THEN** Terraform validation fails

### Requirement: Dashboard title

The dashboard `displayName` SHALL default to `Typesense vitals — <app_key> (cluster=<resolved_cluster>, namespace=<namespace>)` (for apps without a namespace, the namespace segment is omitted) and SHALL be overridable via `dashboard.display_name`. A title change SHALL be an in-place update.

#### Scenario: Default title

- **WHEN** an app `search_prod` with namespace `ts-prod` on cluster `main-cluster` enables the dashboard
- **THEN** the dashboard displayName is `Typesense vitals — search_prod (cluster=main-cluster, namespace=ts-prod)`

#### Scenario: Title override

- **WHEN** the app sets `dashboard.display_name = "Search vitals"`
- **THEN** the dashboard displayName is exactly `Search vitals` and changing it later updates the resource in place

### Requirement: Widget set from available data

The dashboard SHALL render, conditionally on the app's configured checks: with `workload_check` — a running-replicas scorecard (PromQL count on `kubernetes_io:container_uptime`, integer thresholds at `expected_replicas` and quorum) and per-pod charts for memory limit utilization, CPU limit utilization and PVC volume utilization; with `container_check` or `workload_check` — a per-pod restart-count chart; with `flood_check` — a log-volume chart on the app's flood log-based metric; with `log_check` — an error-log rate chart backed by a dedicated per-app log-based counter metric (`severity>=ERROR`, same namespace/cluster scoping as the flood metric) that the module creates only when the app has both `log_check` and the dashboard enabled; with `uptime_check` — an uptime pass-ratio scorecard and a check-latency chart. Sections absent from the app's configuration SHALL be omitted entirely (no empty panes) and remaining tiles reflow densely.

#### Scenario: Full app

- **WHEN** an app has all five checks and the dashboard enabled
- **THEN** the dashboard contains the replica and uptime scorecards, the four per-pod charts, the log-volume chart, the error-log rate chart and the latency chart, and the module creates the error-log counter metric

#### Scenario: Error-log metric gated on the dashboard

- **WHEN** an app has `log_check` but no `dashboard`
- **THEN** no error-log counter metric is created and the plan is unchanged from the previous release

#### Scenario: Uptime-only app

- **WHEN** an app has only `uptime_check` and the dashboard enabled
- **THEN** the dashboard contains only the uptime scorecard and latency chart, with no empty tiles

### Requirement: Topology-independent layout

Every time-series chart SHALL group by `pod_name` so one line per pod appears automatically; the dashboard JSON SHALL be identical for apps of any `expected_replicas` value (1, 3, 5, ...) except for the integer scorecard thresholds derived from `expected_replicas`.

#### Scenario: Same layout across replica counts

- **WHEN** two apps differ only in `expected_replicas` (1 vs 5)
- **THEN** their dashboards differ only in the replica scorecard thresholds

### Requirement: Drift-free dashboard JSON

The generated `dashboard_json` SHALL contain no value the Cloud Monitoring API strips on write: no `xPos`/`yPos` keys with value 0, no empty arrays/objects/strings, no null values, no zero-value enums, enum values uppercase, and no threshold values that are not float32-exact (thresholds are integers in this dashboard). A `terraform plan` run immediately after `apply` SHALL show no changes for the dashboard resource.

#### Scenario: Clean plan after apply

- **WHEN** a consumer applies an app dashboard and re-runs `terraform plan` with unchanged configuration
- **THEN** the dashboard resource shows no diff

#### Scenario: Origin tile

- **WHEN** the first tile of the layout sits at position (0, 0)
- **THEN** the generated JSON omits its `xPos` and `yPos` keys entirely

### Requirement: Dashboard outputs

The module SHALL export the created dashboard resource ids keyed by app name.

#### Scenario: Two apps with dashboards

- **WHEN** two apps enable the dashboard
- **THEN** the dashboard output map contains both apps' dashboard ids
