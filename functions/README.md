# Retained authentication service

This directory also contains the optional arrival scheduler and task worker. They use Cloud Tasks to commit arrival five seconds after travel ends, including when every client is closed. Deployment and limitations are described in [arrival and administration updates](../docs/ARRIVAL_ADMIN_AND_CHATBOT_UPDATES.md). The separate [Functions configuration](../firebase.functions.json) keeps ordinary app deployments on their current workflow.

This directory contains an independently tested server authentication implementation. The current Flutter app signs in through **Firestore identifier aliases plus Firebase password authentication**.

## Current client workflow

AuthService resolves a phone or CNIC to its opaque authentication address, verifies the password with Firebase Authentication and loads the private profile. See [Identity, location and photos](../docs/LOGIN_LOCATION_AND_PHOTO_UPDATES.md).

[firebase.json](../firebase.json) currently configures Firestore/Storage rules, emulators and Hosting. It has no Functions deployment entry.

## Retained source

| File | Purpose |
| --- | --- |
| [phone-login.mjs](phone-login.mjs) | Identifier normalization, password verification, identity checks and request accounting |
| [index.mjs](index.mjs) | HTTPS/Firebase integration for the server implementation |
| [phone-login.test.mjs](phone-login.test.mjs) | Unit fixtures for the retained flow |

The server flow resolves an existing account, verifies its password/token/project identity and returns a custom session token. It uses private request accounting in `auth_login_limits` and generic credential errors.

## Dependencies and tests

The package declares Node.js 22 and Firebase Admin/Functions dependencies.

```bash
npm ci --prefix functions
npm test --prefix functions
```

The recorded suite has 9 passing checks covering normalization, password verification, malformed requests, account status, token identity, request accounting and network errors.

## Local administration

The [HQ provisioning utility](../tools/firebase-rules/provision-admin.mjs) also loads Firebase Admin from this directory's dependencies. It obtains management access from a local Firebase CLI session and takes its password through `EDHI_ADMIN_PASSWORD`.

Follow [Firebase setup](../docs/FIREBASE_SETUP_GUIDE.md) for that operation. Keep environment files, passwords and privileged credentials outside Git.
