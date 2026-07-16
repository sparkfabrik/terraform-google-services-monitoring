# Proposal: typesense-workload-check

## Why

The Typesense monitoring coverage in this module is black-box only (uptime, pod restarts, logs): nothing watches the vitals that actually kill a self-hosted Typesense cluster, namely memory saturation (in-memory store, OOMKill removes a raft member), PVC disk growth (raft log grows while a peer is down, full disk rejects writes), and loss of replicas below raft quorum. All required signals are already free GKE system metrics (`kubernetes.io/*`), so this coverage costs nothing to add. Tracking: refs platform/#4649, phase 1. Ships as the next minor release.

## What Changes

- New optional `workload_check` block per Typesense app creating alert policies for:
  - container memory limit utilization (defaults WARNING 85% / CRITICAL 95%, grounded in the Typesense production guide),
  - container CPU limit utilization (default WARNING 90%),
  - PVC volume utilization (defaults WARNING 75% / CRITICAL 85%),
  - replica availability via PromQL on `kubernetes_io:container_uptime` (konnectivity pattern): WARNING when ready pods drop below `expected_replicas`, CRITICAL below raft quorum `floor(n/2)+1`.
- New `expected_replicas` input (per app, inside `workload_check`) so the same module serves 1-, 3- and 5-replica topologies; the WARNING policy is skipped when it would duplicate the CRITICAL one (single replica).
- New optional `content_matchers` input on the `http_monitoring` submodule, plus a `content_match` convenience field on the Typesense `uptime_check`, so the `/readyz` check can assert `"cluster_status":"OK"` (black-box quorum and split-brain detection).
- New optional per-app `cluster_name` override falling back to the service-level `typesense.cluster_name`, honored by workload, container, log and flood checks (supports multiple GKE clusters in one GCP project from a single module instance).
- New optional `workload_check.controller_name` selector for the edge case of multiple TypesenseClusters sharing a namespace.
- New optional `typesense.alert_documentation` applied to every Typesense alert policy (kyverno-style runbook text).
- Non-breaking: every new field is `optional(...)` with a `null`/passive default; a consumer upgrading without config changes gets zero new resources and zero plan diff.

## Capabilities

### New Capabilities

- `typesense-workload-vitals`: per-app workload saturation and availability alerting (memory, CPU, PVC, replica count vs expected and vs quorum) driven by the `workload_check` block.
- `http-uptime-content-matchers`: response-content assertions on uptime checks created by the `http_monitoring` submodule, surfaced to Typesense apps via `uptime_check.content_match`.

### Modified Capabilities

- `typesense-log-alert`: the GKE cluster targeted by log-based checks becomes resolvable per app (`apps[*].cluster_name` falling back to `typesense.cluster_name`), and alert policies gain the optional shared `alert_documentation` text.

## Impact

- `variables.tf`: `typesense` object grows `alert_documentation` and per-app `cluster_name`, `workload_check`; `uptime_check` grows `content_match`.
- `typesense.tf`: new locals and alert policy resources; existing locals resolve `cluster_name` per app.
- `modules/http_monitoring/`: new `content_matchers` variable and block on `google_monitoring_uptime_check_config`.
- `examples/main.tf`, `examples/test.tfvars`: exercise the new fields (TFLint runs against them).
- `README.md` (terraform-docs regeneration), `CHANGELOG.md` (entries under `[Unreleased]`, versioned at tag time), new `outputs.tf` entries for the new policies.
