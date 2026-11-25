import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:edhiconnect_ai/models/app_user.dart';
import 'package:edhiconnect_ai/services/auth_service.dart';
import 'package:edhiconnect_ai/features/employee/dashboard/employee_dashboard_screen.dart';
import 'package:edhiconnect_ai/features/admin/fleet/driver_accountability_panel.dart';
import 'package:latlong2/latlong.dart';
import 'package:edhiconnect_ai/core/constants/app_constants.dart';
import 'package:edhiconnect_ai/core/constants/pakistan_cities.dart';
import 'package:edhiconnect_ai/models/dispatch_offer.dart';
import 'package:edhiconnect_ai/models/employee.dart';
import 'package:edhiconnect_ai/models/emergency_request.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';
import 'package:edhiconnect_ai/services/route_service.dart';

Future<RoadRouteResult> _road(LatLng start, LatLng end) async =>
    RoadRouteResult(
      points: [start, LatLng(end.latitude + .0001, end.longitude)],
      distanceKm: const Distance().as(LengthUnit.Meter, start, end) / 1000,
      etaMinutes: 2,
      durationSeconds: 120,
    );

const _near = Employee(
  employeeId: 'ack-near',
  userId: 'driver_mock_4',
  name: 'Near Driver',
  phone: '',
  vehicleNumber: 'ACK-NEAR',
  currentLat: 34.1990,
  currentLng: 73.2312,
);
const _far = Employee(
  employeeId: 'ack-far',
  userId: 'driver_mock_5',
  name: 'Far Driver',
  phone: '',
  vehicleNumber: 'ACK-FAR',
  currentLat: 34.2100,
  currentLng: 73.2312,
);

EmergencyRequest _patient(String uid) => EmergencyRequest(
  requestId: '',
  userId: uid,
  userPhone: '03001234569',
  emergencyType: 'Medical Emergency',
  description: 'Patient has severe chest pain and needs an ambulance',
  location: const RequestLocation(
    latitude: 34.1986,
    longitude: 73.2312,
    address: 'Supply Bazaar, Abbottabad',
  ),
);

class _Auth extends AuthService {
  final AppUser profile;
  _Auth(this.profile) : super(allowOffline: true);
  @override
  AppUser get currentUser => profile;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late FirestoreService service;
  var disposed = false;

  setUp(() async {
    disposed = false;
    now = DateTime(2026, 11, 25, 9);
    service = FirestoreService(
      roadLoader: _road,
      roadSnapper: (p) async => p,
      clock: () => now,
    );
    for (final open in await service.getRequestsStream().first) {
      if (![
        EmergencyStatus.completed,
        EmergencyStatus.cancelled,
      ].contains(open.status)) {
        await service.updateRequestStatus(
          open.requestId,
          EmergencyStatus.cancelled,
          adminOverride: true,
        );
      }
    }
    // Only the two test units are on duty.
    for (final unit in service.getAvailableDrivers()) {
      await service.toggleDriverAvailability(unit.employeeId, false);
    }
    // Move two registered driver accounts onto the test ambulances.
    for (final u in [_near, _far]) {
      await service.linkDriverAccount(u.userId, '');
      await service.addEmployee(u.copyWith(userId: ''));
      await service.linkDriverAccount(u.employeeId, u.userId);
    }
  });
  tearDown(() {
    if (!disposed) service.dispose();
  });

  Future<EmergencyRequest> job(String id) async =>
      (await service.getRequestStream(id).first)!;
  Employee unit(String id) =>
      service.getAllEmployees().firstWhere((e) => e.employeeId == id);
  DriverAccountability record(String id) =>
      service.driverAccountability().firstWhere((r) => r.unit.employeeId == id);

  test(
    'A driver with an account is offered the job instead of auto-assigned',
    () async {
      final id = await service.submitEmergencyRequest(_patient('c1'));
      await service.dispatchQueuedRequests();
      final offered = await job(id);
      expect(offered.status, EmergencyStatus.pending);
      expect(offered.offerEmployeeId, _near.employeeId);
      expect(unit(_near.employeeId).status, 'available');
      expect(unit(_near.employeeId).pendingOfferRequestId, id);
      final offer = service.pendingOfferForDriver(_near.userId)!;
      expect(offer.remaining(now), DispatchOffer.window);
      expect(offer.address, contains('Supply Bazaar'));
    },
  );

  test('Accepting starts the trip and counts as an active response', () async {
    final id = await service.submitEmergencyRequest(_patient('c2'));
    await service.dispatchQueuedRequests();
    now = now.add(const Duration(seconds: 12));
    await service.acceptDispatchOffer(
      service.pendingOfferForDriver(_near.userId)!.offerId,
    );
    final accepted = await job(id);
    expect(accepted.status, EmergencyStatus.inProgress);
    expect(accepted.assignedEmployeeId, _near.employeeId);
    expect(accepted.hasOffer, isFalse);
    expect(unit(_near.employeeId).status, 'busy');
    expect(service.isTransitActive(_near.employeeId), isTrue);
    final row = record(_near.employeeId);
    expect(row.accepted, 1);
    expect(row.missed, 0);
    expect(row.avgResponseSeconds, 12);
    expect(row.lastAcceptedAt, now);
  });

  test(
    'No answer in 60 s is a penalty and the next-nearest driver is asked',
    () async {
      final id = await service.submitEmergencyRequest(_patient('c3'));
      await service.dispatchQueuedRequests();
      now = now.add(const Duration(seconds: 59));
      await service.reconcileSimulations();
      expect((await job(id)).offerEmployeeId, _near.employeeId);

      now = now.add(const Duration(seconds: 4));
      await service.reconcileSimulations();
      final moved = await job(id);
      expect(moved.offerEmployeeId, _far.employeeId);
      expect(moved.skippedEmployeeIds, [_near.employeeId]);
      expect(record(_near.employeeId).missed, 1);
      expect(record(_near.employeeId).riskLevel, 'watch');
      expect(service.pendingOfferForDriver(_near.userId), isNull);
      expect(service.pendingOfferForDriver(_far.userId), isNotNull);
    },
  );

  test('Late acceptance after the window is refused', () async {
    await service.submitEmergencyRequest(_patient('c4'));
    await service.dispatchQueuedRequests();
    final offer = service.pendingOfferForDriver(_near.userId)!;
    now = now.add(const Duration(seconds: 61));
    await expectLater(
      service.acceptDispatchOffer(offer.offerId),
      throwsA(isA<StateError>()),
    );
  });

  test('Declining passes on at once and is not a penalty', () async {
    final id = await service.submitEmergencyRequest(_patient('c5'));
    await service.dispatchQueuedRequests();
    await service.declineDispatchOffer(
      service.pendingOfferForDriver(_near.userId)!.offerId,
    );
    await service.dispatchQueuedRequests();
    expect((await job(id)).offerEmployeeId, _far.employeeId);
    expect(record(_near.employeeId).declined, 1);
    expect(record(_near.employeeId).missed, 0);
    expect(unit(_near.employeeId).pendingOfferRequestId, isEmpty);
  });

  test('When everyone passes, HQ is alerted and the round restarts', () async {
    final id = await service.submitEmergencyRequest(_patient('c6'));
    await service.dispatchQueuedRequests();
    await service.declineDispatchOffer(
      service.pendingOfferForDriver(_near.userId)!.offerId,
    );
    await service.dispatchQueuedRequests();
    await service.declineDispatchOffer(
      service.pendingOfferForDriver(_far.userId)!.offerId,
    );
    await service.dispatchQueuedRequests(); // restarts the round
    await service.dispatchQueuedRequests(); // offers nearest again
    final restarted = await job(id);
    expect(restarted.dispatchAlert, isTrue);
    expect(restarted.offerEmployeeId, _near.employeeId);
    expect(restarted.offerAttempts, 3);
  });

  test('Cancelling during an offer closes it without a penalty', () async {
    final id = await service.submitEmergencyRequest(_patient('c7'));
    await service.dispatchQueuedRequests();
    await service.cancelEmergencyRequest(id, 'c7');
    expect(service.pendingOfferForDriver(_near.userId), isNull);
    expect(unit(_near.employeeId).pendingOfferRequestId, isEmpty);
    expect(record(_near.employeeId).missed, 0);
    expect(service.dispatchOffers.single.outcome, DispatchOffer.cancelled);
  });

  test('Units without a driver account still auto-accept instantly', () async {
    for (final u in [_near, _far]) {
      await service.toggleDriverAvailability(u.employeeId, false);
    }
    await service.addEmployee(
      const Employee(
        employeeId: 'auto-unit',
        userId: '',
        name: 'Virtual',
        phone: '',
        vehicleNumber: 'SIM-AUTO',
        currentLat: 34.2,
        currentLng: 73.233,
      ),
    );
    final id = await service.submitEmergencyRequest(_patient('c8'));
    await service.dispatchQueuedRequests();
    expect((await job(id)).status, EmergencyStatus.inProgress);
    expect(service.dispatchOffers, isEmpty);
  });

  test('A unit answering one offer is not offered a second patient', () async {
    final first = await service.submitEmergencyRequest(_patient('c9'));
    final second = await service.submitEmergencyRequest(
      _patient('c10').copyWith(userPhone: '03001234560'),
    );
    await service.dispatchQueuedRequests();
    final a = await job(first);
    final b = await job(second);
    expect(
      {a.offerEmployeeId, b.offerEmployeeId},
      {_near.employeeId, _far.employeeId},
    );
  });

  test(
    'Two misses in a row take a driver off duty; answering resets it',
    () async {
      final first = await service.submitEmergencyRequest(_patient('s1'));
      await service.dispatchQueuedRequests();
      now = now.add(const Duration(seconds: 63));
      await service.reconcileSimulations();
      expect(unit(_near.employeeId).missedStreak, 1);
      expect(unit(_near.employeeId).status, 'available');
      await service.updateRequestStatus(
        first,
        EmergencyStatus.cancelled,
        adminOverride: true,
      );
      await service.submitEmergencyRequest(
        _patient('s2').copyWith(userPhone: '03001234561'),
      );
      await service.dispatchQueuedRequests();
      expect(service.pendingOfferForDriver(_near.userId), isNotNull);
      now = now.add(const Duration(seconds: 63));
      await service.reconcileSimulations();
      final off = unit(_near.employeeId);
      expect(off.status, 'offline');
      expect(off.isAutoOffline, isTrue);
      expect(
        service.getAvailableDrivers().map((e) => e.employeeId),
        isNot(contains(_near.employeeId)),
      );
      await service.toggleDriverAvailability(_near.employeeId, true);
      expect(unit(_near.employeeId).isAutoOffline, isFalse);
      expect(unit(_near.employeeId).missedStreak, 0);
    },
  );

  test('Declining resets the missed streak', () async {
    await service.submitEmergencyRequest(_patient('s3'));
    await service.dispatchQueuedRequests();
    now = now.add(const Duration(seconds: 63));
    await service.reconcileSimulations();
    expect(unit(_near.employeeId).missedStreak, 1);
    await service.submitEmergencyRequest(
      _patient('s4').copyWith(userPhone: '03001234562'),
    );
    await service.dispatchQueuedRequests();
    await service.declineDispatchOffer(
      service.pendingOfferForDriver(_near.userId)!.offerId,
    );
    expect(unit(_near.employeeId).missedStreak, 0);
    expect(unit(_near.employeeId).status, 'available');
  });

  test('HQ can reset a driver\'s penalties', () async {
    await service.submitEmergencyRequest(_patient('c11'));
    await service.dispatchQueuedRequests();
    now = now.add(const Duration(seconds: 63));
    await service.reconcileSimulations();
    expect(record(_near.employeeId).missed, 1);
    now = now.add(const Duration(seconds: 1));
    await service.resetDriverPenalties(_near.employeeId);
    expect(record(_near.employeeId).missed, 0);
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets('Ringing offer fits $width px and Accept starts the job', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final id = await service.submitEmergencyRequest(_patient('w1'));
      await service.dispatchQueuedRequests();
      final auth = _Auth(
        const AppUser(
          id: 'driver_mock_4',
          name: 'Zubair Farooq',
          email: 'd@example.com',
          phone: '03459871234',
          role: 'employee',
        ),
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<FirestoreService>.value(value: service),
            ChangeNotifierProvider<AuthService>.value(value: auth),
          ],
          child: const MaterialApp(home: EmployeeDashboardScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('NEW EMERGENCY · RESPOND NOW'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('acceptOffer')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect((await job(id)).status, EmergencyStatus.inProgress);
      expect(find.text('NEW EMERGENCY · RESPOND NOW'), findsNothing);
      expect(find.text('Your response record'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      service.dispose(); // stops the journey ticker inside the fake clock
      disposed = true;
    });

    testWidgets('HQ accountability table fits $width px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await service.submitEmergencyRequest(_patient('w2'));
      await service.dispatchQueuedRequests();
      now = now.add(const Duration(seconds: 63));
      await service.reconcileSimulations();
      await tester.pumpWidget(
        ChangeNotifierProvider<FirestoreService>.value(
          value: service,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: DriverAccountabilityPanel()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Driver accountability'), findsOneWidget);
      expect(find.text('Zubair Farooq'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Zubair Farooq'));
      await tester.pumpAndSettle();
      expect(find.text('MISSED'), findsOneWidget);
      expect(find.text('Reset penalties'), findsOneWidget);
    });
  }

  group('Cities', () {
    test('Free text maps onto the fixed list', () {
      expect(PakistanCities.normalize(' lahore '), 'Lahore');
      expect(PakistanCities.normalize('LHR'), 'Lahore');
      expect(PakistanCities.normalize('G-9, Islamabad'), 'Islamabad');
      expect(PakistanCities.normalize('Pindi'), 'Rawalpindi');
      expect(PakistanCities.normalize('Atlantis'), '');
      expect(PakistanCities.label(''), PakistanCities.notSet);
    });

    test('GPS resolves to the nearest listed city', () {
      expect(PakistanCities.nearest(34.1986, 73.2312), 'Abbottabad');
      expect(PakistanCities.nearest(24.90, 67.08), 'Karachi');
      expect(PakistanCities.nearest(0, 0), isNull);
      expect(PakistanCities.nearest(51.5, -0.12), isNull);
    });

    test('Counts group by city, biggest first', () {
      final counts = PakistanCities.countBy<String>([
        'Lahore',
        'lahore',
        'Karachi',
        '',
      ], (c) => c);
      expect(counts.first.key, 'Lahore');
      expect(counts.first.value, 2);
      expect(counts.map((e) => e.key), contains(PakistanCities.notSet));
    });

    test('New emergencies record the city of the patient pin', () async {
      final id = await service.submitEmergencyRequest(_patient('c12'));
      expect((await job(id)).city, 'Abbottabad');
    });
  });
}
