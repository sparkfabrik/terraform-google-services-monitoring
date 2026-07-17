# Proposal: typesense-app-dashboard

## Why

Typesense monitoring now alerts on saturation, availability, logs and uptime, but there is no single place to look at an app's vitals — operators assemble the picture from Metrics Explorer queries per incident. A per-app Cloud Monitoring dashboard built from the metrics the module already wires (free `kubernetes.io` system metrics, the flood log-based metric, uptime checks) closes that gap at zero metric cost, and the module is the natural home: the dashboard's filters are the alert filters, already resolved per app (cluster, namespace, container, volume, replicas). Tracking: refs platform/#4649.

## What Changes

- New optional per-app `dashboard` block (`enabled` default true, `display_name` default null), presence-enabled like the other check blocks. One `google_monitoring_dashboard` per enabled app.
- Default title `Typesense vitals — <app_key> (cluster=<resolved_cluster>, namespace=<namespace>)`, following the module's display-name convention; `display_name` overrides it. The title is not the dashboard's identity, so renaming never recreates the resource.
- Dashboard content, strictly from data available without scraped application metrics:
  - scorecards: running replicas (PromQL count on `kubernetes_io:container_uptime`) against `expected_replicas`, uptime check pass ratio, error-log rate;
  - per-pod charts (every chart grouped by `pod_name`, so the same layout serves 1, 3 or 5 replicas): memory limit utilization, CPU limit utilization, PVC volume utilization, container restart count;
  - log volume chart from the flood log-based metric, rendered only when the app's `flood_check` is enabled (the metric does not exist otherwise);
  - error-log rate chart backed by a new per-app log-based counter metric (`severity>=ERROR`, flood-metric pattern), created and rendered only when the app has `log_check` and the dashboard enabled; generated series volume is ~0.33 MiB/month per app, inside the project free tier;
  - uptime check latency, rendered only when the app has an `uptime_check`.
- Widgets that depend on `workload_check` data (replica scorecard, saturation charts) render only when the app has `workload_check` configured; the dashboard degrades gracefully for apps with fewer checks.
- mosaicLayout via `dashboard_json = jsonencode(...)` in HCL locals (kyverno dashboard pattern); authored to avoid `dashboard_json` perpetual plan drift.
- Non-breaking: `dashboard` defaults to `null`; consumers upgrading without config changes get a zero-change plan.

## Capabilities

### New Capabilities

- `typesense-app-dashboard`: the per-app Cloud Monitoring dashboard — gating, title contract, widget set and its conditional rendering, pod-level grouping.

### Modified Capabilities

None (no existing requirement changes; the dashboard consumes what the other capabilities define).

## Impact

- `variables.tf`: `dashboard` block on `apps[*]`.
- `typesense.tf` (or a dedicated section within it): dashboard locals, one `google_logging_metric` counter for error logs per app with `log_check` + dashboard, and the `google_monitoring_dashboard` resource, reusing the existing per-app resolution locals.
- `outputs.tf`: dashboard ids keyed by app.
- `examples/main.tf` / `examples/test.tfvars`: one app with the dashboard enabled and a custom title.
- `README.md` regenerated; `CHANGELOG.md` Added entries under `[Unreleased]`; ships as a normal minor release.
