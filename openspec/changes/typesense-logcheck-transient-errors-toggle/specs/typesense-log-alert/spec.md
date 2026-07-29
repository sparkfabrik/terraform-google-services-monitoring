# Delta: typesense-log-alert

## ADDED Requirements

### Requirement: Transient error exclusion preset

The `log_check` object SHALL accept an `exclude_transient_errors` field (bool, default: `false`). When `true`, the module SHALL append a module-maintained preset of exclusion patterns to the user-provided `exclude_patterns` when building the effective exclusion list for the log-match alert filter. The preset SHALL be exactly, in order: `Peer refresh failed`, `> healthy write lag of`, `> healthy read lag of`. The preset SHALL be defined as a module constant, not configurable by consumers, and the module SHALL assert at plan time, for any configuration that renders the log-match alert, that every preset entry satisfies the exclusion pattern validation invariant (non-empty after trimming; no double quote, backslash, or control character). The effective list SHALL be the user patterns followed by the preset patterns, deduplicated byte-exact preserving first occurrence. When `false`, the effective list SHALL be the user patterns exactly as provided (no deduplication) and the rendered filter SHALL be identical to the filter produced before this field existed.

#### Scenario: Toggle enabled with no user patterns

- **WHEN** an app has `log_check = { exclude_transient_errors = true }` and no `exclude_patterns`
- **THEN** the log filter contains `AND NOT (jsonPayload.message:"Peer refresh failed" OR textPayload:"Peer refresh failed" OR jsonPayload.message:"> healthy write lag of" OR textPayload:"> healthy write lag of" OR jsonPayload.message:"> healthy read lag of" OR textPayload:"> healthy read lag of")`

#### Scenario: Toggle enabled with user patterns

- **WHEN** an app has `log_check = { exclude_patterns = ["custom noise"], exclude_transient_errors = true }`
- **THEN** the effective exclusion list is `["custom noise", "Peer refresh failed", "> healthy write lag of", "> healthy read lag of"]` and the filter clause renders the user pattern first

#### Scenario: Overlap deduplicated

- **WHEN** an app has `log_check = { exclude_patterns = ["Peer refresh failed"], exclude_transient_errors = true }`
- **THEN** the effective exclusion list contains `Peer refresh failed` exactly once, followed by the two remaining preset patterns

#### Scenario: Toggle disabled preserves current behavior

- **WHEN** `exclude_transient_errors` is not specified or is `false`
- **THEN** the rendered filter is byte-identical to the filter produced without the field, for any value of `exclude_patterns`

#### Scenario: Toggle disabled keeps duplicate user patterns

- **WHEN** an app has `log_check = { exclude_patterns = ["x", "x"] }` and `exclude_transient_errors` unset or `false`
- **THEN** the rendered clause repeats the pattern verbatim, byte-identical to the pre-change rendering

#### Scenario: Preset entry violating the pattern invariant

- **WHEN** the module-maintained preset contains an entry that is empty after trimming or contains `"`, `\`, or a control character, and at least one app has an enabled `log_check`
- **THEN** `terraform plan` fails with a message stating the preset invariant and identifying it as a module defect

#### Scenario: Preset does not affect other log-based resources

- **WHEN** an app has `exclude_transient_errors = true` together with `flood_check` and the dashboard error-log counter metric
- **THEN** the flood check filter and the `google_logging_metric` filters remain unfiltered by the preset

## MODIFIED Requirements

### Requirement: Exclusion pattern validation

The `typesense` variable validation SHALL reject, at plan time, any `log_check.exclude_patterns` entry that is `null`, empty after trimming whitespace, or contains a double-quote character (`"`), a backslash (`\`), or any control character (newline, carriage return, tab, NUL, and the rest of the C0/C1 classes), with an error message stating the constraint and pointing at `log_check.exclude_patterns`. A `null` entry SHALL surface the validation error message, not an internal function error. The message is a constant string (dynamic `error_message` expressions require Terraform >= 1.9 while the module supports >= 1.5), following the `notification_prompts` validation precedent.

#### Scenario: Pattern with embedded double quote

- **WHEN** an app configures `log_check = { exclude_patterns = ["bad\"pattern"] }`
- **THEN** `terraform plan` fails with a validation error stating the constraint

#### Scenario: Empty pattern

- **WHEN** an app configures `log_check = { exclude_patterns = [""] }`
- **THEN** `terraform plan` fails with a validation error stating the constraint

#### Scenario: Whitespace-only pattern

- **WHEN** an app configures `log_check = { exclude_patterns = ["  "] }`
- **THEN** `terraform plan` fails with a validation error stating the constraint

#### Scenario: Pattern with trailing backslash

- **WHEN** an app configures `log_check = { exclude_patterns = ["trailing\\"] }`
- **THEN** `terraform plan` fails with a validation error stating the constraint (a backslash escapes the closing quote in the Cloud Logging filter grammar)

#### Scenario: Pattern with control character

- **WHEN** an app configures `log_check = { exclude_patterns = ["a\rb"] }` (or any other raw control character such as NUL or form feed)
- **THEN** `terraform plan` fails with a validation error stating the constraint

#### Scenario: Null pattern entry

- **WHEN** an app configures `log_check = { exclude_patterns = ["a", null] }`
- **THEN** `terraform plan` fails with the validation error message, not an internal function error

### Requirement: Log alert exclusion patterns

The `log_check` object SHALL accept an `exclude_patterns` field (list of strings, default: `[]`). The effective exclusion list SHALL be `exclude_patterns` optionally extended by the transient-errors preset (see "Transient error exclusion preset"). When the effective list is non-empty, the log-match alert filter SHALL exclude entries whose message contains any of the patterns, by appending a single clause of the form `AND NOT (jsonPayload.message:"<p1>" OR textPayload:"<p1>" OR jsonPayload.message:"<p2>" OR textPayload:"<p2>" ...)`. Matching SHALL use the Cloud Logging substring operator (`:`), which is case-insensitive. When the effective list is empty, the rendered filter SHALL be identical to the filter produced without the field.

#### Scenario: Exclusion patterns configured

- **WHEN** an app has `namespace = "ts-ns"` and `log_check = { exclude_patterns = ["Peer refresh failed", "> healthy write lag of"] }` configured
- **THEN** the log filter contains `AND NOT (jsonPayload.message:"Peer refresh failed" OR textPayload:"Peer refresh failed" OR jsonPayload.message:"> healthy write lag of" OR textPayload:"> healthy write lag of")`

#### Scenario: Default empty list preserves filter

- **WHEN** `exclude_patterns` is not specified or is `[]` and `exclude_transient_errors` is not `true`
- **THEN** the rendered log filter contains no `NOT` clause and is byte-identical to the filter produced before this field existed

#### Scenario: Exclusions do not affect other log-based resources

- **WHEN** an app has `exclude_patterns` configured together with `flood_check` and the dashboard error-log counter metric
- **THEN** the flood check filter and the `google_logging_metric` filter remain unfiltered by the patterns
