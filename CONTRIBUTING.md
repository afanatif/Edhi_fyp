# Contributing to EdhiConnect AI

Thank you for helping improve the connected emergency and welfare platform. Start with the [project overview](docs/PROJECT_DOCUMENTATION.md) and [distributed-system design](docs/DISTRIBUTED_SYSTEM_ARCHITECTURE.md).

## Local setup

```bash
git clone https://github.com/afanatif/Edhi_fyp.git
cd Edhi_fyp
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

Use Flutter 3.44 / Dart 3.12. Configure the intended Firebase project using the [setup guide](docs/FIREBASE_SETUP_GUIDE.md). Keep project-owner credentials in local tooling and use designated review accounts.

## Make a coherent change

Work in a descriptive branch. State the concrete behavior being changed and identify the affected portal, service, model and rule policy.

| Change | Review focus |
| --- | --- |
| Screen or form | Validation, loading/error state, responsive behavior and navigation |
| Data model | Parsing, serialization, existing records and affected UI |
| Dispatch or lifecycle | Transaction reads, concurrency, active request identity and unit release |
| Driver assignment | Account activation, unique claim and busy-unit protection |
| Authentication | Alias normalization, UID/profile relation and role routing |
| Authorization | Direct-client denial and accepted related-record operations |
| Image handling | Byte validation, bounded preparation and record visibility |
| Dependencies | Locked versions, build compatibility and affected checks |

Use existing shared widgets and services where their responsibilities match. Keep persistence and multi-record logic in the service layer rather than duplicating it in portal widgets.

## Validate

```bash
dart format lib test
flutter analyze
flutter test
node tools/check-documentation.mjs
```

Run the emulator suite for rules or authorization-related changes:

```powershell
npm ci --prefix tools/firebase-rules
.\tools\firebase-rules\node_modules\.bin\firebase.cmd emulators:exec --only firestore,storage --project demo-edhi-pdf "node tools/firebase-rules/rules.test.mjs"
```

Use targeted tests while implementing and relevant complete checks before delivery. Add regression fixtures for meaningful new behavior, especially concurrency and ownership conditions. Review mobile/desktop layouts when changing a shared screen.

For changes in the retained server authentication code:

```bash
npm ci --prefix functions
npm test --prefix functions
```

## Document

Update the guide that owns the changed behavior. Keep local source links relative, describe current implementation accurately and preserve consistent role/status/collection names.

Record user-visible changes in [CHANGELOG.md](CHANGELOG.md). Update APK identity and verification evidence when publishing a newly built Android artifact.

## Commit and review

Use a concise commit subject describing the outcome. A review description should explain:

1. The trigger/problem and resulting behavior.
2. The relevant data or authorization change.
3. Checks actually performed and their results.

Do not include credentials, signing keys, live database exports, runtime logs or case screenshots in the commit. [SECURITY.md](SECURITY.md) describes repository and data boundaries.
