# Firebase setup guide

EdhiConnect AI uses Firebase Authentication for passwords and Cloud Firestore for profiles, incidents, fleet relationships and welfare records. The checked-in Android and web configuration targets `eedhi-b08e1`.

## 1. Project and platform configuration

Keep the following configuration aligned:

| File | Purpose |
| --- | --- |
| [.firebaserc](../.firebaserc) | Default CLI project |
| [firebase.json](../firebase.json) | Rules, local emulators and Hosting configuration |
| [lib/firebase_options.dart](../lib/firebase_options.dart) | Flutter platform options |
| [android/app/google-services.json](../android/app/google-services.json) | Android Firebase registration |
| [google-services.json](../google-services.json) | Supplied Android configuration copy |
| [android/app/build.gradle.kts](../android/app/build.gradle.kts) | Android package `com.eeedhi` |

For a new project, register the web app and Android package in Firebase Console and generate matching FlutterFire options. Configure each target platform's own registration when preparing that platform. The application checks project identity to keep its cloud session aligned.

Client Firebase options contain project identifiers and client API keys. These belong to the app configuration; private service-account keys and OAuth credentials do not. See [Firebase API keys](https://firebase.google.com/docs/projects/api-keys).

## 2. Enable password authentication

In Firebase Console, open **Authentication → Sign-in method** and enable **Email/Password**.

Citizen and driver accounts use internal authentication addresses. The user-facing identifiers are CNIC or phone, each with the same password. Exact Firestore alias reads resolve these identifiers before Firebase verifies the password.

The current login workflow uses password authentication. There is no phone-message verification step to configure.

## 3. Create the database and deploy rules

Create the default Cloud Firestore database in the target Firebase project. Choose its region deliberately and deploy the checked-in rules before testing role-specific data flows.

Install the local CLI dependencies:

```powershell
npm ci --prefix tools/firebase-rules
.\tools\firebase-rules\node_modules\.bin\firebase.cmd login
.\tools\firebase-rules\node_modules\.bin\firebase.cmd projects:list
.\tools\firebase-rules\node_modules\.bin\firebase.cmd deploy --only firestore:rules --project eedhi-b08e1
```

Use a Google account that manages the project. If the browser callback cannot return locally, use `login --no-localhost` and complete the displayed session with that account.

The rules are in [firestore.rules](../firestore.rules). Preserve the ownership and cross-document checks when editing them. [Storage rules](../storage.rules) are included for the corresponding image paths; the current attachment workflow writes prepared previews to Firestore.

## 4. Provision the HQ account

HQ requires both an Authentication account and a matching private profile with `role: admin` and `isActive: true`.

The local [provisioning utility](../tools/firebase-rules/provision-admin.mjs) targets `eedhi-b08e1` and the administrator email `admin@gmail.com`. It verifies project access, creates or updates the profile, sets the supplied password, enables the account and checks that password login and client profile reads succeed.

Install its dependencies:

```powershell
npm ci --prefix functions
npm ci --prefix tools/firebase-rules
```

Run it with a privately entered password:

```powershell
$adminSecurePassword = Read-Host "HQ password" -AsSecureString
$adminPasswordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminSecurePassword)
try {
    $env:EDHI_ADMIN_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($adminPasswordPointer)
    node tools/firebase-rules/provision-admin.mjs
} finally {
    Remove-Item Env:\EDHI_ADMIN_PASSWORD -ErrorAction SilentlyContinue
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($adminPasswordPointer)
}
```

This is an account-management operation: rerunning it updates the account password to the entered value. Keep the password outside repository files and documentation. The script verifies its target project before changing data.

For a different Firebase project, update the script's explicit target/email and matching project configuration together.

## 5. Registration data flow

A citizen or driver signs up through the app. AuthService creates an Authentication identity and commits these related Firestore records:

1. `users/{uid}`: private profile and role.
2. `phone_claims/{normalized-phone}`: unique phone reservation.
3. `login_aliases/cnic_<digits>`: CNIC username lookup.
4. `login_aliases/phone_<normalized-phone>`: phone username lookup.

A registration collision is surfaced to the user. The application handles unsuccessful setup without presenting a partially configured account as a successful registration.

## 6. Fleet initialization through HQ

Create operational units through the HQ interface rather than manually fabricating profile records:

1. Register a driver account.
2. Sign in to HQ.
3. Open **Fleet operations** and locate **Registered drivers**.
4. Select **Create ambulance & assign driver** or assign an eligible existing unit.
5. Enter vehicle details and select a map parking point.
6. Save and confirm the unit and driver link.

The assignment workflow maintains `employees` and `driver_links` together. A user profile alone represents an account; it does not create a vehicle.

## 7. Photo records

Missing-person and donation photos are validated, resized and re-encoded. The prepared image is stored in `photo_attachments`; the parent record stores a `firestore-photo:` reference.

The current app needs Authentication, Firestore and the deployed Firestore rules for this flow. Image-specific rules control content type, ownership, exact reads and stored size.

## 8. Verification and administration

Run emulator checks before rule deployment:

```powershell
.\tools\firebase-rules\node_modules\.bin\firebase.cmd emulators:exec --only firestore,storage --project demo-edhi-pdf "node tools/firebase-rules/rules.test.mjs"
```

[inspect-fleet.mjs](../tools/firebase-rules/inspect-fleet.mjs) is an owner-operated diagnostic for profiles and links. Its output contains operational account data; keep logs in the local ignored build directory.

[live-free-plan-smoke.mjs](../tools/firebase-rules/live-free-plan-smoke.mjs) creates a temporary authentication/profile/attachment fixture in its explicitly configured project, verifies identifier login, then performs cleanup. Run it deliberately with the project owner's authorization.

See [Build and deployment](BUILD_AND_DEPLOYMENT.md) for web hosting and Android packaging, and [Database schema](DATABASE_SCHEMA.md) for field definitions.
