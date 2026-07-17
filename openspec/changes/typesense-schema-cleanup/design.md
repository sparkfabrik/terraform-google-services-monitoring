# Design: typesense-schema-cleanup

## Context

The `typesense` variable grew check by check across releases; each Kubernetes-based check block carries its own required `namespace`, and duration-like fields exist in three spellings (bare numbers, `_seconds` numbers, `"Ns"` strings). Maintainers accepted a breaking cleanup. Both changes affect only the variable schema and the locals that read it: filter strings, display names and `for_each` keys keep their rendered values, so migrated consumers see a zero-change plan.

## Goals / Non-Goals

**Goals**

- One declaration of `namespace` per app, next to `cluster_name`.
- One timing convention: numbers of seconds, `_seconds` suffix, everywhere.
- Loud, self-explanatory plan-time failures for unmigrated configurations.
- Zero infrastructure diff for a value-preserving migration.

**Non-Goals**

- Changing toggle semantics (block presence enables, `enabled` mutes) or any default value.
- Renaming checks or restructuring blocks beyond the two cleanups.
- Grace-period compatibility with the old schema.

## Decisions

1. **App-level `namespace` is `optional(string, null)` + validation, not hard-required.** Uptime-only apps have no namespace. Validation fails when any of `container_check`, `log_check`, `flood_check`, `workload_check` is non-null and `namespace` is null, naming the app key.
2. **No fallback to per-block `namespace`.** The attribute is removed from the block types entirely, so a leftover produces Terraform's native `An attribute named "namespace" is not expected here` at plan time. Alternative (coalesce fallback like `cluster_name` got in the previous release) rejected: maintainers accepted the break, and a fallback would leave two sources of truth and cleanup debt.
3. **Timing convention: number + `_seconds` suffix.** It already covers the majority of fields (`auto_close_seconds`, all of `flood_check`, `replica_availability.duration_seconds`). Renamed/retyped: `pod_restart.alignment_period`/`duration` (bare numbers gain the suffix), workload threshold-list `alignment_period`/`duration` (strings become numbers), `logmatch_notification_rate_limit` (string becomes `logmatch_notification_rate_limit_seconds`). Alternative (Go-duration strings everywhere) rejected: strings admit invalid values (`"5m"`, `"abc"`) that fail late at API time, while numbers are validated by the type system and the module already interpolates `"${n}s"` where the provider wants strings.
4. **Rename plus retype in one step, no aliases.** A transitional alias set (accepting both spellings) doubles the schema surface for one release and silently masks half-migrated configs. Type errors name every offending attribute; the CHANGELOG migration table maps old → new one-to-one.
5. **Validation for timing numbers**: positive integers required (`> 0`); no upper bound (the API enforces its own limits).

## Risks / Trade-offs

- [Consumers bump without migrating and get a wall of type errors] → errors are individually self-explanatory and the CHANGELOG carries a complete before/after snippet; the break cannot corrupt state because plan never succeeds.
- [A consumer translates `"300s"` to a wrong number during migration] → values in the migration table are carried over verbatim (`"300s"` → `300`); display names embed thresholds, so a wrong value is visible in the first plan as a policy update rather than silently absorbed.
- [Renovate auto-bump PRs fail plan in consumer CI until migrated] → expected and desired: the failing plan is the migration reminder.

## Migration Plan

- Breaking minor release under 0.x semver (`feat(typesense)!:`), CHANGELOG with old → new field table and a full before/after app example.
- Consumer edit per app: add `namespace` at app level, delete it from up to four blocks, rename/retype the listed timing fields with identical values.
- Verification for a migrated consumer: `terraform plan` shows zero changes.
- Rollback: pin the previous ref and restore the old configuration shape; no state impact in either direction.

## Open Questions

None.
