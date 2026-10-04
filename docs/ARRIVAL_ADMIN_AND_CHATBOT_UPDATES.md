# Arrival, database administration and welfare knowledge

## Arrival without an admin panel

The saved road journey determines arrival: `startedAt + durationSeconds + 5 real seconds`. The one-second app ticker lets the request owner or assigned driver reconcile arrival, even when no admin is logged in. Firestore rules enforce the deadline using server time and require a single transaction updating the request, endpoint telemetry and stopped route. The ambulance remains busy until completion is confirmed.

Paused, cancelled, stopped and replaced journeys cannot arrive. A speed change recalculates remaining travel; the final five-second delay is not sped up. An offline client synchronizes when connected. Browser background throttling can delay its timer.

For arrival while **every client is closed**, the optional Functions worker schedules a Cloud Task at the same deadline and checks the saved assignment again before writing. This backend requires Firebase Blaze billing, Cloud Tasks and the appropriate service-account permissions. It has been unit tested, but has not been deployed or verified against a live task queue. See [Firebase task functions](https://firebase.google.com/docs/functions/task-functions).

Deploy the normal client and Firestore rules together; existing builds cannot perform the newly permitted arrival transaction until these rules are deployed:

```powershell
flutter build web --release
.\tools\firebase-rules\node_modules\.bin\firebase.cmd deploy --only firestore:rules,hosting --project eedhi-b08e1
```

Optional server deployment, once the project owner has enabled the required backend services:

```powershell
npm ci --prefix functions
.\tools\firebase-rules\node_modules\.bin\firebase.cmd deploy --config firebase.functions.json --only functions:edhiconnect:scheduleAmbulanceArrival,functions:edhiconnect:commitAmbulanceArrival --project eedhi-b08e1
```

The separate config avoids adding a Functions deployment to the ordinary free-plan configuration. The retained phone login function is not required by this app and is excluded by the two function names above.

## Administration

HQ → More → Database browses the application's 19 supported collections. The list loads the first 200 document IDs; exact ID lookup opens records outside that limit. Expand a record to inspect all fields. Add and Edit use a JSON document editor; timestamps, coordinates, bytes and references retain their native Firestore types using `__type` tags. Save replaces that document. Audit history is read-only; writes are logged without copying private document contents into the audit message.

Delete requires typing the exact document ID. Busy ambulances must finish or cancel their mission first. Deleting an active request first cancels it through the existing operational transaction. Administrators cannot delete their own current profile or remove their own admin access through the editor.

This editor manages **Firestore documents**, not Firebase Authentication accounts or project IAM. Creating a user document does not create login credentials. Deleting one does not delete its Auth identity. Phone/CNIC identity changes also require maintaining phone claims and login aliases; the ordinary profile editor deliberately preserves the login phone. Use Firebase Auth administration for identity lifecycle work.

The People editor now saves name and address to the database. The dashboard shows a cancellation review alert. People highlights accounts with three cancellations, identifies current restrictions and offers Unban. Unban clears the restriction and restarts counting while retaining the previous count for review; the next cancellation begins at one. The restriction applies to app emergency requests, not the account's login.

## Welfare chatbot

The assistant searches a bundled corpus of 24 downloaded official Edhi and Chhipa pages, plus reviewed service answers and an app guide. It recognizes common Urdu/Roman Urdu terms, spelling variants and limited provider follow-ups. It distinguishes urgent distress from ordinary ambulance questions, displays clickable official sources and suggests related questions. It does not claim live ambulance availability, prices, blood stock or shelter admissions.

Retrieval happens locally, with no language-model API key, per-message model fee or website request. The corpus is cached once. Removed the artificial 500 ms reply delay; question and response persist in one batch. Histories are scoped to the authenticated user's UID rather than a shared public thread. Earlier shared `thread_default` records remain accessible only to administrators. Answers remain in English; multilingual support currently covers query recognition.

Refresh the source snapshot before rebuilding:

```powershell
python tools/refresh_welfare_knowledge.py
```

The crawler uses official host allowlists, checks robots.txt, validates redirects and retains earlier successful documents when an individual refresh fails. It is a bounded source search assistant, not an unrestricted generative model or a claim to know every fact. No private conversation is sent to source websites.

## User management and chatbot follow-up

People now highlights the actual user row in yellow when the cancellation count reaches three. Separate Ban and Active switches control emergency requests and account activation. Manual bans persist until an administrator unbans; automatic cancellation restrictions still expire after 24 hours. Add user creates Firebase email/password credentials in a secondary Auth instance and atomically reserves CNIC/phone aliases without signing the administrator out. Passwords are never stored in Firestore or audit records. Delete requires typing DELETE, blocks users with active emergencies or busy driver assignments, removes profile/aliases/phone claims and releases idle ambulance links. Historical reports remain. The Firebase Auth identity remains and requires server-side Auth administration for permanent deletion.

Registration checks duplicate aliases before creating credentials and returns transaction conflict outcomes outside the web SDK callback, avoiding the opaque converted-Future error for duplicate CNIC/phone registrations. The screenshot's CNIC already has a registered alias.

Chatbot replies no longer display source labels or links. Existing stored replies have their source footer removed at rendering. Ambulance instructions describe the request workflow without simulation wording. Blood queries preserve positive/negative signs, blood group and city context, support English/Roman Urdu/Urdu, and can list matching available donors from the app database. Lookup failures fall back to workflow instructions; no matching donors produces an explicit empty result. No medical compatibility matching is inferred. Severe distress still produces emergency contact guidance.

## Payments

The donation form currently records wallet/bank transaction references with `AwaitingVerification`; selecting Easypaisa or JazzCash does not initiate a payment. The simplest extension is an authorized recipient's merchant QR or bank/Raast transfer with manual admin verification. JazzCash offers [QR/Raast acceptance](https://www.jazzcash.com.pk/business/), and Easypaisa offers [merchant QR services](https://merchantportal.easypaisa.com.pk/).

For automatic confirmation, obtain approved credentials from [Easypaisa business onboarding](https://registerbusiness.easypaisa.com.pk/) or the [JazzCash merchant sandbox](https://sandbox.jazzcash.com.pk/MerchantDashboard). Implement server-created payment references, hosted checkout, authenticated response verification and idempotent donation updates. Keep merchant passwords/signing keys on the server; a client success screen or typed reference is not proof of payment. No payment gateway has been activated in this change.


## App-only assistant update

Chat replies now use implemented app workflows exclusively. The bundled organization corpus remains internal reference material; organization descriptions, names, links and source labels are excluded from generated replies. Older provider replies and suggestion chips are adapted when displayed. The chatbot gives English, Roman Urdu and Urdu app guidance and keeps blood-group, city and donor availability matching.

Open shortcuts navigate to Emergency Request, Home, Blood Bank, Donations, Missing Persons, Profile, First Aid, Centers and SOS Contacts. Blood guidance uses the actual Donate, Donors, Requests and Post Need controls. Payment replies describe transaction-reference verification without claiming to initiate a charge. The wipe feature remains at its previous implementation; no complete-reset backend was retained or deployed.

## Context from current app records

The chatbot checks available donor listings (up to 100 records), recent missing-person reports (up to 100), active blood requests (up to 50) and the signed-in user's own ambulance requests (up to 30). It reports counts within the records checked, filters group/city/name/status where appropriate, and distinguishes a failed lookup from an empty result. It retains relevant follow-up context and drops unrelated details when the topic changes. No creation or image-attachment workflow was added to chat; buttons open the existing app screens. Chhipa documents and refresh targets were removed from the bundled reference corpus. Existing historical provider mentions remain filtered when displayed.
