# Delta: typesense-log-alert

## ADDED Requirements

### Requirement: Transient error exclusion preset

The `log_check` object SHALL accept an `exclude_transient_errors` field (bool, default: `false`). When `true`, the module SHALL append a module-maintained preset of exclusion patterns to the user-provided `exclude_patterns` when building the effective exclusion list for the log-match alert filter. The preset SHALL be exactly, in order: `Peer refresh failed`, `> healthy write lag of`, `> healthy read lag of`. The preset SHALL be defined as a module constant, not configurable by consumers. The effective list SHALL be the user patterns followed by the preset patterns, deduplicated preserving first occurrence. When `false`, the effective list SHALL be the user patterns only and the rendered filter SHALL be identical to the filter produced before this field existed.

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

#### Scenario: Preset does not affect other log-based resources

- **WHEN** an app has `exclude_transient_errors = true` together with `flood_check` and the dashboard error-log counter metric
- **THEN** the flood check filter and the `google_logging_metric` filters remain unfiltered by the preset

## MODIFIED Requirements

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
