# Tasks: typesense-schema-cleanup

## 1. Variable schema (variables.tf)

- [x] 1.1 Add `namespace = optional(string, null)` at the app level, next to `cluster_name`; remove the `namespace` attribute from `container_check`, `log_check`, `flood_check` and `workload_check`.
- [x] 1.2 Rename/retype timing fields: `pod_restart.alignment_period` → `alignment_period_seconds` (number), `pod_restart.duration` → `duration_seconds` (number); workload threshold lists `alignment_period`/`duration` (strings) → `alignment_period_seconds`/`duration_seconds` (numbers, defaults 300); `log_check.logmatch_notification_rate_limit` (string `"300s"`) → `logmatch_notification_rate_limit_seconds` (number, default 300).
- [x] 1.3 Update validations: app-level `namespace` required when any Kubernetes-based check is configured (static message: dynamic error messages need Terraform 1.9+ and the module keeps `>= 1.5`); all `_seconds` fields validated `> 0`; drop the per-block namespace validations.
- [x] 1.4 Update the `typesense` variable description (namespace placement, timing convention).

## 2. Service file (typesense.tf)

- [x] 2.1 Point every locals/filter/display-name reference of a block-level `namespace` to the app-level field (container, log, flood, workload families and the log metric).
- [x] 2.2 Render `"${n}s"` from the renamed numeric fields wherever the provider expects Go-duration strings (workload aggregations, log rate limit).
- [x] 2.3 Confirm no `for_each` key composition changes (keys must stay `<app>` / `<app>--<severity>--<threshold>`), so migrated consumers get a zero-change plan.

## 3. Examples and docs

- [x] 3.1 Migrate `examples/main.tf` and `examples/test.tfvars` to the new shape (namespace once per app, numeric timing fields).
- [x] 3.2 `make generate-docs` for the README block.
- [x] 3.3 Migration docs: short breaking entries in CHANGELOG under `[Unreleased]` referencing a new `UPGRADING.md`, which carries the old → new field table, a full before/after app example and the silent-drop warning.

## 4. Verification

- [x] 4.1 `make lint` passes.
- [ ] 4.2 Zero-diff migration check: on a downstream stack, bump the ref and migrate values verbatim; `terraform plan` must show no changes.
- [x] 4.3 Negative checks (revised: Terraform silently discards unknown object attributes, so no type error exists for legacy fields — see design decision 2/4): an app with `workload_check` and no app-level namespace fails validation; a negative `_seconds` value fails validation; an uptime-only app without namespace passes; a leftover block-level `namespace` or legacy `alignment_period = "300s"` is silently ignored (verified via `terraform validate` fixtures on Terraform 1.13).

## 5. Change management

- [ ] 5.1 Spec-first: commit artifacts and open the spec PR for review before implementation (breaking interface change).
- [ ] 5.2 Implementation PR: `feat(typesense)!:` conventional commit with the issue ref.
- [ ] 5.3 After merge: sync delta specs into `openspec/specs/`, archive the change, tag the breaking minor release.
