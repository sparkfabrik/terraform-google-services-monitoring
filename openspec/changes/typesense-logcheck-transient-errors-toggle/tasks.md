# Tasks: typesense-logcheck-transient-errors-toggle

## 1. Variable schema

- [x] 1.1 Add `exclude_transient_errors = optional(bool, false)` to the `log_check` object in `variables.tf`, after `exclude_patterns`.
- [x] 1.2 Extend the `typesense` variable `description` (single-line string in `variables.tf`) with a sentence documenting the toggle and the three preset patterns.

## 2. Filter construction

- [x] 2.1 Add a local constant in `typesense.tf` (near the other typesense log-check locals) holding the preset list: `"Peer refresh failed"`, `"> healthy write lag of"`, `"> healthy read lag of"`.
- [x] 2.2 Update `local.typesense_logmatch_exclusions` to build the clause from the effective list: `distinct(concat(lc.exclude_patterns, lc.exclude_transient_errors ? <preset> : []))`, user patterns first. Keep the existing shape: empty effective list renders `""`, non-empty renders the `format("\nAND NOT (%s)", ...)` clause with the leading `\n` in the local, not the heredoc.
- [x] 2.3 Confirm the flood-check metric (`typesense.tf`) and the dashboard error-log metric (`typesense_dashboard.tf`) are untouched by the change.

## 3. Examples and docs

- [x] 3.1 Update `examples/main.tf`: set `exclude_transient_errors = true` on the existing `log_check` block (or the second app) with a short comment; adjust the existing exclude_patterns comment if needed.
- [x] 3.2 Run `make generate-docs` to regenerate the terraform-docs block in `README.md`.
- [x] 3.3 Add a CHANGELOG bullet under `## [Unreleased]` / `### Added` stating the new toggle. No `UPGRADING.md` entry (additive, default-off).

## 4. Verification

- [x] 4.1 Run `make lint` (TFLint against `examples/test.tfvars`); it must pass.
- [x] 4.2 Run `make tfsec`; it must pass.
- [x] 4.3 Verify byte-identical rendering when the toggle is off: inspect the `typesense_logmatch_exclusions` expression to confirm `exclude_transient_errors = false` (or unset) with empty `exclude_patterns` yields `""` and with non-empty user patterns yields the same clause as before the change.
- [x] 4.4 Verify the toggle path: with `exclude_transient_errors = true` and no user patterns the clause contains all three preset patterns in order; with an overlapping user pattern the duplicate appears once (deduplicated, first occurrence preserved).

## 5. Review fixes

- [x] 5.1 Gate deduplication on the toggle in `typesense.tf`: effective list is `lc.exclude_transient_errors ? distinct(concat(lc.exclude_patterns, local.typesense_transient_error_patterns)) : lc.exclude_patterns`. Toggle off must render duplicate user patterns verbatim (byte-identical to pre-change).
- [x] 5.2 Rename the rendered-clause local `typesense_logmatch_exclusions` to `typesense_logmatch_exclusion_clauses` and update its single reference in the logmatch alert resource.
- [x] 5.3 Split the locals comment: the effective-list sentence stays on `typesense_logmatch_exclusion_patterns`; the rendering semantics (jsonPayload/textPayload, case-insensitive `:`, empty list renders `""` to keep the filter byte-identical) move onto `typesense_logmatch_exclusion_clauses`. Add one line naming kyverno's `noise_exclusions` as the other preset shape and why this one is opt-in.
- [x] 5.4 Add a plan-time `precondition` (on the logmatch alert resource lifecycle) asserting every preset entry is non-empty after trimming and contains no `"`, `\`, or newline, with a constant error message. Shorten the preset comment to point at it.
- [x] 5.5 Strengthen the `exclude_patterns` validation in `variables.tf`: reject patterns empty after trimming or containing `"`, `\`, or a newline. Constant error message.
- [x] 5.6 Fix `examples/main.tf`: reword the toggle comment (it must say the preset log lines are dropped from the alert, not that the preset is suppressed); replace the `"Bad or missing auth key header"` example pattern with a benign noise line (e.g. a client-disconnect message); drop the verbatim preset enumeration from the example comment and point at the `typesense` variable description instead.
- [x] 5.7 Extend the `typesense` variable description: note the toggle assumes a health-signal check (uptime_check or workload_check) is configured for the app, since the lag patterns also match chronic degradation. Keep the preset enumeration in the description (consumer contract).
- [x] 5.8 Run `make generate-docs`, `make lint`, tfsec; re-verify rendering including the new duplicate-user-pattern case (toggle off, `["x","x"]` renders the duplicate clause verbatim).
- [x] 5.9 Add a CHANGELOG `### Fixed` bullet for the strengthened `exclude_patterns` validation (backslash, whitespace-only, newline now rejected at plan time).
