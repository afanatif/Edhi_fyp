import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:edhiconnect_ai/core/constants/app_constants.dart';
import 'package:edhiconnect_ai/models/emergency_request.dart';
import 'package:edhiconnect_ai/models/emergency_usage.dart';
import 'package:edhiconnect_ai/models/employee.dart';
import 'package:edhiconnect_ai/models/route_playback.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';

EmergencyRequest requestFor(String uid, {DateTime? createdAt}) =>
    EmergencyRequest(
      requestId: '',
      userId: uid,
      userPhone: '+923001234567',
      emergencyType: 'Medical Emergency',
      location: const RequestLocation(
        latitude: 34.1986,
        longitude: 73.2312,
        address: 'Patient confirmed pin',
      ),
      description: 'Patient requires urgent medical help',
      createdAt: createdAt,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 2, 12);
  test(
    'Cancellation closes at 60 seconds, including assigned and moving jobs',
    () {
      final request = requestFor('citizen', createdAt: now);
      expect(EmergencyUsage.canCancel(request, now), isTrue);
      expect(
        EmergencyUsage.canCancel(
          request,
          now.add(const Duration(milliseconds: 59999)),
        ),
        isTrue,
      );
      expect(
        EmergencyUsage.canCancel(request, now.add(const Duration(seconds: 60))),
        isFalse,
      );
      expect(
        EmergencyUsage.canCancel(
          request,
          now.subtract(const Duration(seconds: 1)),
        ),
        isFalse,
      );
      expect(EmergencyUsage.canCancel(requestFor('citizen'), now), isFalse);
      for (final status in [
        EmergencyStatus.pending,
        EmergencyStatus.approved,
        EmergencyStatus.assigned,
        EmergencyStatus.inProgress,
        EmergencyStatus.arrived,
      ]) {
        final assigned = request.copyWith(
          status: status,
          updatedAt: now.add(const Duration(seconds: 50)),
        );
        expect(
          EmergencyUsage.canCancel(
            assigned,
            now.add(const Duration(seconds: 59)),
          ),
          isTrue,
        );
        expect(
          EmergencyUsage.canCancel(
            assigned,
            now.add(const Duration(seconds: 60)),
          ),
          isFalse,
        );
        expect(
          EmergencyUsage.remaining(
            assigned,
            now.add(const Duration(seconds: 59)),
          ),
          const Duration(seconds: 1),
        );
      }
      for (final status in [
        EmergencyStatus.completed,
        EmergencyStatus.cancelled,
      ]) {
        expect(
          EmergencyUsage.canCancel(request.copyWith(status: status), now),
          isFalse,
        );
      }
    },
  );
  test('Third cancellation bans for 24 hours and resets after expiry', () {
    var usage = const EmergencyUsage();
    for (var i = 0; i < 3; i++) {
      usage = usage.afterCancellation(now.add(Duration(minutes: i)));
    }
    expect(usage.cancellationCount, 3);
    expect(usage.isBanned(now.add(const Duration(hours: 24))), isTrue);
    expect(
      usage.isBanned(now.add(const Duration(hours: 24, minutes: 2))),
      isFalse,
    );
    expect(
      usage
          .afterCancellation(now.add(const Duration(hours: 24, minutes: 2)))
          .cancellationCount,
      1,
    );
  });
  test('Counter resets after the 24-hour counting window', () {
    final usage = const EmergencyUsage()
        .afterCancellation(now)
        .afterCancellation(now.add(const Duration(minutes: 1)));
    expect(usage.countAt(now.add(const Duration(hours: 24))), 0);
    expect(
      usage
          .afterCancellation(now.add(const Duration(hours: 24)))
          .cancellationCount,
      1,
    );
  });
  test(
    'Service counts once per cancellation, isolates owners, blocks a fourth request',
    () async {
      final service = FirestoreService(automaticSimulation: false);
      addTearDown(service.dispose);
      for (var i = 1; i <= 3; i++) {
        final id = await service.submitEmergencyRequest(
          requestFor('policy-user'),
        );
        await expectLater(
          service.cancelEmergencyRequest(id, 'wrong-user'),
          throwsStateError,
        );
        final usage = await service.cancelEmergencyRequest(id, 'policy-user');
        expect(usage.cancellationCount, i);
        await expectLater(
          service.cancelEmergencyRequest(id, 'policy-user'),
          throwsStateError,
        );
      }
      await expectLater(
        service.submitEmergencyRequest(requestFor('policy-user')),
        throwsStateError,
      );
      expect(
        await service.submitEmergencyRequest(requestFor('other-user')),
        isNotEmpty,
      );
    },
  );
  test(
    'Double assignment and cancellation after completion are rejected',
    () async {
      final service = FirestoreService(automaticSimulation: false);
      addTearDown(service.dispose);
      final id = await service.submitEmergencyRequest(requestFor('trip-user'));
      final driver = service.getAvailableDrivers().first;
      await service.assignRequest(
        requestId: id,
        employeeId: driver.employeeId,
        employeeName: driver.name,
      );
      final second = await service.submitEmergencyRequest(
        requestFor('different-user'),
      );
      await expectLater(
        service.assignRequest(
          requestId: second,
          employeeId: driver.employeeId,
          employeeName: driver.name,
        ),
        throwsStateError,
      );
      await service.updateRequestStatus(id, EmergencyStatus.inProgress);
      await service.updateRequestStatus(id, EmergencyStatus.arrived);
      expect(
        service
            .getAllEmployees()
            .firstWhere((e) => e.employeeId == driver.employeeId)
            .status,
        'busy',
      );
      await service.updateRequestStatus(id, EmergencyStatus.completed);
      await expectLater(
        service.cancelEmergencyRequest(id, 'trip-user'),
        throwsStateError,
      );
      expect(
        (await service.getEmergencyUsage('trip-user')).cancellationCount,
        0,
      );
      expect(
        service
            .getAllEmployees()
            .firstWhere((e) => e.employeeId == driver.employeeId)
            .status,
        'available',
      );
    },
  );
  for (final status in [
    EmergencyStatus.assigned,
    EmergencyStatus.inProgress,
    EmergencyStatus.arrived,
  ]) {
    test(
      'Cancelling $status clears the reservation once and permits redispatch',
      () async {
        var clock = now;
        final service = FirestoreService(
          automaticSimulation: false,
          clock: () => clock,
        );
        addTearDown(service.dispose);
        final id = await service.submitEmergencyRequest(
          requestFor('cancel-$status'),
        );
        final driver = service.getAvailableDrivers().first;
        clock = clock.add(const Duration(seconds: 30));
        await service.assignRequest(
          requestId: id,
          employeeId: driver.employeeId,
          employeeName: driver.name,
        );
        if (status != EmergencyStatus.assigned) {
          await service.updateRequestStatus(id, EmergencyStatus.inProgress);
          if (status == EmergencyStatus.arrived) {
            await service.updateRequestStatus(id, status);
          }
        }
        clock = clock.add(const Duration(seconds: 29));
        final usage = await service.cancelEmergencyRequest(
          id,
          'cancel-$status',
        );
        expect(usage.cancellationCount, 1);
        expect(
          (await service.getRequestStream(id).first)!.status,
          EmergencyStatus.cancelled,
        );
        final released = service.getAllEmployees().firstWhere(
          (e) => e.employeeId == driver.employeeId,
        );
        expect(released.status, 'available');
        expect(released.activeRequestId, isEmpty);
        expect(released.speedKmh, 0);
        await expectLater(
          service.cancelEmergencyRequest(id, 'cancel-$status'),
          throwsStateError,
        );
        final next = await service.submitEmergencyRequest(
          requestFor('next-$status'),
        );
        await service.assignRequest(
          requestId: next,
          employeeId: driver.employeeId,
          employeeName: driver.name,
        );
        expect(
          service
              .getAllEmployees()
              .firstWhere((e) => e.employeeId == driver.employeeId)
              .activeRequestId,
          next,
        );
      },
    );
    test(
      'Assigning at 59 seconds does not extend the cancellation deadline for $status',
      () async {
        var clock = now;
        final service = FirestoreService(
          automaticSimulation: false,
          clock: () => clock,
        );
        addTearDown(service.dispose);
        final id = await service.submitEmergencyRequest(
          requestFor('expired-$status'),
        );
        final driver = service.getAvailableDrivers().first;
        clock = clock.add(const Duration(seconds: 59));
        await service.assignRequest(
          requestId: id,
          employeeId: driver.employeeId,
          employeeName: driver.name,
        );
        if (status != EmergencyStatus.assigned) {
          await service.updateRequestStatus(id, EmergencyStatus.inProgress);
          if (status == EmergencyStatus.arrived) {
            await service.updateRequestStatus(id, status);
          }
        }
        clock = clock.add(const Duration(seconds: 1));
        await expectLater(
          service.cancelEmergencyRequest(id, 'expired-$status'),
          throwsStateError,
        );
        expect(
          (await service.getEmergencyUsage(
            'expired-$status',
          )).cancellationCount,
          0,
        );
        expect((await service.getRequestStream(id).first)!.status, status);
        expect(
          service
              .getAllEmployees()
              .firstWhere((e) => e.employeeId == driver.employeeId)
              .status,
          'busy',
        );
      },
    );
  }
  test(
    'Route playback moves by distance, is deterministic across clients and ends safely',
    () {
      final points = [
        const LatLng(34, 73),
        const LatLng(34, 73.001),
        const LatLng(34, 73.01),
      ];
      final demo = RoutePlayback(
        requestId: 'job',
        points: points,
        startedAt: now,
        durationSeconds: 100,
      );
      final mirror = RoutePlayback(
        requestId: 'job',
        points: points,
        startedAt: now,
        durationSeconds: 100,
      );
      expect(
        demo.positionAt(now.subtract(const Duration(seconds: 5))),
        points.first,
      );
      final halfway = demo.positionAt(now.add(const Duration(seconds: 50)))!;
      expect(halfway.longitude, closeTo(73.005, 0.00001));
      expect(mirror.positionAt(now.add(const Duration(seconds: 50))), halfway);
      expect(
        demo.positionAt(now.add(const Duration(seconds: 500))),
        points.last,
      );
      expect(demo.movingAt(now.add(const Duration(seconds: 100))), isFalse);
      expect(
        RoutePlayback(
          requestId: 'job',
          points: points,
          startedAt: now,
          durationSeconds: 100,
          enabled: false,
        ).positionAt(now),
        isNull,
      );
    },
  );
  test('Unknown/stale/demo locations cannot claim fresh GPS', () {
    const unknown = Employee(
      employeeId: 'unit',
      userId: 'driver',
      name: 'Driver',
      phone: '115',
    );
    expect(unknown.hasValidLocation, isFalse);
    final live = unknown.copyWith(
      isSimulated: false,
      currentLat: 34,
      currentLng: 73,
      locationUpdatedAt: now,
    );
    expect(live.hasFreshGps(now.add(const Duration(seconds: 89))), isTrue);
    expect(live.hasFreshGps(now.add(const Duration(seconds: 90))), isFalse);
    expect(live.copyWith(isDemo: true).hasFreshGps(now), isFalse);
    expect(live.copyWith(currentLat: 91).hasValidLocation, isFalse);
  });
  test(
    'Directory has sourced offices without fabricated coordinates or fleet counts',
    () {
      final service = FirestoreService(automaticSimulation: false);
      addTearDown(service.dispose);
      final centers = service.getEdhiCenters();
      expect(centers.length, 7);
      expect(
        centers.every(
          (c) =>
              c.sourceUrl != null && c.ambulanceCount == 0 && !c.hasCoordinates,
        ),
        isTrue,
      );
      expect(service.findNearestAvailableAmbulance(0, 0), isNull);
    },
  );
}
