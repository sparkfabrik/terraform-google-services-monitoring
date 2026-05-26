## 1. Variable Definition

- [x] 1.1 Add `log_check` optional object to `typesense.apps` in `variables.tf` with fields: `enabled`, `namespace`, `min_severity`, `logmatch_notification_rate_limit`, `auto_close_seconds`
- [x] 1.2 Update `cluster_name` validation to require it when any app has `log_check` configured (extend existing `container_check` validation condition)

## 2. Resource Implementation

- [x] 2.1 Add `typesense_log_checks` local in `typesense.tf` that filters to enabled log_check apps
- [x] 2.2 Add `google_monitoring_alert_policy.typesense_logmatch_alert` resource with `for_each = local.typesense_log_checks`, using `condition_matched_log` with severity filter, notification_rate_limit, and auto_close

## 3. Output

- [x] 3.1 Add `typesense_logmatch_alert_policy_names` output in `outputs.tf`

## 4. Example and Documentation

- [x] 4.1 Add `log_check` to the Typesense app in `examples/main.tf`
- [x] 4.2 Run `terraform fmt` and `terraform validate` to verify syntax

## 5. flood_check Variable Definition

- [x] 5.1 Add `flood_check` optional object to `typesense.apps` in `variables.tf` with fields: `enabled`, `namespace`, `threshold_entries_per_minute` (required), `alignment_period_seconds`, `duration_seconds`, `auto_close_seconds`, `notification_rate_limit`
- [x] 5.2 Update `cluster_name` validation to also require it when any app has `flood_check` configured

## 6. flood_check Resource Implementation

- [x] 6.1 Add `typesense_flood_checks` local in `typesense.tf` that filters to enabled flood_check apps
- [x] 6.2 Add `google_logging_metric.typesense_log_flood` resource with `for_each = local.typesense_flood_checks`, scoped to namespace + container_name="typesense"
- [x] 6.3 Add `google_monitoring_alert_policy.typesense_flood_alert` resource with `condition_threshold` on `ALIGN_RATE` of the log metric, firing when rate exceeds `threshold_entries_per_minute`

## 7. flood_check Output and Example

- [x] 7.1 Add `typesense_flood_alert_policy_names` output in `outputs.tf`
- [x] 7.2 Add `flood_check` to the Typesense app in `examples/main.tf` with all options explicit
- [x] 7.3 Run `terraform fmt` and `terraform validate` to verify syntax
