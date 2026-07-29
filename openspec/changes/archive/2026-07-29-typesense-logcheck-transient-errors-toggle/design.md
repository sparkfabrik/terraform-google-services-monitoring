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

   All three satisfy the invariant the plan-time validation enforces on user patterns, so verbatim interpolation stays safe. The invariant is not left to a comment: a `precondition` on the log-match alert resource asserts it over the preset at plan time, so a future curation mistake fails loud instead of shipping a malformed filter. Variable validation cannot reference locals, so the assertion lives on the resource that interpolates the preset. As a consequence it is instance-scoped: it does not evaluate when no app has an enabled `log_check`, which is also the only configuration that consumes the preset. When it does evaluate, it fires for every log_check app, including toggle-off ones. Its error message is prefixed as a module defect, since a consumer tripping it has no configuration to change. No new injection surface: the preset is not user-controlled.

4. **Append after user patterns, deduplicated with `distinct()`, only when the toggle is on.** User patterns first preserves the reader's mental model (their config renders first in the filter). `distinct()` keeps the clause clean when a consumer migrating from the manual list forgets to drop an entry that the preset now covers. Dedup is byte-exact: a case-variant or whitespace-variant leftover is kept (Cloud Logging matching is case-insensitive, so the extra term is redundant but harmless). When the toggle is off, the user list is used verbatim, not wrapped in `distinct()`: deduping it would change the rendered filter for consumers carrying duplicate entries, violating the byte-identical guarantee.

5. **Two locals: effective pattern list, then rendered clause.** `typesense_logmatch_exclusion_patterns` holds the effective list per app (`exclude_transient_errors ? distinct(concat(user, preset)) : user`); `typesense_logmatch_exclusion_clauses` renders it with the existing `length(...) == 0 ? "" : format(...)` shape. The list is needed twice (emptiness test and join), so inlining would duplicate the expression. `exclude_transient_errors = true` with an empty user list still renders the clause (effective list is non-empty); toggle off with an empty list renders `""` byte-identical to today.

6. **Strengthened pattern validation.** The parent change's validation (non-empty, no `"`) does not actually make verbatim interpolation safe: a trailing backslash escapes the closing quote in the Cloud Logging filter grammar, a whitespace-only pattern silences every log line, and raw control characters (carriage return, NUL, form feed) land verbatim in the API payload and fail opaquely at apply. The validation now rejects patterns that are `null`, empty after trimming, or contain `"`, `\`, or any control character, with the `null` case guarded first so the constant error message surfaces instead of a `trimspace` function error. Constant error message (dynamic messages need Terraform >= 1.9; the module floor is 1.5). The same predicate guards the preset via the resource precondition; the two copies carry bidirectional cross-reference comments because Terraform 1.5 has no shared-predicate mechanism. Only configurations that already produced broken or degenerate filters are rejected, so this is a fix, not a breaking change.

## Risks / Trade-offs

- [Preset curation changes alert behavior on module upgrade] → Deliberate: that is the feature's purpose. Any future preset edit gets its own CHANGELOG bullet so consumers see it in release notes.
- [A preset pattern could over-match unrelated log lines] → The three substrings are specific to Typesense raft messages; same risk already accepted for the manual list in the parent change.
- [The lag patterns also match chronic raft degradation, so the toggle can silence a persistent failure] → The variable description instructs consumers to enable the toggle only for apps that keep a health signal covered by another check (`uptime_check` or `workload_check`). This assumption is deliberately unenforced: a consumer may hold health coverage outside this module, and a hard validation would block legitimate configurations.
- [New pattern for the module (boolean expanding to config)] → Documented here and in the spec delta so future presets follow the same shape instead of inventing another one.
- [Rendered filter length is unbounded and the toggle appends ~260 characters] → Accepted without a plan-time bound: realistic exclusion lists sit far below the Cloud Monitoring filter length limit, and a length validation would need a maintained constant for an API limit this module does not own. A consumer within reach of the limit fails at apply, as with the parent `exclude_patterns` change.

## Migration Plan

Additive, default-off. Consumers currently carrying the manual three-pattern list can set `exclude_transient_errors = true` and delete the entries; `distinct()` makes the intermediate state (both present) harmless. No `UPGRADING.md` entry.
