# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] - 2025-12-01

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.4.0...0.5.0)

### Changed

- refs platform/board#3935: Kyverno log alert filter updated with explicit error patterns.

### Breaking change

- The previous `severity>=ERROR` filter for Kyverno log alerts has been removed and replaced with explicit text pattern matching. This significantly alters alert behavior, as alerts are now triggered based on specific error patterns rather than severity level. Please review and update your alert expectations accordingly.

## [0.4.0] - 2025-10-13

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.3.0...0.4.0)

### changed

- Rename tf file from `cloud-sql.tf` to `cloud_sql.tf`.
- Rename tf file from `kyverno_log_alert.tf` to `kyverno.tf`.
- Add cert-manager missing issuer alert log.

## [0.3.0] - 2025-10-07

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.2.0...0.3.0)

### Changed

- Add kyverno alert log.
- Update module documentation.

## [0.2.0] - 2024-10-17

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.1.1...0.2.0)

### Changed

- Increase default alert thresholds for Cloud SQL CPU, memory and disk utilization.

## [0.1.1] - 2024-06-25

[Compare with previous version](https://github.com/sparkfabrik/terraform-google-services-monitoring/compare/0.1.0...0.1.1)

### Fixed

- Fixed Google provider minimum required version.

## [0.1.0] - 2024-06-19

### Added

- Add support for Cloud SQL monitoring:
  - CPU utilization
  - Memory utilization
  - Disk utilization
