# EdhiConnect AI documentation

This library explains the connected emergency-response and humanitarian-welfare platform from product, engineering and operational perspectives. The source of truth for implementation is the checked-in Flutter application, Firebase rules and test suites.

## Reading paths

| Reader | Suggested sequence |
| --- | --- |
| Project reviewer | [Overview](PROJECT_DOCUMENTATION.md) → [Distributed design](DISTRIBUTED_SYSTEM_ARCHITECTURE.md) → [Master guide](COMPREHENSIVE_FYP_MASTER_DOCUMENTATION.md) |
| Citizen or HQ operator | [Portal guide](USER_AND_ADMIN_GUIDE.md) → [Walkthrough](DEMONSTRATION_SCRIPT.md) → [Ambulance coordination](ambulance-tracking-and-policy.md) |
| Developer | [Build and deployment](BUILD_AND_DEPLOYMENT.md) → [Firebase setup](FIREBASE_SETUP_GUIDE.md) → [Schema](DATABASE_SCHEMA.md) → [Contribution guide](../CONTRIBUTING.md) |
| Test reviewer | [Acceptance report](ACCEPTANCE_TESTING_REPORT.md) → [Revision history](EVALUATION_AND_REVISION_HISTORY.md) → [Implementation record](Changes-implementation.md) |

## Guide catalogue

- [Project documentation](PROJECT_DOCUMENTATION.md): product scope, responsibilities and module boundaries.
- [Distributed-system architecture](DISTRIBUTED_SYSTEM_ARCHITECTURE.md): independent clients, shared cloud authority, concurrency, data propagation and atomic operations.
- [Comprehensive master documentation](COMPREHENSIVE_FYP_MASTER_DOCUMENTATION.md): integrated requirements and technical design.
- [Database schema](DATABASE_SCHEMA.md): collections, fields, relations and rule ownership.
- [User and admin guide](USER_AND_ADMIN_GUIDE.md): portal tasks and operating procedures.
- [Firebase setup guide](FIREBASE_SETUP_GUIDE.md): configuration and administrator provisioning.
- [Build and deployment](BUILD_AND_DEPLOYMENT.md): prerequisites, local server, builds and hosting.
- [Identity, location and photos](LOGIN_LOCATION_AND_PHOTO_UPDATES.md): cross-identifier authentication, device location, map pins and image flow.
- [Ambulance tracking and policy](ambulance-tracking-and-policy.md): unit assignment, mission lifecycle and map reconciliation.
- [Acceptance testing report](ACCEPTANCE_TESTING_REPORT.md): recorded results and repeatable checks.
- [Demonstration script](DEMONSTRATION_SCRIPT.md): a coordinated multi-portal walkthrough.
- [Changes and implementation](Changes-implementation.md): current changes mapped to source.
- [Project status and development guide](PROJECT_STATUS_AND_ROADMAP.md): maintained components and a structured development process.
- [Evaluation and revision history](EVALUATION_AND_REVISION_HISTORY.md): engineering review and regression evidence.

## Documentation conventions

Role names match the interface; stored values match the data model. “Citizen” stores `user`, “Driver” stores `employee`, and HQ stores `admin`. Ambulance units live in `employees`; the collection name reflects the existing model.

Examples describe generic accounts and records. Credentials, exported account data and live case images stay outside the documentation. Local commands run from the repository root unless stated otherwise.

Useful entry points: [README](../README.md), [security guide](../SECURITY.md), [change log](../CHANGELOG.md).
