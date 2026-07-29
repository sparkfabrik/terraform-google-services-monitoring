# Proposal: typesense-logcheck-transient-errors-toggle

## Why

Typesense clusters running on spot/preemptible node pools emit the same transient raft-recovery log lines after every node preemption ("Peer refresh failed", "> healthy write lag of", "> healthy read lag of"). Today every consumer project must copy the same three-entry `log_check.exclude_patterns` list to keep the log alert quiet; the list is duplicated across many projects and drifts when the curated set changes.

## What Changes

- Add a new optional boolean attribute `log_check.exclude_transient_errors` (default `false`) to the `typesense` variable.
- When `true`, the module appends a curated, module-maintained preset of three exclusion patterns to the user-provided `log_check.exclude_patterns` list, deduplicated, when building the logmatch alert filter.
- The preset lives as a module constant (local) in `typesense.tf`; it is not exposed as a variable.
- Exclusion continues to apply to the logmatch alert policy only. The flood-check log metric and the dashboard error-log metric keep counting excluded lines.
- When the combined pattern list is empty, the rendered filter stays byte-identical to the current form (no state churn for existing consumers).
- `examples/main.tf`, the generated README docs, and the CHANGELOG are updated. No `UPGRADING.md` entry (additive, default-off).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `typesense-log-alert`: the "Log alert exclusion patterns" requirement gains the transient-errors preset toggle: preset content, append-and-deduplicate semantics, default-off behavior, and non-interaction with flood/dashboard resources.

## Impact

- `variables.tf`: new `optional(bool, false)` attribute on the `log_check` object; variable description extended.
- `typesense.tf`: new local holding the preset; `typesense_logmatch_exclusions` builds the clause from the combined (user + preset) list.
- `examples/main.tf`: demonstrate the toggle.
- `README.md`: regenerated terraform-docs block (`make generate-docs`).
- `CHANGELOG.md`: one bullet under `## [Unreleased]` / `### Added`.
- No provider, dependency, or state-shape changes. Issue ref: platform/#4649.
