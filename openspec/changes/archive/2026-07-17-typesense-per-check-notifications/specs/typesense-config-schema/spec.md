# typesense-config-schema (delta)

## ADDED Requirements

### Requirement: Per-check notification resolution

Every Typesense check block (`uptime_check`, `container_check`, `log_check`, `flood_check`, `workload_check`) SHALL accept `notification_enabled = optional(bool, null)` and `notification_channels = optional(list(string), null)`. The effective routing for a check's policies SHALL be resolved as: effective enablement is the check-level `notification_enabled` when non-null, otherwise the service-level `typesense.notification_enabled`; when effectively disabled the channel list is empty; when effectively enabled the channel list is the check-level `notification_channels` when non-null, otherwise the service-level list when non-empty, otherwise the root `notification_channels`. The most specific non-null setting always wins.

#### Scenario: Defaults inherit current behavior

- **WHEN** a check sets neither `notification_enabled` nor `notification_channels`
- **THEN** its policies use the service-level resolution unchanged and an upgrading consumer sees no plan diff

#### Scenario: Silent check

- **WHEN** a check sets `notification_enabled = false` on a service with channels configured
- **THEN** that check's policies are created with an empty notification channel list while other checks keep the service routing

#### Scenario: Check-level channel override

- **WHEN** a check sets `notification_channels = ["projects/p/notificationChannels/123"]` and leaves `notification_enabled` null on a service with `notification_enabled = true`
- **THEN** that check's policies notify only the overridden channel

#### Scenario: Check re-enables over a disabled service

- **WHEN** `typesense.notification_enabled = false` and a check sets `notification_enabled = true` with `notification_channels = ["projects/p/notificationChannels/123"]`
- **THEN** that check's policies notify the overridden channel while all other checks stay silent

#### Scenario: Empty override list

- **WHEN** a check sets `notification_channels = []` and is effectively enabled
- **THEN** its policies are created with no notification channels and validation does not reject the empty list
