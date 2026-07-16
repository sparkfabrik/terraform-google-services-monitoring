## Purpose

Response-content assertions on uptime checks created by the `http_monitoring` submodule, surfaced to Typesense apps via `uptime_check.content_match`. Lets a `/readyz` check assert the health payload (e.g. `"cluster_status":"OK"`) so quorum loss and split-brain conditions are detected end to end even when the endpoint keeps answering HTTP 200.

## Requirements

### Requirement: Content matchers on uptime checks

The `http_monitoring` submodule SHALL accept a `content_matchers` input (list of objects with `content` and optional `matcher`, default `"CONTAINS_STRING"`, empty list by default) and render one `content_matchers` block per entry on the `google_monitoring_uptime_check_config` resource.

#### Scenario: No matchers configured

- **WHEN** a consumer omits `content_matchers`
- **THEN** the uptime check resource has no `content_matchers` block and existing consumers see no plan diff

#### Scenario: Matcher configured

- **WHEN** a consumer passes `content_matchers = [{ content = "\"status\":\"OK\"" }]`
- **THEN** the uptime check fails whenever the response body does not contain `"status":"OK"`, even if the HTTP status is accepted

### Requirement: Content match on Typesense uptime checks

The Typesense `uptime_check` object SHALL accept an optional `content_match` string. When set, the module SHALL pass it to the `http_monitoring` submodule as a single `CONTAINS_STRING` content matcher; when unset, no matcher is passed.

#### Scenario: Typesense health content assertion

- **WHEN** an app sets `uptime_check = { host = "search.example.com", content_match = "\"cluster_status\":\"OK\"" }`
- **THEN** the uptime check alerts when the health endpoint responds 200 with a degraded cluster status payload

#### Scenario: Backward compatibility

- **WHEN** an app configures `uptime_check` without `content_match`
- **THEN** the resulting uptime check is identical to the previous release
