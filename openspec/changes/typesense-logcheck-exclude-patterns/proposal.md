# Proposal: Typesense log_check exclude patterns

## Why

The Typesense `log_check` alert fires on every log entry at or above `min_severity`, with no way to exclude known-transient messages. On clusters running Typesense on spot/preemptible node pools, every node preemption triggers a short raft recovery burst (`Peer refresh failed ... failed to catch up`, `N queued writes > healthy write lag of 500`) that pages operators daily even though the cluster self-heals within minutes. Consumers currently have to choose between alert fatigue and disabling the log alert entirely.

## What Changes

- Add an `exclude_patterns` option to the Typesense `log_check` block: a list of substrings, default `[]` (current behavior unchanged).
- Each pattern is excluded from the log-match alert filter: entries whose message contains any pattern do not trigger the alert.
- Patterns match against both `textPayload` and `jsonPayload.message`, covering plain-text and structured container logs.
- The dashboard error-log counter metric (`typesense_error_logs_*`) is intentionally NOT filtered: the dashboard keeps showing the full error rate, only alert notifications are suppressed.
- The flood check is unaffected: a sustained error storm still fires `flood_check` regardless of exclusions.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `typesense-log-alert`: the log-match alert filter requirement gains an optional exclusion clause built from `log_check.exclude_patterns`; default (empty list) preserves the existing filter byte-for-byte.

## Impact

- `typesense.tf`: `google_monitoring_alert_policy.typesense_logmatch_alert` filter construction.
- `variables.tf`: `typesense.apps.*.log_check` object gains `exclude_patterns = optional(list(string), [])`.
- `README.md`: regenerated terraform-docs block.
- `examples/`: canonical example extended to exercise the new option.
- No breaking changes: existing consumers get an identical filter when the option is unset.
