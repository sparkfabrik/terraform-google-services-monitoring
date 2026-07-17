# Proposal: typesense-schema-cleanup

## Why

The `typesense` variable schema accumulated two inconsistencies across releases. First, `namespace` is declared inside every Kubernetes-based check block (`container_check`, `log_check`, `flood_check`, `workload_check`), so consumers repeat the same value up to four times per app while the sibling `cluster_name` already lives once at app level. Second, duration-like fields use three different conventions (bare numbers, `_seconds`-suffixed numbers, and `"Ns"` Go-duration strings), forcing consumers to remember which block wants which spelling. A breaking cleanup has been accepted by the maintainers: both issues are plan-time-only breaks with zero infrastructure diff after migration. Tracking: refs platform/#4649.

## What Changes

- **BREAKING** `namespace` moves to the app level (`apps[*].namespace`, optional string next to `cluster_name`) and is removed from `container_check`, `log_check`, `flood_check` and `workload_check`. Validation requires an app-level `namespace` when any Kubernetes-based check is configured; uptime-only apps need none. No fallback to the old location. Terraform's object conversion silently discards attributes that are not part of an `optional()` object type, so a leftover per-block `namespace` is ignored rather than rejected; the unmigrated shape (namespace only in blocks) still fails loudly through the app-level validation naming the app.
- **BREAKING** All duration-like fields become numbers of seconds with a `_seconds` suffix:
  - `container_check.pod_restart.alignment_period` → `alignment_period_seconds`, `.duration` → `duration_seconds` (numbers, values unchanged);
  - `workload_check.{memory,cpu,volume}_utilization[*].alignment_period`/`duration` (strings `"300s"`) → `alignment_period_seconds`/`duration_seconds` (numbers);
  - `log_check.logmatch_notification_rate_limit` (string `"300s"`) → `logmatch_notification_rate_limit_seconds` (number).
  - Already conformant and unchanged: every `auto_close_seconds`, `flood_check.alignment_period_seconds`/`duration_seconds`, `replica_availability.duration_seconds`.
  - Leftover legacy timing attributes are silently discarded by Terraform's object conversion (no type error is possible for extra attributes); the renamed `_seconds` field then takes its default. The CHANGELOG migration table is the contract for carrying values over.
- Toggle semantics unchanged: block presence enables a check, `enabled` mutes it; no block gains a non-null default.
- Migrating a configuration with identical values produces a zero-change plan: the renamed fields feed only filter strings and display names, and no `for_each` key changes.
- CHANGELOG carries a before/after migration snippet covering both changes.

## Capabilities

### New Capabilities

- `typesense-config-schema`: the cross-cutting configuration contract of the `typesense` variable — app-level `namespace` placement and resolution, and the uniform `_seconds` numeric convention for all duration-like fields.

### Modified Capabilities

- `typesense-log-alert`: log and flood scenarios reference the app-level `namespace` instead of a block-level one; the rate-limit input becomes `logmatch_notification_rate_limit_seconds` (number).
- `typesense-workload-vitals`: workload scenarios reference the app-level `namespace`; threshold-list timing fields become `_seconds` numbers.

## Impact

- `variables.tf`: `typesense` object reshaped as above; validations updated (namespace-required-when-k8s-checks, positive timing numbers).
- `typesense.tf`: locals read `apps[*].namespace`; interpolations render `"${n}s"` where the API wants Go-duration strings.
- `examples/main.tf`, `examples/test.tfvars`: migrated to the new shape.
- `README.md` regenerated; `CHANGELOG.md` gets Changed/Removed entries under `[Unreleased]` with the migration table; ships as a breaking minor release under 0.x semver (`feat(typesense)!`).
- All known consumers migrate with a small mechanical edit (delete duplicated namespaces, rename timing fields); their applied infrastructure does not change.
