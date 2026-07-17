# typesense-log-alert (delta)

## MODIFIED Requirements

### Requirement: Notification channel cascade

The alert policy SHALL resolve notification routing per check as defined by the Typesense per-check notification resolution: check-level `notification_enabled`/`notification_channels` when non-null, otherwise per-service `notification_channels` if non-empty, otherwise root `notification_channels`, with an empty list when the effective `notification_enabled` is false. `log_check` and `flood_check` resolve independently of each other.

#### Scenario: Notification channels inherited from root

- **WHEN** `typesense.notification_channels` is empty, root `notification_channels` is set, and the check sets no notification fields
- **THEN** the alert uses root `notification_channels`

#### Scenario: Notifications disabled

- **WHEN** `typesense.notification_enabled = false` and the check sets no notification fields
- **THEN** the alert uses an empty notification channel list

#### Scenario: Silent flood check with notifying log check

- **WHEN** an app sets `flood_check.notification_enabled = false` and leaves `log_check` notification fields null on a service with channels configured
- **THEN** the flood policy has no notification channels while the log severity policy keeps the service routing

#### Scenario: Log check channel override

- **WHEN** an app sets `log_check.notification_channels = ["projects/p/notificationChannels/123"]`
- **THEN** the log severity policy notifies only that channel
