# Design: typesense-app-dashboard

## Context

One `google_monitoring_dashboard` per enabled Typesense app, built from data the module already resolves per app (cluster, namespace, container/volume selectors, `expected_replicas`, flood metric name, uptime check). The Cloud Monitoring API normalizes `dashboard_json` on every write, so any committed value the API strips (zero/empty/default values) produces a perpetual plan diff; authoring rules below follow the known normalization behavior (provider issue #16173 and related).

## Goals / Non-Goals

**Goals**

- One dashboard per app, adopted with one flag, fitting 1/3/5-replica topologies with identical JSON (`pod_name` grouping everywhere).
- Drift-free: `terraform plan` immediately after `apply` shows no changes.
- Graceful degradation: widgets render only when their data source exists for the app.

**Non-Goals**

- Charts on scraped application metrics (out of scope for this change).
- Dashboard-level filters/variables, SLOs, or alert-status widgets.
- A generic dashboard framework for other services (kyverno stays as is; convergence is a later concern).

## Decisions

1. **`jsonencode(...)` over HCL locals, not JSON template files** (kyverno precedent). The dashboard is assembled per app from resolved locals — interpolation is the norm, so `file()` round-tripping is not available anyway; `jsonencode` gives structural plan diffs and keeps everything in one language. Trade-off accepted: no offline `gcloud --validate-only` on a static file; mitigated by a rendered-JSON fixture check in verification.
2. **mosaicLayout with drift-safe authoring.** The issue calls for mosaicLayout and kyverno already uses it. Its known drift class (stripped zero values) is neutralized by construction rules: omit `xPos`/`yPos` keys when 0 (build tiles with `merge()` that only adds position keys when non-zero), never emit empty arrays/objects/strings or zero enums, enums uppercase, no `blankView`, no `minAlignmentPeriod` on non-xyChart widgets.
3. **Conditional widget assembly.** The tile list is built by `concat()` of per-section lists, each empty when the app lacks the backing check (`workload_check` → replica scorecard + saturation charts; `flood_check` → log-volume chart; `uptime_check` → pass-ratio scorecard and latency chart; restarts chart always present). Row positions are computed from the accumulated height of the sections actually present, so layouts stay dense without empty panes.
4. **Thresholds only where float32-exact.** The API rounds threshold values through float32; decimal saturation thresholds (0.85, 0.95) would perma-diff. Replica scorecards use integer thresholds (quorum, expected). Saturation charts carry no threshold overlays in this change; utilization is a 0-1 ratio chart and the alert policies own the thresholds.
5. **Title contract.** Default `Typesense vitals — <app_key> (cluster=<resolved_cluster>, namespace=<namespace>)`, following the module's display-name convention and making the project-level dashboard list self-locating; `dashboard.display_name` overrides. `displayName` is not the resource identity: renames are in-place updates, never recreation.
6. **Gating consistent with the check blocks**: `dashboard = optional(object({...}), null)` — `null` means no dashboard and zero plan diff on upgrade; `enabled = false` mutes without deleting config. Apps without any Kubernetes check can still have a dashboard (uptime-only widgets) as long as `uptime_check` exists; a dashboard on an app with no checks at all fails validation (nothing to render).

## Risks / Trade-offs

- [API normalization changes or an unlisted stripped field slips in → perpetual diff] → acceptance criterion is an apply-then-plan-clean check on a real project; the diff classification rule (config-only additions are the cause) plus the normalization reference make fixes mechanical.
- [PromQL scorecard (replica count) rendering differs from threshold widgets across console versions] → the same query already backs the replica alert; if the scorecard proves brittle, fallback is an xyChart on the identical query — layout unchanged.
- [Conditional assembly makes tile positions config-dependent → enabling a check later reflows the dashboard] → accepted; a reflow is one in-place update, and dense layouts beat permanent placeholder gaps.
- [jsonencode HCL grows large in typesense.tf] → dashboard locals isolated in a clearly delimited section (or a sibling `typesense_dashboard.tf`, still one service per concern); no submodule — a second dashboard consumer can motivate extraction later.

## Migration Plan

- Additive minor release; `dashboard` defaults to `null`, upgrade is zero-diff.
- Adoption per app: `dashboard = {}`. First plan: one new `google_monitoring_dashboard` resource, nothing else.
- Rollback: remove the block (dashboard destroyed, alerts untouched) or pin the previous ref.

## Open Questions

None.
