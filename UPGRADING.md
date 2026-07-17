# Upgrading

Migration notes for breaking changes, newest first. Each section explains how
to move a downstream stack from the previous release. The
[CHANGELOG](CHANGELOG.md) lists what changed; this file explains how to
migrate.

## 0.19.0

### Typesense: app-level `namespace` and uniform `_seconds` timing fields

Two schema cleanups of the `typesense` variable. Both are plan-time-only
breaks: a value-preserving migration produces a **zero-change plan** (the
affected fields feed only filter strings and display names, and no resource
addresses change).

#### 1. `namespace` moves to the app level

Declare `namespace` once per app, next to `cluster_name`, and delete it from
`container_check`, `log_check`, `flood_check` and `workload_check`.

An app that configures any of those Kubernetes-based checks without an
app-level `namespace` fails validation at plan time. Uptime-only apps need
no namespace.

#### 2. Duration-like fields become `_seconds` numbers

Rename the fields below and carry the values over verbatim (`"300s"` becomes
`300`). All other timing fields (`auto_close_seconds`, the `flood_check`
fields, `replica_availability.duration_seconds`) already followed this
convention and are unchanged.

| Old field                                                                     | New field                                                                             |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `container_check.pod_restart.alignment_period` (number)                       | `container_check.pod_restart.alignment_period_seconds` (number)                       |
| `container_check.pod_restart.duration` (number)                               | `container_check.pod_restart.duration_seconds` (number)                               |
| `workload_check.{memory,cpu,volume}_utilization[*].alignment_period` (string) | `workload_check.{memory,cpu,volume}_utilization[*].alignment_period_seconds` (number) |
| `workload_check.{memory,cpu,volume}_utilization[*].duration` (string)         | `workload_check.{memory,cpu,volume}_utilization[*].duration_seconds` (number)         |
| `log_check.logmatch_notification_rate_limit` (string)                         | `log_check.logmatch_notification_rate_limit_seconds` (number)                         |

#### Before and after

Identical values; the migration produces a zero-change plan.

```hcl
# Before
apps = {
  "search" = {
    container_check = {
      namespace = "typesense"
      pod_restart = {
        alignment_period = 60
        duration         = 180
      }
    }
    log_check = {
      namespace                        = "typesense"
      logmatch_notification_rate_limit = "300s"
    }
    flood_check = {
      namespace = "typesense"
    }
    workload_check = {
      namespace         = "typesense"
      expected_replicas = 3
      memory_utilization = [
        { severity = "CRITICAL", threshold = 0.95, alignment_period = "300s", duration = "300s" }
      ]
    }
  }
}

# After
apps = {
  "search" = {
    namespace = "typesense"
    container_check = {
      pod_restart = {
        alignment_period_seconds = 60
        duration_seconds         = 180
      }
    }
    log_check = {
      logmatch_notification_rate_limit_seconds = 300
    }
    flood_check = {}
    workload_check = {
      expected_replicas = 3
      memory_utilization = [
        { severity = "CRITICAL", threshold = 0.95, alignment_period_seconds = 300, duration_seconds = 300 }
      ]
    }
  }
}
```

#### Watch out: leftover legacy fields are silently ignored

Terraform's object conversion discards attributes that are no longer part of
the variable type, without an error. A leftover legacy field (for example
`alignment_period = "600s"` in a threshold entry) is dropped and the renamed
`_seconds` field takes its default, so a custom value can silently revert to
the default. Carry every custom value over to the renamed field and review
the first plan: changed alignment periods and durations surface there as
policy updates.

#### Verification

After migrating, `terraform plan` must show **no changes**. Any policy update
in that plan means a value was not carried over verbatim.
