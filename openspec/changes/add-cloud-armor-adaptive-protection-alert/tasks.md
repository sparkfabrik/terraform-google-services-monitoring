## 1. Implementation

- [x] 1.1 Add the `cloud_armor_adaptive_protection` variable with validation on `security_policies`
- [x] 1.2 Add `cloud_armor_adaptive_protection.tf`: data source per policy, log-based alert policy, plan-time precondition
- [x] 1.3 Add the `cloud_armor_adaptive_protection_alert_policy_name` output
- [x] 1.4 Add the example, regenerate the README, add the CHANGELOG entry

## 2. Verification

- [x] 2.1 Plan against a real project: policy with Adaptive Protection enabled creates the alert
- [x] 2.2 Plan against a real project: policy without Adaptive Protection fails the precondition and names it
- [x] 2.3 Plan with `verify_adaptive_protection_enabled = false` creates the alert without reading the policy
- [x] 2.4 `make lint` passes
