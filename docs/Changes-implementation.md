# Changes and implementation record

This guide maps the current requested feature set to its implementation and regression coverage.

## Identity and location

| Change | Result | Source |
| --- | --- | --- |
| Phone/CNIC toggle | Alternative usernames for one password-authenticated account | [login screen](../lib/features/auth/login_screen.dart), [AuthService](../lib/services/auth_service.dart) |
| Atomic identifier setup | Profile, phone claim and aliases are coordinated on registration | [AuthService](../lib/services/auth_service.dart), [rules](../firestore.rules) |
| Current location display | Greeting area displays device location and refresh action | [location widget](../lib/core/widgets/current_location_display.dart), [LocationService](../lib/services/location_service.dart) |
| Patient map selection | User confirms the destination by selecting a point | [location picker](../lib/core/widgets/location_picker_sheet.dart) |
| Ambulance parking map | HQ chooses a staging location with a pin | [map picker](../lib/core/widgets/map_location_picker.dart) |

## Fleet and driver management

Registered-driver accounts appear separately from unit inventory in HQ. Operators can assign an eligible existing ambulance or create and assign a new unit.

The service coordinates the unit association and unique `driver_links` claim. Active-driver checks, existing-link checks and busy-unit protection keep the relationship explicit.

Sources: [registered-driver panel](../lib/features/admin/fleet/registered_drivers_panel.dart), [HQ dashboard](../lib/features/admin/dashboard/admin_dashboard_screen.dart), [FirestoreService](../lib/services/firestore_service.dart).

Checks: [registered-driver tests](../test/registered_drivers_test.dart), [ambulance-policy tests](../test/ambulance_policy_test.dart).

## Welfare forms and photos

Missing-person reports and relevant donation forms accept optional images. The picker validates input, prepares a bounded PNG and stores an attachment reference. Campaign selection is optional for donations.

HQ's missing-person panel shows images and detailed report/contact metadata with search, filters and expanded viewing.

Sources: [photo picker](../lib/core/widgets/photo_picker_field.dart), [PhotoCodec](../lib/services/photo_codec.dart), [donations](../lib/features/user/donations/donations_screen.dart), [report form](../lib/features/user/missing_persons/missing_person_form.dart), [HQ reports](../lib/features/admin/missing_persons/admin_missing_persons_view.dart).

Checks: [photo tests](../test/photo_codec_test.dart), [requested-update tests](../test/requested_updates_test.dart), [HQ missing-person tests](../test/admin_missing_persons_test.dart).

## Mission lifecycle and shared map state

Dispatch reserves the incident and unit together. Shared journey records provide route/timing inputs across portals. Completion closes the arrived incident and releases the unit atomically.

Cancellation follows the original request's eligibility across supported open stages, including assigned missions. The operation updates usage, closes the request, releases the applicable unit and stops the associated journey together.

Checks cover direct writes, ownership, related-unit release and stale-request safety.

Sources: [FirestoreService](../lib/services/firestore_service.dart), [RoutePlayback](../lib/models/route_playback.dart), [rules](../firestore.rules).

## Firebase and delivery

Android and web configuration target the configured Firebase project. The Android package uses `com.eeedhi`. HQ provisioning is provided through a trusted local utility; the administrator password remains private.

The repository includes reproducible platform source, rules, tests and the Android APK. Detailed setup and artifact information are in [Firebase setup](FIREBASE_SETUP_GUIDE.md) and [Build and deployment](BUILD_AND_DEPLOYMENT.md).

## Documentation publication

The documentation set now presents the overall platform, distributed architecture, data model, operating workflows, setup and recorded verification. The README includes a native project banner, portal comparison, architecture diagram, guide library and Android download.

[Acceptance report](ACCEPTANCE_TESTING_REPORT.md) records the verified checks. [CHANGELOG](../CHANGELOG.md) summarizes the published baseline.
