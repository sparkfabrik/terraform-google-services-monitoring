# Tasks: typesense-workload-check

## 1. Variables

- [x] 1.1 Add `alert_documentation = optional(string)` and per-app `cluster_name = optional(string)` to the `typesense` variable; add `content_match = optional(string)` to `uptime_check`.
- [x] 1.2 Add the `workload_check` optional object to `apps[*]`: `enabled` (default true), `namespace` (required), `expected_replicas` (required), `container_name` (default `"typesense"`), `controller_name` (optional), `volume_name` (default `"data"`), threshold lists `memory_utilization` / `cpu_utilization` / `volume_utilization` with the defaults from design decision 3, `replica_availability` object (`enabled` default true, `duration_seconds` default 300), `auto_close_seconds` (default 3600), `notification_prompts` (optional).
- [x] 1.3 Extend the `typesense` variable validations: `expected_replicas >= 1`, non-empty `workload_check.namespace`, and per-app resolvable cluster name for every app with any Kubernetes-based check (workload, container, log, flood), replacing the service-level-only check.

## 2. http_monitoring submodule

- [x] 2.1 Add `content_matchers` variable (list of `{ content, matcher }`, default `[]`) and render dynamic `content_matchers` blocks on `google_monitoring_uptime_check_config`.
- [x] 2.2 Regenerate the submodule README via terraform-docs if it carries a generated block. (No generated block in `modules/http_monitoring/README.md` — no-op; variables documented by hand there if needed.)

## 3. typesense.tf

- [x] 3.1 Add per-app locals resolving `cluster_name` (app override, service fallback) and rewire the existing container/log/flood filters to use the resolved value.
- [x] 3.2 Build flattened `for_each` maps for the three threshold families (key `<app>--<severity>--<threshold>`, cloud_sql pattern) and the replica policies.
- [x] 3.3 Implement memory, CPU and volume `google_monitoring_alert_policy` resources (`condition_threshold` on `kubernetes.io/container/memory/limit_utilization` with `memory_type="non-evictable"`, `container/cpu/limit_utilization`, `pod/volume/utilization` with `volume_name` filter), with optional `controller_name` constraint.
- [x] 3.4 Implement the replica availability policies (`condition_prometheus_query_language`, konnectivity pattern): CRITICAL below `floor(expected_replicas / 2) + 1`, WARNING below `expected_replicas` created only when `expected_replicas > quorum`.
- [x] 3.5 Pass `content_match` through to the `http_monitoring` submodule call as a single `CONTAINS_STRING` matcher.
- [x] 3.6 Render the optional `documentation` block from `typesense.alert_documentation` on every Typesense alert policy (new and pre-existing), null-safe so unset means no block.
- [x] 3.7 Apply the notification cascade, `auto_close_seconds` and `notification_prompts` to the new policies.

## 4. Outputs, examples, docs

- [x] 4.1 Add outputs for the new policy names keyed by app and family.
- [x] 4.2 Extend `examples/main.tf` and `examples/test.tfvars` with a `workload_check` app (including `content_match`) and a per-app `cluster_name` override so TFLint exercises every new field.
- [x] 4.3 Run `make generate-docs` to refresh the README terraform-docs block.
- [x] 4.4 Add CHANGELOG entries under `[Unreleased]` (Added: workload vitals alerts, content matchers, per-app cluster name, alert documentation).

## 5. Verification

- [x] 5.1 `make lint` and `make tfsec` pass.
- [ ] 5.2 No-diff check: plan a downstream stack pinned to the branch with unchanged 0.17-style config and confirm zero changes. (Local equivalent done: `terraform plan` JSON planned-values of an unchanged 0.17-style config are byte-identical between `main` and this branch. Real downstream confirmation still pending.)
- [ ] 5.3 Adoption check: enable `workload_check` on one app in a sandbox and confirm the expected policy set (2 memory + 1 CPU + 2 volume + 2 replica for a 3-replica app). (Local plan confirms exactly that policy set for a 3-replica app, plus WARNING-skip for a 1-replica app. Sandbox apply still pending.)

## 6. Change management

- [x] 6.1 Commit spec artifacts and implementation per the repo's OpenSpec workflow (spec-first PR, then implementation, or one PR if maintainers deem it trivial).
- [ ] 6.2 After merge: sync delta specs into `openspec/specs/` and archive the change to `openspec/changes/archive/YYYY-MM-DD-typesense-workload-check/`.
