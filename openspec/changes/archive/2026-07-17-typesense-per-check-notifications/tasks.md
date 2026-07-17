# Tasks: typesense-per-check-notifications

## 1. Variable schema (variables.tf)

- [x] 1.1 Add `notification_enabled = optional(bool, null)` and `notification_channels = optional(list(string), null)` to each of the five Typesense check blocks (`uptime_check`, `container_check`, `log_check`, `flood_check`, `workload_check`).
- [x] 1.2 Document the resolution order in the `typesense` variable description (check-level non-null wins → service level → root; disabled means empty list; `[]` override is legal).

## 2. Service file (typesense.tf)

- [x] 2.1 Add a single per-app-per-check resolution local computing `effective_channels` (`coalesce` on the toggle, then on the channel lists), replacing direct references to `local.typesense_notification_channels` in all policy resources.
- [x] 2.2 Wire `container_check`, `log_check`, `flood_check` and every `workload_check` family (memory, CPU, volume, replica) to their check's resolved entry.
- [x] 2.3 Pass the resolved list of `uptime_check` to `module.typesense_uptime_checks` via the existing `alert_notification_channels` input (no submodule change).

## 3. Examples and docs

- [x] 3.1 Extend `examples/main.tf`/`examples/test.tfvars`: one silent check (`notification_enabled = false`) and one check-level channel override.
- [x] 3.2 `make generate-docs`.
- [x] 3.3 CHANGELOG Added entries under `[Unreleased]` (per-check notification toggle and channel override, resolution order).

## 4. Verification

- [x] 4.1 `make lint` passes.
- [x] 4.2 Zero-diff check: a downstream stack bumps the ref without config changes and `terraform plan` shows no changes. _Verified locally (2026-07-17) on a consumer stack pinned to commit `7a2de8c` with no notification fields set: `0 to change, 0 to destroy` across all typesense policies (the only additions were the consumer's two pre-existing missing flood policies, unrelated to this change)._
- [x] 4.3 Behavior checks on a downstream stack or fixtures: silent check plans with empty `notification_channels`; check-level override plans with only the overridden channel while sibling checks keep service routing; check-level `notification_enabled = true` under a disabled service plans with the check's channels. _First two verified on the same consumer stack: `workload_check.notification_enabled = false` on one app updated all 7 of its workload policies in-place to an empty channel list; `log_check.notification_channels` set to a one-channel subset updated only that app's log policy to exactly that channel; all sibling checks absent from the diff (8 in-place updates total, `notification_channels` only). The re-enable-over-disabled-service scenario was not exercised on the consumer stack (requires flipping the service-level toggle); cover it with a fixture if needed._

## 5. Change management

- [x] 5.1 Single PR (additive, single-service change): spec artifacts + implementation, conventional commit `feat(typesense): ...` with the issue ref.
- [x] 5.2 Sync delta specs into `openspec/specs/` (done in this PR; `openspec validate --specs` passes).
- [x] 5.3 Archive the change (done in this PR). Tag the minor release after merge.
