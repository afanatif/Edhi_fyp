# Project status and development guide

## Current platform

EdhiConnect AI contains citizen, driver and HQ portals backed by Firebase identity and shared cloud data. Android and web use the same service/model layer.

| Domain | Current implementation |
| --- | --- |
| Identity | Phone/CNIC password login, role profiles and account activation |
| Emergency coordination | Located incidents, priority/risk context, queue and transactional dispatch |
| Fleet | Unit inventory, map parking selection, registered-driver assignment and readiness |
| Mission lifecycle | Shared journey view, arrival, completion and coordinated resource release |
| Donations | Monetary/material records, optional campaigns, photos and HQ review |
| Blood bank | Donor availability, group/city discovery and urgent needs |
| Missing persons | Citizen reporting, images, status progression and detailed HQ view |
| Supporting tools | Contacts, first aid, centers, preferences, notifications and activity |
| Delivery | Source, authorization rules, regression checks, guides and Android APK |

## Maintained architectural boundaries

- Features own presentation and form interactions.
- Shared widgets own reusable map, image, location and status behavior.
- Services own identity, data operations and observable state.
- Models own record parsing and serialization.
- Rules own accepted client data-access policies.
- Tooling owns emulator fixtures and trusted administration tasks.

The [distributed-system guide](DISTRIBUTED_SYSTEM_ARCHITECTURE.md) explains how these boundaries work across independent clients.

## Development planning

A new feature should begin with a concrete workflow and identify the actors, records and invariants it changes.

| Planning question | Expected design output |
| --- | --- |
| Who performs the action? | Role and ownership boundary |
| What becomes shared? | Document shape and relations |
| Which changes belong together? | Transaction or batch design |
| What happens concurrently? | Re-read checks and conflict handling |
| What should another portal observe? | Query/subscription and UI state |
| What validates the result? | Service, widget and authorization fixtures |
| How does the operator set it up? | Updated setup/operation documentation |

## Review and delivery sequence

1. Define the desired before/after behavior.
2. Inspect the affected service, model and rule paths.
3. Implement the smallest coherent change across those paths.
4. Verify the affected portal and relationship invariants.
5. Run relevant checks and the analyzer.
6. Build affected artifacts.
7. Update the guide and change log.
8. Publish a reviewed revision.

## Change ownership

Account identity changes need Auth/profile/alias review. Fleet changes need driver-claim and active-mission review. Incident lifecycle changes need terminal-state and resource-release review. Welfare changes need attachment and record-visibility review.

Keep dependency updates explicit and preserve lockfiles. Use fixture data for regression review and private credentials for administrative operations.

## Reference set

[Project overview](PROJECT_DOCUMENTATION.md), [master guide](COMPREHENSIVE_FYP_MASTER_DOCUMENTATION.md), [schema](DATABASE_SCHEMA.md), [acceptance report](ACCEPTANCE_TESTING_REPORT.md), [contribution guide](../CONTRIBUTING.md).
