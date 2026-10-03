# User and administrator guide

The platform has citizen, driver and HQ portals. Sign-in routes each active account to its assigned role.

## 1. Register and sign in

Choose citizen or driver during registration. Enter your name, CNIC, mobile number, address and password. Use your own identifiers consistently; the app normalizes their formatting.

On the login page, switch between **CNIC** and **Phone**. Enter the selected identifier with the same account password. Changing tabs does not create a second account or change your role.

HQ uses its provisioned administrator email and password. Administrator access is assigned through trusted setup rather than public registration.

## 2. Select the current location

The citizen home view shows the current location below the greeting. Use the location action to request or refresh the device position and address.

For an emergency, open the patient-location map and drop or move the pin to the person needing help. Confirm the selection after checking the visible place. The submitted incident uses that selected point.

A manually selected patient location can differ from the phone's current position. Check the patient point before sending the request.

## 3. Request emergency help

1. Open the emergency action.
2. Choose the category that fits the incident.
3. Describe the situation and check contact information.
4. Confirm the patient's map location.
5. Submit and open the tracking view.

Tracking displays the request status, assigned unit information and the mission map. The visible progress stages connect submission, assignment, travel, arrival and completion.

Use the cancellation action while the app shows it as available. The server validates eligibility from the original request; a driver assignment does not restart the policy. Arrival is a mission stage; completion closes the response and releases the unit.

## 4. Make a donation

Choose monetary, ration or clothing. Campaign selection is optional.

For a monetary record, enter the amount and the requested payment-reference details. HQ reviews the stored payment information. For material contributions, describe the items and include pickup/contact context.

Add an image where appropriate using camera/gallery selection. Review the preview before submitting; replace or remove the selected photo if needed. Your donation history shows the resulting record and review state.

## 5. Use the blood bank

The blood-bank page contains **Requests**, **Donate** and **Donors** tabs.

- Requests: review urgent blood needs or submit a need with group, units and contact context.
- Donate: register your blood group, city and availability.
- Donors: search matching group/city records and use contact actions to coordinate.

Keep availability current so the directory remains useful to people searching for help.

## 6. Report a missing person

Open missing persons and create a report. Enter the person's name, age, gender, last-seen place/time, distinguishing description and reporting contact.

Add a clear optional image. Review the photo and details before submitting. The report appears in the shared bulletin and HQ missing-person view.

The reporting owner can make the supported found/reunited status changes. Contact actions connect viewers with the listed reporting contact.

## 7. Driver account and mission access

Register as driver, then sign in. HQ assigns your registered account to an ambulance before its mission dashboard becomes operational.

Once linked, the portal shows the assigned unit and relevant mission. Review patient location, category, description and contact information. Open the navigation/contact actions as needed.

The shared mission status updates across portals. Use the supported mission completion action after arrival. Unit availability follows the completed transaction.

## 8. HQ: create an ambulance and assign a driver

Open **Fleet operations**. The unit list and **Registered drivers** panel represent vehicles and accounts separately.

To create and link a unit:

1. Select **Create ambulance & assign driver** or the create action on an unlinked driver.
2. Choose an active registered driver.
3. Enter the vehicle plate/number and model.
4. Open the parking-location map and drop a pin.
5. Select a center association where relevant.
6. Save and confirm the assignment in the unit and registered-driver views.

To link an existing unit, select the driver's assignment action and choose an eligible unassigned ambulance.

Driver identity details are taken from the registered account. The service maintains a unique driver claim and checks unit eligibility. Busy units stay protected while their current mission is active.

## 9. HQ: review and dispatch incidents

Open the emergency/dispatch view. Review the pending queue, selected incident, priority and risk explanation. High-risk cases require review before the automatic assignment workflow.

Select an eligible available ambulance or use the dispatch workflow. The app reserves the unit and incident together, then updates the queue and mission views.

The map shows the selected incident, unit and road route. Fleet filters help locate available, busy and offline records. Journey controls update the shared route record, so associated clients follow the same progress data.

After arrival and completion, confirm the unit is available and its active request is cleared. Queued work can then use the released resource.

## 10. HQ: missing-person reports

Open **Welfare → Missing persons**.

The panel lists reports with image previews, status, identifying details, last-seen information and reporting contacts. Search by the supported record text and use the status filters to focus the list.

Open a report to inspect its full details. Expand the image for closer viewing and use the contact actions to coordinate with the reporter. The panel reflects the shared report record and its current status.

## 11. HQ: donations and blood bank

In Welfare, review donation type, amount or item description, campaign association, payment references and attachments. Use the available review actions to record the processing state.

The blood-bank area displays donor and need records. Use blood-group/city information and the recorded contact data to coordinate the next action.

## 12. Profiles, contacts and preferences

Profiles provide account information and supported preferences. High contrast and text scale adapt the presentation. Emergency contacts use device contact actions; a prepared message is handed to the messaging application for the user to send.

Quick help also includes first-aid pages and the center directory. Map/navigation actions open the corresponding device service.

## 13. Multi-portal review

Use separate devices or isolated browser profiles for citizen, driver and HQ accounts. Keep all sessions pointed at the same configured Firebase project.

A useful review order is: register driver → create/link unit in HQ → submit citizen request → inspect HQ assignment → inspect driver mission → follow citizen tracking → complete → review welfare reports.

The [walkthrough](DEMONSTRATION_SCRIPT.md) provides a detailed presentation sequence. The [distributed-system guide](DISTRIBUTED_SYSTEM_ARCHITECTURE.md) explains how changes move between these views.
