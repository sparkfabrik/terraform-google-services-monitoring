# Design: fix-typesense-flood-rate-limit

## Context

`typesense_flood_alert` (typesense.tf) alerts with `condition_threshold` on a user-defined log-based metric. The Cloud Monitoring API only accepts `alert_strategy.notification_rate_limit` on `condition_matched_log` policies and returns a 400 otherwise, so the policy cannot be created. The constraint is already known in this codebase (comment on the Kyverno service file). The log severity alert (`condition_matched_log`) is unaffected and keeps its rate limit.

## Goals / Non-Goals

**Goals**

- `flood_check` applies successfully.
- No plan diff for consumers not using `flood_check`.
- No inert fields left in the variable interface.

**Non-Goals**

- Redesigning flood-alert notification throttling.

## Decisions

1. **Delete the `notification_rate_limit` block from the flood policy, keep `auto_close`.** The API offers no legal equivalent for metric alerts; notification frequency stays bounded by `alignment_period_seconds`, `duration_seconds` debounce and `auto_close_seconds`. Alternative (convert the flood alert to `condition_matched_log`) rejected: the check is rate-based by design and needs the counter metric.
2. **Remove `flood_check.notification_rate_limit` from the variable schema.** An inert deprecated field silently ignores user intent: a consumer setting it expects throttling and gets none. Removal turns that into an explicit plan-time type error (`An attribute named "notification_rate_limit" is not expected here`). The blast radius is effectively zero because the flood check has never applied successfully, so no working configuration sets the field. Alternative (keep the field, documented as deprecated and inert) rejected: it trades an honest failure for a silent no-op and leaves cleanup debt.

## Risks / Trade-offs

- [A consumer that set `notification_rate_limit` fails at plan time after the bump] → the type error names the attribute; the CHANGELOG Removed entry states the required action (delete the attribute). No consumer can have a working configuration with the field set, since the flood check never applied.

## Migration Plan

- Minor release (0.19.0; breaking interface change under 0.x semver). Consumers bump the ref; blocked applies converge (the flood policies get created). A consumer that set `notification_rate_limit` deletes the attribute. Rollback: pin the previous ref (restores the broken behavior for flood users, no state damage).

## Open Questions

None.
