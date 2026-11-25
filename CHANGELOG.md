# Change log

## 1.1.0 — 2026-11-25

### Driver acknowledgement and accountability

- Automatic dispatch now **offers** the job to the nearest driver with an account; they have 60 seconds to accept.
- Accept starts the trip at once; **Decline** passes the job on immediately and is not a penalty.
- No answer in 60 seconds is a **missed offer (penalty)** and the next-nearest ambulance is asked.
- After three refusals, or when every nearby driver has passed, HQ gets a red alert and the round restarts.
- Any open app moves the job on: HQ, the patient's app (no admin needed for linked drivers) or the driver's own app. Rules check the server clock (`dispatch_offers` collection, offer fields on requests and units).
- Driverless (simulated) units keep accepting automatically.
- Driver dashboard: ringing full-width offer card with countdown, Accept / Decline, and the driver's own response record.
- HQ → Fleet: sortable **Driver accountability** table (offers, accepted, missed, declined, last accepted, average response), per-driver history and penalty reset.
- Citizen tracker shows which driver is being asked and the seconds left.

- **Auto-offline:** two missed offers in a row take a driver off duty so patients stop waiting on them; accepting or declining resets the count, and the driver switches back on with one tap. HQ sees an "Auto-offline" tag.

### Donations: pay by QR

- easypaisa QR card in Donate → Money: tap to enlarge, **Download QR**, account holder name and masked number, and a 4-step "how to send" guide with a PIN/OTP warning.
- Transaction ID (TID) entry with paste button and format checks (pasted "TID: 3912 4455 019" is cleaned up), plus optional payment screenshot.
- Each TID can be claimed only once: a `payment_refs` lock document is written with the donation and the rules refuse a second claim.
- HQ shows the TID for matching against the account and can **Verify** or **Reject with a reason**; donors see the status and reason in My History.

### Cities

- Users get a home city from GPS on first sign-in (default Abbottabad), changeable from Home or Profile.
- Fixed list of Pakistani cities so spellings group together; older free-text cities are mapped where possible, others show as "City not set".
- Blood bank (urgent needs and donors) and missing persons open on the user's city, with a city switcher and "All cities".
- New emergencies, blood needs and missing-person reports store a city; HQ blood bank and missing-person views show per-city counts and filters.

## 1.0.0 — 2026-10-03

### Connected portals

- Citizen, driver and HQ workspaces with role-based routing.
- Phone/CNIC username toggle using the same Firebase password account.
- Private profiles, identifier aliases and normalized phone claims.
- HQ administrator provisioning through a trusted local utility.

### Emergency and fleet coordination

- Located emergency submission with explainable priority, duplicate context and risk review.
- Dispatch queue and transaction-based incident/unit reservation.
- Separate registered-driver and ambulance views in HQ.
- Create-and-assign and existing-unit driver assignment workflows.
- Map pin selection for patient destinations and ambulance parking.
- Shared route geometry, timestamps and mission progress.
- Coordinated completion/cancellation, usage accounting and unit release.

### Humanitarian welfare

- Monetary, ration and clothing records with optional campaigns.
- Optional prepared photo attachments on relevant donation and missing-person forms.
- Missing-person images, details, search and filters in HQ.
- Blood donor availability, group/city discovery and urgent needs.
- First aid, contacts, centers and presentation preferences.

### Verification and delivery

- Clean Flutter analyzer.
- 141 passing Flutter checks and 44 passing emulator rule checks.
- 9 passing checks for the retained server authentication implementation.
- Android APK and reproducible Android/web source.
- Full documentation library with distributed architecture, schema, setup and operating guides.
- README banner, diagrams, guide catalogue and APK download.
