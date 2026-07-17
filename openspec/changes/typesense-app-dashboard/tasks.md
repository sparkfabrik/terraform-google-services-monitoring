# Tasks: typesense-app-dashboard

## 1. Variable schema (variables.tf)

- [ ] 1.1 Add `dashboard = optional(object({ enabled = optional(bool, true), display_name = optional(string, null) }), null)` to `apps[*]`.
- [ ] 1.2 Add validation: an app with `dashboard` configured must have at least one check (`uptime_check`, `container_check`, `log_check`, `flood_check`, `workload_check`).

## 2. Dashboard implementation (typesense.tf, delimited section or sibling typesense_dashboard.tf)

- [ ] 2.1 Locals: dashboard-enabled apps map; per-app title (`Typesense vitals — <app_key> (cluster=..., namespace=...)`, namespace segment omitted when null; `display_name` override wins).
- [ ] 2.2 Tile builders per section, each an empty list when the backing check is absent: replica scorecard (PromQL count, integer thresholds at quorum and `expected_replicas`), memory/CPU/volume per-pod charts (`groupByFields` on pod_name), restart chart, flood log-volume chart, error-log rate chart, uptime scorecard + latency chart.
- [ ] 2.2b `google_logging_metric` counter for error logs (`severity>=ERROR`, flood-metric filter pattern with the app's cluster/namespace), created only for apps with both `log_check` and the dashboard enabled.
- [ ] 2.3 Position computation in HCL: `concat()` the present sections, compute `yPos` from accumulated heights, attach `xPos`/`yPos` via `merge()` **only when non-zero** (origin tile carries neither key).
- [ ] 2.4 Drift-safe JSON rules everywhere: no empty arrays/objects/strings, no nulls (filter optional attributes before `jsonencode`), enums uppercase, no zero-value enums, no `blankView`, no `minAlignmentPeriod` outside xyChart, integer thresholds only.
- [ ] 2.5 `google_monitoring_dashboard` resource with `dashboard_json = jsonencode(...)`, `for_each` over the enabled apps.

## 3. Outputs, examples, docs

- [ ] 3.1 Output: dashboard ids keyed by app.
- [ ] 3.2 `examples/main.tf` / `examples/test.tfvars`: one app with `dashboard = {}` and one with a `display_name` override.
- [ ] 3.3 `make generate-docs`; CHANGELOG Added entries under `[Unreleased]`.

## 4. Verification

- [ ] 4.1 `make lint` passes.
- [ ] 4.2 Rendered-fixture validation: extract the rendered `dashboard_json` (from `terraform plan -json` on the examples, or `terraform console`), then run the dashboard normalizer in check mode and `gcloud monitoring dashboards create --config-from-file=<fixture> --validate-only` against a sandbox project. Commit the rendered fixture as the golden example.
- [ ] 4.3 Zero-diff check: a downstream stack bumps the ref without config changes and `terraform plan` shows no changes.
- [ ] 4.4 Adoption check: enabling `dashboard = {}` on one app plans exactly one new `google_monitoring_dashboard` and nothing else.
- [ ] 4.5 Drift check (requires an apply in a sandbox project, not a consumer): apply the examples dashboard, re-run `terraform plan`, confirm the dashboard resource shows no diff; classify and fix any config-only additions before merging.

## 5. Change management (single branch/PR, ordered commits)

- [ ] 5.1 Commit 1: the OpenSpec artifacts exactly as reviewed (`docs(openspec): ...`).
- [ ] 5.2 Commit 2: the implementation (`feat(typesense): ...` with the issue ref). Do not amend commit 1.
- [ ] 5.3 Commit 3 (only if local/consumer testing requires spec adjustments): update the artifacts with test evidence or corrections and wait for explicit approval before committing.
- [ ] 5.4 Commit 4: `openspec validate`, sync the spec into `openspec/specs/`, archive the change to `openspec/changes/archive/` (`docs(openspec): sync and archive ...`).
- [ ] 5.5 The user merges the PR manually; tagging the release remains a separate human decision.
