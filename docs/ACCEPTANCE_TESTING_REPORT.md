# Acceptance testing report

## 1. Verification baseline

Recorded application verification for the current source baseline:

| Check | Result | Scope |
| --- | --- | --- |
| Flutter analyzer | Passed; no issues | Dart analysis and configured lints |
| Flutter tests | 141 passed | Unit, service and widget regression checks |
| Firebase emulator rules | 44 passed | Firestore/Storage authorization and related-record writes |
| Retained authentication service | 9 passed | Node unit checks for the server authentication implementation |
| Web release build | Produced | Flutter web packaging |
| Android release APK | Produced | Android packaging and signature inspection |

Application and rule logs were reviewed locally. Runtime logs and account/case screenshots are kept outside the published documentation. The recorded test counts refer to their specific suites.

## 2. Reproduce the application checks

From the repository root:

```bash
flutter pub get
flutter analyze
flutter test
```

The package uses Flutter 3.44.0 / Dart 3.12.0 in the recorded environment. Fixtures construct typed records and test service paths or widgets without requiring the reviewer's personal Firebase accounts.

## 3. Reproduce authorization checks

```powershell
npm ci --prefix tools/firebase-rules
.\tools\firebase-rules\node_modules\.bin\firebase.cmd emulators:exec --only firestore,storage --project demo-edhi-pdf "node tools/firebase-rules/rules.test.mjs"
```

The test project name is separate from the configured application project. Rules fixtures use multiple authenticated identities and attempt both accepted and rejected direct writes.

Permission-denied output is expected for deliberately rejected test operations. The suite's pass/fail result is the acceptance signal.

## 4. Functional regression coverage

| Area | Behaviors reviewed |
| --- | --- |
| Authentication | CNIC/phone formatting, username selection, password account resolution and role handling |
| Registration | Valid input, private profile setup and identity relationships |
| Requested updates | Location presentation, optional campaigns and image fields |
| Photo preparation | Supported signatures, invalid data rejection and bounded PNG re-encoding |
| Driver management | Registered-driver display, existing-unit linking, create-and-link workflow and busy-unit protection |
| Missing-person HQ | Details, images, contact context, filters, search and stream updates |
| Triage | Priority matching, duplicate context and explainable review signals |
| Dispatch | Queue ordering, resource eligibility and consistent reservation behavior |
| Journey presentation | Route progress, shared time inputs, pause/stop behavior and map selection |
| Mission completion | Arrival prerequisite, unit release and stale-assignment safety |
| Cancellation | Eligibility across assignment stages, server policy and atomic release |
| Layout | Representative responsive layouts and reusable widget behavior |
| Supporting features | Donation, blood-bank, contact and preference behavior |

## 5. Principal Flutter suite map

| File | Focus |
| --- | --- |
| [cnic_auth_test.dart](../test/cnic_auth_test.dart) | Identifier/profile authentication behavior |
| [requested_updates_test.dart](../test/requested_updates_test.dart) | Login/location/photo/campaign changes |
| [photo_codec_test.dart](../test/photo_codec_test.dart) | Image input and preview preparation |
| [registered_drivers_test.dart](../test/registered_drivers_test.dart) | Account-to-unit assignment and driver UI |
| [admin_missing_persons_test.dart](../test/admin_missing_persons_test.dart) | HQ report presentation and updates |
| [ambulance_policy_test.dart](../test/ambulance_policy_test.dart) | Fleet and terminal-state invariants |
| [emergency_cancellation_ui_test.dart](../test/emergency_cancellation_ui_test.dart) | Eligible cancellation presentation |
| [triage_and_features_test.dart](../test/triage_and_features_test.dart) | Decision support and feature behavior |
| [nfr_and_acceptance_test.dart](../test/nfr_and_acceptance_test.dart) | Service and acceptance checks |
| [ui_layout_test.dart](../test/ui_layout_test.dart) | Adaptive interface checks |
| [pdf_changes_test.dart](../test/pdf_changes_test.dart) | Earlier requested feature regressions |
| [widget_test.dart](../test/widget_test.dart) | Application widget baseline |

The [test directory](../test/) contains the full set of regression sources.

## 6. Authorization scenarios

The [rules suite](../tools/firebase-rules/rules.test.mjs) checks boundaries including:

- Authenticated owner profile access and restricted personal updates.
- Citizen/driver registration fields and identifier alias relations.
- Prevention of public self-registration as HQ.
- Alias exact reads and denied alias enumeration.
- Active-role access to incidents, units and welfare records.
- Driver ownership and restricted operational updates.
- Incident completion with related unit release.
- Rejection of premature, unrelated or telemetry-altering completion.
- Repeated/stale completion safety.
- Eligible cancellation and matching usage updates.
- Prevention of isolated unit release and unrelated journey changes.
- Attachment ownership, MIME type, size and exact-read policy.
- Storage image path, identity and content checks.

The rule source is the authoritative policy; fixtures should change alongside intentional rule changes.

## 7. Retained service checks

```bash
npm ci --prefix functions
npm test --prefix functions
```

Nine checks cover normalized mobile identifiers, existing-UID password verification, malformed input, wrong-password handling, account activation, token identity/project validation, rate accounting and network errors.

This service is retained separately from the app's current alias-based login path. See [functions README](../functions/README.md).

## 8. Build artifact checks

```bash
flutter build web --release
flutter build apk --release
```

The Android artifact is included as [EdhiConnect.apk](../EdhiConnect.apk). Its hash and package identity are recorded in [Build and deployment](BUILD_AND_DEPLOYMENT.md).

Android signature verification was performed on the produced package. The build configuration records which signing configuration is used.

## 9. Portal walkthrough checks

The coordinated review covered:

1. Registered driver visibility in HQ.
2. Unit creation and driver assignment.
3. Parking-point selection with the map.
4. Mission access through the linked driver account.
5. Citizen/HQ shared incident presentation.
6. Terminal state and resource-release behavior.
7. Missing-person image and full details in HQ.
8. Welfare form fields and optional campaign behavior.

Use [Demonstration script](DEMONSTRATION_SCRIPT.md) for a repeatable review using designated fixture accounts and records.

## 10. Keeping acceptance evidence current

A source change should identify the behavior affected and run its relevant checks. Authorization changes require emulator coverage. Widget changes should be reviewed at the intended viewport. Android packaging changes require a new artifact and recorded hash.

Update this report when the verified suite counts or artifact identity change. Keep claims tied to actual command results and reviewed behavior.
