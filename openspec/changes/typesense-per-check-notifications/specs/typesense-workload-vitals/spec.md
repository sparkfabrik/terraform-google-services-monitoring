# typesense-workload-vitals (delta)

## MODIFIED Requirements

### Requirement: Notification channel cascade and alert strategy

Workload vitals policies SHALL resolve notification routing per check as defined by the Typesense per-check notification resolution (check-level `notification_enabled`/`notification_channels` when non-null, otherwise service level, otherwise root) and SHALL apply `workload_check.auto_close_seconds` (default 3600) and optional `workload_check.notification_prompts` to every policy of the block. All policies of the block (threshold families and replica availability) share the block's resolved routing.

#### Scenario: Notifications inherited

- **WHEN** `typesense.notification_enabled = true` and no override list is set at any level
- **THEN** workload policies use the root `notification_channels`

#### Scenario: Silent workload check

- **WHEN** an app sets `workload_check.notification_enabled = false`
- **THEN** every memory, CPU, volume and replica policy of that app is created with an empty notification channel list

#### Scenario: Workload channel override

- **WHEN** an app sets `workload_check.notification_channels = ["projects/p/notificationChannels/123"]`
- **THEN** every policy of that app's workload block notifies only that channel while the app's other checks keep the service routing
