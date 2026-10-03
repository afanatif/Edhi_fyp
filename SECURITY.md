# Security and data handling

EdhiConnect AI handles account identifiers, contact information, patient locations, incident records and welfare case images. Identity, ownership and role policies are part of the shared data design.

## Report a security issue

Contact the repository owner through an available private channel before publishing sensitive account or case information. Use the [maintainer profile](https://github.com/afanatif) to identify the owner.

Include the affected workflow, expected/observed behavior and a reproducible example using fixture data. Keep passwords, tokens, CNICs, phone numbers and live record images out of public reports.

## Identity and roles

Firebase Authentication verifies passwords and supplies account UIDs. Private user profiles supply the role and active state.

Public registration creates citizen or driver profiles. HQ accounts are provisioned through trusted local management. User-owned profile updates cannot promote the role.

Phone/CNIC aliases contain only the opaque authentication address. Exact reads support sign-in; listing is denied. Passwords remain in Firebase Authentication.

## Access policies

The authoritative client policies are [firestore.rules](firestore.rules) and [storage.rules](storage.rules).

| Records | Access boundary |
| --- | --- |
| Profiles | Self read and selected personal updates; HQ management |
| Incidents | HQ, owner and assigned driver |
| Units | Active-account reads; HQ creation/assignment; restricted driver operational updates |
| Driver links | Own claim read; HQ management |
| Donations | Owner/HQ read; HQ review updates |
| Missing persons | Active-account bulletin; owner-supported status changes and HQ administration |
| Photos | Exact reads by kind/owner/HQ; immutable prepared attachment |
| Usage | Own/HQ read and validated related-incident updates |

Supporting collections have individual policies. For example, active clients can create application activity events. Review the precise rule rather than assuming every collection has identical ownership checks.

## Transactional operations

Incident assignment coordinates request and unit reservation. Completion and eligible cancellation coordinate terminal state and related resource release. Selected non-HQ operations are validated using related after-state in the rules.

Trusted HQ workflows maintain the unique driver claim alongside the unit association. Review both service transactions and rule policies when changing an invariant.

## Image handling

Supported selected image bytes are validated and re-encoded as bounded PNG previews. Re-encoding removes source metadata. Attachment records carry ownership and type information; parent records hold their reference.

Case images are operational data. Use fixture images for screenshots, public issues and documentation.

## Credentials and configuration

Firebase client project identifiers and API keys are included for application configuration; authorization depends on authenticated identity and rules. See [Firebase API-key guidance](https://firebase.google.com/docs/projects/api-keys).

Keep the following private:

- Firebase CLI refresh/access tokens and local credential caches.
- Service-account private keys and administration credentials.
- HQ passwords and other account passwords.
- Android signing keys and private signing properties.
- Database exports and live account/case records.

The repository ignore files exclude common private environment files, keys, exports, build logs and tool dependency directories.

## Administration utilities

The provisioning utility uses locally authenticated project-management access. Its entered password is supplied through a temporary environment variable and cleared after use. Running it updates the configured administrator account.

Fleet diagnostics and live smoke checks may read or create operational account records. Run them deliberately against their configured target and keep their logs local.

## Verification

The emulator suite tests direct accepted and rejected writes with several identities. Authentication, ownership, related-record transitions and attachment policies are covered by the [acceptance checks](docs/ACCEPTANCE_TESTING_REPORT.md).

When changing a security policy, update the rule, relevant service path and direct-client regression fixture together.
