# Tasks: typesense-logcheck-transient-errors-toggle

## 1. Variable schema

- [ ] 1.1 Add `exclude_transient_errors = optional(bool, false)` to the `log_check` object in `variables.tf`, after `exclude_patterns`.
- [ ] 1.2 Extend the `typesense` variable `description` (single-line string in `variables.tf`) with a sentence documenting the toggle and the three preset patterns.

## 2. Filter construction

- [ ] 2.1 Add a local constant in `typesense.tf` (near the other typesense log-check locals) holding the preset list: `"Peer refresh failed"`, `"> healthy write lag of"`, `"> healthy read lag of"`.
- [ ] 2.2 Update `local.typesense_logmatch_exclusions` to build the clause from the effective list: `distinct(concat(lc.exclude_patterns, lc.exclude_transient_errors ? <preset> : []))`, user patterns first. Keep the existing shape: empty effective list renders `""`, non-empty renders the `format("\nAND NOT (%s)", ...)` clause with the leading `\n` in the local, not the heredoc.
- [ ] 2.3 Confirm the flood-check metric (`typesense.tf`) and the dashboard error-log metric (`typesense_dashboard.tf`) are untouched by the change.

## 3. Examples and docs

- [ ] 3.1 Update `examples/main.tf`: set `exclude_transient_errors = true` on the existing `log_check` block (or the second app) with a short comment; adjust the existing exclude_patterns comment if needed.
- [ ] 3.2 Run `make generate-docs` to regenerate the terraform-docs block in `README.md`.
- [ ] 3.3 Add a CHANGELOG bullet under `## [Unreleased]` / `### Added` stating the new toggle. No `UPGRADING.md` entry (additive, default-off).

## 4. Verification

- [ ] 4.1 Run `make lint` (TFLint against `examples/test.tfvars`); it must pass.
- [ ] 4.2 Run `make tfsec`; it must pass.
- [ ] 4.3 Verify byte-identical rendering when the toggle is off: inspect the `typesense_logmatch_exclusions` expression to confirm `exclude_transient_errors = false` (or unset) with empty `exclude_patterns` yields `""` and with non-empty user patterns yields the same clause as before the change.
- [ ] 4.4 Verify the toggle path: with `exclude_transient_errors = true` and no user patterns the clause contains all three preset patterns in order; with an overlapping user pattern the duplicate appears once (deduplicated, first occurrence preserved).
