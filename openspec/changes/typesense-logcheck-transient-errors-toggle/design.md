# Design: typesense-logcheck-transient-errors-toggle

## Context

The `exclude_patterns` mechanism shipped in the `typesense-logcheck-exclude-patterns` change (archived 2026-07-28). `typesense.tf` builds an `AND NOT (...)` clause in `local.typesense_logmatch_exclusions` from `log_check.exclude_patterns` and appends it to the logmatch alert filter only. Patterns are interpolated verbatim (substring `:` operator on `jsonPayload.message` and `textPayload`); safety comes from a plan-time validation in `variables.tf` that rejects empty patterns and embedded `"`. An empty list renders the empty string, keeping the filter byte-identical to the pre-feature form.

Consumers running Typesense on spot node pools all need the same three exclusions for transient raft-recovery noise. The curated list currently lives in each consumer's configuration.

## Goals / Non-Goals

**Goals:**

- One boolean flag that applies the curated spot-noise preset without consumers copying pattern strings.
- Preset maintained in exactly one place (this module), so future curation reaches all consumers on module upgrade.
- Zero plan diff for consumers that do not set the flag.

**Non-Goals:**

- Filtering the flood-check metric or dashboard error-log metric (unchanged from the parent feature).
- Exposing the preset as a configurable variable or output.
- Regex exclusion support.
- Presets for other services or other noise families (the mechanism stays typesense/log_check-specific until a second use case appears).

## Decisions

1. **Boolean toggle over a preset-as-default list.** The Kyverno precedent (`service_errors_check.noise_exclusions`) ships its curated list as the variable default, opt-out by override. Chosen against here: changing the `exclude_patterns` default would alter alert behavior for every existing consumer on upgrade, and overriding the list to opt out also discards the user's own patterns. A default-false boolean is strictly additive. Decided with the user.

2. **Name `exclude_transient_errors`, not spot-node wording.** User decision: the attribute name must not couple to the spot-node deployment detail. The description documents what the preset covers.

3. **Preset as a module constant in `typesense.tf` locals.** Not a variable: consumers must not edit it (that is what `exclude_patterns` is for), and a variable default would be overridable, silently forking the curated list. The preset is:
   - `Peer refresh failed`
   - `> healthy write lag of`
   - `> healthy read lag of`

   All three satisfy the same invariant the plan-time validation enforces on user patterns (non-empty, no `"`), so verbatim interpolation stays safe. No new injection surface: the preset is not user-controlled.

4. **Append after user patterns, deduplicated with `distinct()`.** User patterns first preserves the reader's mental model (their config renders first in the filter). `distinct()` keeps the clause clean when a consumer migrating from the manual list forgets to drop an entry that the preset now covers; duplicates would be harmless to Cloud Logging but would churn the filter string and confuse diff review.

5. **Combine in `local.typesense_logmatch_exclusions`, reusing the existing empty-check shape.** The existing `length(...) == 0 ? "" : format(...)` expression switches to the combined list. `exclude_transient_errors = true` with an empty user list must still render the clause (combined list is non-empty); both off/empty must render `""` byte-identical to today.

## Risks / Trade-offs

- [Preset curation changes alert behavior on module upgrade] → Deliberate: that is the feature's purpose. Any future preset edit gets its own CHANGELOG bullet so consumers see it in release notes.
- [A preset pattern could over-match unrelated log lines] → The three substrings are specific to Typesense raft messages; same risk already accepted for the manual list in the parent change.
- [New pattern for the module (boolean expanding to config)] → Documented here and in the spec delta so future presets follow the same shape instead of inventing another one.

## Migration Plan

Additive, default-off. Consumers currently carrying the manual three-pattern list can set `exclude_transient_errors = true` and delete the entries; `distinct()` makes the intermediate state (both present) harmless. No `UPGRADING.md` entry.
