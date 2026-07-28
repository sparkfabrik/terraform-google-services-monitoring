# Design: Typesense log_check exclude patterns

## Context

`google_monitoring_alert_policy.typesense_logmatch_alert` (typesense.tf) builds a `condition_matched_log` filter from a heredoc: resource type, project, cluster, namespace, container name, and `severity>=<min_severity>`. Any matching entry fires the alert (rate-limited by `logmatch_notification_rate_limit_seconds`). Typesense on GKE emits structured logs where the message lives in `jsonPayload.message`; depending on the logging agent configuration a plain `textPayload` is also possible.

Raft recovery after a node preemption or pod reschedule emits transient ERROR entries (peer catch-up, write-lag drain) that self-resolve within minutes but page operators on every occurrence.

## Goals / Non-Goals

**Goals:**

- Let consumers suppress alert notifications for known-transient log messages, per app.
- Preserve the exact current filter when the option is unset (no plan diff for existing consumers).
- Fail at plan time on patterns that would corrupt the generated filter.

**Non-Goals:**

- Filtering the dashboard error-log counter metric (`google_logging_metric.typesense_error_logs`): the dashboard keeps the full error rate so excluded noise stays visible.
- Touching `flood_check`: a sustained storm of excluded messages still trips the flood alert.
- Regex support: substring exclusion covers the known use cases; regex can be added later without breaking the list-of-strings API.

## Decisions

- **Substring match with the `:` operator, not regex (`=~`).** Cloud Logging's `field:"value"` performs a case-insensitive substring match with no metacharacter surprises. Regex would force consumers to escape raft messages like `queued writes > healthy write lag of 500` and invites accidental over-matching.
- **Match both `jsonPayload.message` and `textPayload`.** One exclusion clause per pattern: `(jsonPayload.message:"<p>" OR textPayload:"<p>")`. Covers structured and plain container logs without asking the consumer which agent format is active.
- **Filter construction.** When `exclude_patterns` is non-empty, append one line to the existing heredoc: `AND NOT (<clause 1> OR <clause 2> ...)`. When empty, append nothing — the rendered filter is byte-identical to today's, so no state churn on upgrade.
- **Plan-time validation instead of escaping.** A variable `validation` block rejects patterns that are empty or contain a double quote (`"`). Escaping quotes via `replace()` was considered and dropped: silent rewriting hides intent, and no realistic log-exclusion pattern needs a literal quote. This follows the precedent set by the `notification_prompts` plan-time validation (0.20.1).
- **Option lives on `log_check` only.** The exclusion is a property of the log-match alert, not of the app; other checks derive nothing from it.

## Risks / Trade-offs

- [Overly broad pattern silences a real failure] → Documentation prescribes narrow, distinctive substrings; the dashboard error-log chart still shows all entries; `flood_check` remains as a volume backstop.
- [Filter length limits] → Cloud Logging filters cap at 20,000 characters; even dozens of patterns stay far below it. No guard needed.
- [Case-insensitive matching may exclude more than intended] → Inherent to the `:` operator; documented in the variable description.

## Migration Plan

Additive, backward-compatible. Consumers upgrade the module ref and optionally set `exclude_patterns`. Rollback = remove the option or pin the previous ref; the filter reverts to the unfiltered form in place (in-place alert policy update, no recreation).

## Open Questions

None.
