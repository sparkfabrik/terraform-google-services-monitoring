# Tasks: fix-typesense-flood-rate-limit

## 1. Implementation

- [x] 1.1 Remove the `notification_rate_limit` block from `alert_strategy` in `google_monitoring_alert_policy.typesense_flood_alert` (typesense.tf), keeping `auto_close`.
- [x] 1.2 Remove the `notification_rate_limit` field from the `flood_check` object in `variables.tf`.
- [x] 1.3 Remove the field from the `flood_check` example in `examples/main.tf`.

## 2. Docs

- [x] 2.1 Run `make generate-docs` to refresh the README terraform-docs block.
- [x] 2.2 Add CHANGELOG entries under `[Unreleased]` (Fixed: flood alert policy creation rejected by the Monitoring API; Removed: `flood_check.notification_rate_limit`).

## 3. Verification

- [x] 3.1 `make lint` passes.
- [ ] 3.2 Apply check: a downstream stack with `flood_check` enabled plans and applies the flood policies without the 400 error; the created policies show `auto_close` and no notification rate limit.
- [ ] 3.3 No-diff check: a consumer without `flood_check` sees no plan change on the version bump.

## 4. Change management

- [ ] 4.1 Commit spec artifacts and implementation (single PR: trivial, single-service fix), conventional commits with the issue ref.
- [ ] 4.2 After merge: sync the delta spec into `openspec/specs/typesense-log-alert/` and archive the change to `openspec/changes/archive/YYYY-MM-DD-fix-typesense-flood-rate-limit/`; tag the 0.19.0 minor release.
