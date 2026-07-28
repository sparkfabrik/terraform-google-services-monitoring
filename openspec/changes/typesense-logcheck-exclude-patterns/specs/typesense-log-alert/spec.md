# Delta: typesense-log-alert

## ADDED Requirements

### Requirement: Log alert exclusion patterns

The `log_check` object SHALL accept an `exclude_patterns` field (list of strings, default: `[]`). When the list is non-empty, the log-match alert filter SHALL exclude entries whose message contains any of the patterns, by appending a single clause of the form `AND NOT (jsonPayload.message:"<p1>" OR textPayload:"<p1>" OR jsonPayload.message:"<p2>" OR textPayload:"<p2>" ...)`. Matching SHALL use the Cloud Logging substring operator (`:`), which is case-insensitive. When the list is empty, the rendered filter SHALL be identical to the filter produced without the field.

#### Scenario: Exclusion patterns configured

- **WHEN** an app has `namespace = "ts-ns"` and `log_check = { exclude_patterns = ["Peer refresh failed", "> healthy write lag of"] }` configured
- **THEN** the log filter contains `AND NOT (jsonPayload.message:"Peer refresh failed" OR textPayload:"Peer refresh failed" OR jsonPayload.message:"> healthy write lag of" OR textPayload:"> healthy write lag of")`

#### Scenario: Default empty list preserves filter

- **WHEN** `exclude_patterns` is not specified or is `[]`
- **THEN** the rendered log filter contains no `NOT` clause and is byte-identical to the filter produced before this field existed

#### Scenario: Exclusions do not affect other log-based resources

- **WHEN** an app has `exclude_patterns` configured together with `flood_check` and the dashboard error-log counter metric
- **THEN** the flood check filter and the `google_logging_metric` filter remain unfiltered by the patterns

### Requirement: Exclusion pattern validation

The `typesense` variable validation SHALL reject, at plan time, any `log_check.exclude_patterns` entry that is an empty string or contains a double-quote character (`"`), with an error message identifying the offending app.

#### Scenario: Pattern with embedded double quote

- **WHEN** an app configures `log_check = { exclude_patterns = ["bad\"pattern"] }`
- **THEN** `terraform plan` fails with a validation error naming the app and the double-quote constraint

#### Scenario: Empty pattern

- **WHEN** an app configures `log_check = { exclude_patterns = [""] }`
- **THEN** `terraform plan` fails with a validation error naming the app
