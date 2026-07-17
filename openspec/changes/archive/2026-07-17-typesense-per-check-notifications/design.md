# Design: typesense-per-check-notifications

## Context

Typesense notification routing resolves once per module instance: `typesense_notification_channels = notification_enabled ? (service override or root list) : []`, and every policy of every app references that single local. The five check blocks have no say. This change moves resolution to per-app-per-check granularity while keeping the service level as the inherited default.

## Goals / Non-Goals

**Goals**

- Silent alerts: a check whose policies open incidents but notify no channel.
- Per-check channel override: a different or narrower list than the service default.
- Inheritance by default: unset fields reproduce today's routing exactly; zero plan diff on bump.

**Non-Goals**

- Per-threshold-entry routing inside `workload_check` families (block granularity is the unit).
- Rolling the pattern to other services (kyverno, cloud_sql, ...) — documented as the reference pattern, applied elsewhere in later changes.
- Changing the service-level fields or the root `notification_channels` fallback.

## Decisions

1. **Tri-state `optional(bool, null)` for the toggle.** `null` must mean "inherit", which a boolean with a concrete default cannot express. Same reasoning for `optional(list(string), null)` on channels: `null` inherits, a non-null list is authoritative as-is.
2. **Block-explicit wins in both directions** (`effective_enabled = coalesce(block, service)`): a block `true` notifies even when the service level is disabled. Alternative (AND semantics: service `false` silences everything regardless of blocks) rejected: it makes the block field dead weight exactly when an operator wants one critical check to keep paging while muting the service, and the asymmetry (block can silence but not enable) is harder to document than plain "the most specific setting wins".
3. **Empty override list `[]` is legal and means "no channels".** It is not distinguished from `notification_enabled = false` by outcome, only by intent; no validation forbids it. Rejected alternative (validate `length > 0`): would force consumers to switch fields to express silence when they template channel lists that can legitimately be empty.
4. **Resolution in one per-app-per-check local map**, keyed like the existing check locals, computed as `effective_channels`. Policies swap `local.typesense_notification_channels` for their check's entry. The uptime path passes the resolved list into `module.typesense_uptime_checks` via the existing `alert_notification_channels` input — the submodule stays untouched.
5. **`notification_prompts` stays where it is** (per-check option where it already exists). Prompts govern notification content, not routing; mixing them into this change would widen the diff for no design gain.

## Risks / Trade-offs

- [Operator sets block `notification_channels` but service `notification_enabled = false` and expects notifications] → resolution is enabled-first: channels only apply when the effective toggle is true; documented in the variable description with the resolution order.
- [Silent checks can be forgotten and never page] → intended behavior; display names are unchanged and incidents still open in the console, so silent alerts remain visible where operators look.
- [Divergence risk: five blocks each carrying the pair invites copy-paste drift in the module code] → single resolution local shared by all five, one code path to review.

## Migration Plan

- Additive minor release. No consumer action; both fields default to `null` and the resolved routing is bit-identical to today's.
- Adoption: set the fields on the checks that need them; first plan shows only `notification_channels` updates on the touched policies.
- Rollback: remove the fields or pin the previous ref; policies return to service-level routing as an in-place update.

## Open Questions

None.
