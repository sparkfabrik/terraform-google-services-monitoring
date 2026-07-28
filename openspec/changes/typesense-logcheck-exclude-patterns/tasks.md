# Tasks: Typesense log_check exclude patterns

## 1. Variable schema

- [ ] 1.1 Add `exclude_patterns = optional(list(string), [])` to the `log_check` object in `variables.tf`, with the substring/case-insensitivity semantics documented in the `typesense` variable description.
- [ ] 1.2 Add a plan-time `validation` block rejecting any pattern that is an empty string or contains `"`, with an error message naming the offending app (follow the `notification_prompts` validation pattern).

## 2. Filter construction

- [ ] 2.1 In `typesense.tf`, build the exclusion clause for `google_monitoring_alert_policy.typesense_logmatch_alert`: for each pattern emit `jsonPayload.message:"<p>" OR textPayload:"<p>"`, join with ` OR `, wrap as `AND NOT (...)`.
- [ ] 2.2 Append the clause to the `condition_matched_log` filter only when `exclude_patterns` is non-empty; the empty-list rendering must be byte-identical to the current filter.
- [ ] 2.3 Confirm `flood_check` filter and `google_logging_metric.typesense_error_logs` (typesense_dashboard.tf) are not touched.

## 3. Example and docs

- [ ] 3.1 Extend `examples/main.tf` with `exclude_patterns` on one app's `log_check`.
- [ ] 3.2 Regenerate `README.md` terraform-docs block (`make generate-docs`).
- [ ] 3.3 Add CHANGELOG entry under `## [Unreleased]` / `### Added`.

## 4. QA

- [ ] 4.1 `make lint` passes.
- [ ] 4.2 `make tfsec` passes.
- [ ] 4.3 Verify rendered filter via plan against the example: with patterns set, filter contains the single `AND NOT (...)` clause; without, filter is unchanged.
