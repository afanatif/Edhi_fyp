# Multi-portal walkthrough

This walkthrough presents the platform as a connected workflow across citizen, driver and HQ sessions. Use designated review accounts and generic welfare fixtures.

## Preparation

1. Start the app on localhost using [Build and deployment](BUILD_AND_DEPLOYMENT.md).
2. Open three isolated browser profiles or devices.
3. Sign one session into HQ with its provisioned account.
4. Register or sign in a driver in the second session.
5. Register or sign in a citizen in the third session.
6. Keep all sessions pointed at the same configured Firebase project.

The presentation begins with the three portals and then follows one shared incident. Explain that each client has its own UI state and receives updates from the same cloud records.

## Scene 1: identity and portal routing

Show the login toggle between CNIC and Phone. Explain that both are usernames for the same password account.

Sign in and point out the assigned role. In HQ, show the registered-driver list and the separate ambulance inventory. Explain why registration and vehicle assignment are different entities.

## Scene 2: create an ambulance and assign a driver

In HQ Fleet operations:

1. Locate the active unlinked driver.
2. Choose **Create ambulance & assign driver**.
3. Enter a designated review vehicle number and model.
4. Open the parking map, drop a pin and confirm.
5. Save the assignment.
6. Show the linked account in the registered-driver panel and the unit in the fleet list.

Switch to the driver session. Show the assigned ambulance and mission workspace. Explain the unique driver-link claim maintained with the unit association.

## Scene 3: citizen location and request

In the citizen portal:

1. Show the actual current-location display and refresh action.
2. Open the emergency flow.
3. Select the patient point on the map.
4. Choose a category and write a clear description.
5. Submit and open tracking.

Explain that the patient's map point is the dispatch destination. The device point can help locate it, but the selected patient location is the submitted location.

## Scene 4: HQ incident review

Show the new request, contact details, location, priority and review reasons. Explain how deterministic triage enriches the queue.

Review any flagged context using the available operator workflow. Select an eligible unit and dispatch.

Point out the updated incident and busy unit. Explain that both records are reserved together through a transaction.

## Scene 5: shared mission view

Switch between the citizen tracking screen, driver portal and HQ map. Show the same request ID, assigned unit and mission state.

Explain the distributed design: clients receive committed record changes asynchronously. The shared journey record supplies route geometry and timestamps for map progress.

Show arrival and then the supported completion action. Confirm the incident closes and the unit becomes available.

## Scene 6: donation with optional campaign

Create a clothing donation using generic item details and pickup context. Leave campaign unselected. Add a permitted fixture image, review the preview and submit.

In HQ Welfare, inspect the type, notes, campaign value and image. For monetary records, explain payment-reference recording and operator verification.

## Scene 7: missing-person reporting and HQ details

Use a designated fictional review case:

1. Enter identifying details and last-seen information.
2. Add a fixture image.
3. Enter a review contact.
4. Submit.
5. Open **HQ → Welfare → Missing persons**.
6. Search for the case and inspect all details.
7. Expand the photo and show contact actions.
8. Show supported report-status progression from the owner portal.

Use fixture records suitable for the audience rather than displaying personal account data.

## Scene 8: blood bank and quick help

Show the blood-bank Requests, Donate and Donors tabs. Register availability or inspect a designated donor fixture. Demonstrate group/city discovery and contact actions.

Open first aid, emergency contacts and the center directory. Explain how these tools connect stored information to device actions.

## Scene 9: engineering overview

Open the [distributed architecture](DISTRIBUTED_SYSTEM_ARCHITECTURE.md) and point to:

- Independent role-based clients.
- Firebase Authentication as identity authority.
- Firestore rules as the data-access boundary.
- Transactions for assignment and terminal release.
- Snapshot listeners for asynchronous portal updates.
- Shared typed models and service boundaries.

Finish with the [acceptance report](ACCEPTANCE_TESTING_REPORT.md) and repository build instructions.

## Review cleanup

Close the designated review mission through the supported workflow. Restore any changed donor availability and remove temporary review records through the appropriate owner/HQ tools. Keep production account credentials out of presentation material.
