import 'dart:async';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:edhiconnect_ai/core/constants/app_constants.dart';
import 'package:edhiconnect_ai/models/employee.dart';
import 'package:edhiconnect_ai/models/emergency_request.dart';
import 'package:edhiconnect_ai/models/route_playback.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';
import 'package:edhiconnect_ai/services/route_service.dart';

EmergencyRequest _patient(String uid) => EmergencyRequest(
  requestId: '',
  userId: uid,
  emergencyType: 'Medical Emergency',
  description: 'Simulation test patient',
  location: const RequestLocation(
    latitude: 34.1986,
    longitude: 73.2312,
    address: 'Confirmed patient pin',
  ),
);

// An explicitly injected route fixture: tests never depend on public routing.
Future<RoadRouteResult> _road(LatLng start, LatLng end) async =>
    RoadRouteResult(
      points: [start, LatLng(end.latitude + .0001, end.longitude)],
      distanceKm: const Distance().as(LengthUnit.Meter, start, end) / 1000,
      etaMinutes: 2,
      durationSeconds: 120,
    );

const _virtualDriver = Employee(
  employeeId: 'virtual-test',
  userId: '',
  name: 'Virtual Driver',
  phone: '',
  vehicleNumber: 'SIM-TEST',
  currentLat: 34.2,
  currentLng: 73.233,
  isSimulated: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late FirestoreService service;
  setUp(() {
    now = DateTime(2026, 10, 2, 14);
    service = FirestoreService(
      roadLoader: _road,
      roadSnapper: (p) async => p,
      clock: () => now,
    );
  });
  tearDown(() => service.dispose());
  Future<String> dispatch() async {
    await service.addEmployee(_virtualDriver);
    final id = await service.submitEmergencyRequest(
      _patient('simulation-citizen'),
    );
    await service.assignRequest(
      requestId: id,
      employeeId: _virtualDriver.employeeId,
      employeeName: _virtualDriver.name,
    );
    return id;
  }

  Employee unit() => service.getAllEmployees().firstWhere(
    (e) => e.employeeId == _virtualDriver.employeeId,
  );

  Future<void> emptyDispatchPool() async {
    for (final job in await service.getRequestsStream().first) {
      if (![
        EmergencyStatus.completed,
        EmergencyStatus.cancelled,
      ].contains(job.status)) {
        await service.updateRequestStatus(
          job.requestId,
          EmergencyStatus.cancelled,
          adminOverride: true,
        );
      }
    }
    for (final driver in service.getAvailableDrivers()) {
      await service.toggleDriverAvailability(driver.employeeId, false);
    }
  }

  test(
    'Cancellation inside one minute freezes the running route and releases its unit',
    () async {
      final id = await dispatch();
      now = now.add(const Duration(seconds: 30));
      final before = service.getTransitPlayback(_virtualDriver.employeeId);
      final position = before!.positionAt(now)!;
      expect(
        (await service.getRequestStream(id).first)!.status,
        EmergencyStatus.inProgress,
      );
      await service.cancelEmergencyRequest(id, 'simulation-citizen');
      final stopped = service.getTransitPlayback(_virtualDriver.employeeId)!;
      expect(stopped.enabled, isFalse);
      expect(stopped.stoppedAt, now);
      expect(unit().status, 'available');
      expect(unit().activeRequestId, isEmpty);
      now = now.add(const Duration(minutes: 10));
      await service.reconcileSimulations();
      expect(stopped.positionAt(now), position);
      expect(unit().currentLat, closeTo(position.latitude, 0.000001));
      expect(unit().currentLng, closeTo(position.longitude, 0.000001));
      expect(
        (await service.getRequestStream(id).first)!.status,
        EmergencyStatus.cancelled,
      );
    },
  );

  test(
    'Queue waits for units, assigns multiple jobs uniquely and uses released units',
    () async {
      await emptyDispatchPool();
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        ids.add(
          await service.submitEmergencyRequest(
            _patient('queue-$i').copyWith(
              userPhone: '0300123456$i',
              description:
                  'Patient has a painful injury and needs ambulance assistance',
              location: RequestLocation(
                latitude: 34.1986 + i * .005,
                longitude: 73.2312,
                address: 'Confirmed pin $i',
              ),
            ),
          ),
        );
      }
      await service.dispatchQueuedRequests();
      expect(
        (await service.getRequestStream(ids.first).first)!.status,
        EmergencyStatus.pending,
      );
      await service.addEmployee(_virtualDriver);
      await service.addEmployee(
        _virtualDriver.copyWith(
          employeeId: 'second',
          vehicleNumber: 'SIM-SECOND',
          currentLat: 34.21,
        ),
      );
      await Future.wait([
        service.dispatchQueuedRequests(),
        service.dispatchQueuedRequests(),
      ]);
      final jobs = await Future.wait(
        ids.map((id) => service.getRequestStream(id).first),
      );
      final moving = jobs
          .where((r) => r!.status == EmergencyStatus.inProgress)
          .toList();
      expect(moving.length, 2);
      expect(moving.map((r) => r!.assignedEmployeeId).toSet().length, 2);
      final waiting = jobs.firstWhere(
        (r) => r!.status == EmergencyStatus.pending,
      )!;
      now = now.add(const Duration(seconds: 125));
      await service.reconcileSimulations();
      final finished = moving.first!;
      await service.updateRequestStatus(
        finished.requestId,
        EmergencyStatus.completed,
      );
      await service.dispatchQueuedRequests();
      final dispatched = (await service
          .getRequestStream(waiting.requestId)
          .first)!;
      expect(dispatched.status, EmergencyStatus.inProgress);
      expect(dispatched.assignedEmployeeId, finished.assignedEmployeeId);
    },
  );

  test(
    'Critical calls take precedence, and high-risk calls wait for verification',
    () async {
      await emptyDispatchPool();
      final ordinary = await service.submitEmergencyRequest(
        _patient('ordinary').copyWith(
          description: 'Patient needs medical transport for a painful sprain',
          userPhone: '03001234561',
        ),
      );
      final critical = await service.submitEmergencyRequest(
        _patient('critical').copyWith(
          emergencyType: 'Cardiac Arrest',
          description: 'Patient unconscious not breathing cardiac arrest',
          userPhone: '03001234562',
        ),
      );
      final flagged = await service.submitEmergencyRequest(
        _patient('flagged').copyWith(
          description: 'fake prank call joke testing lol',
          userPhone: '03001234563',
        ),
      );
      await service.addEmployee(_virtualDriver);
      await service.dispatchQueuedRequests();
      expect(
        (await service.getRequestStream(critical).first)!.status,
        EmergencyStatus.inProgress,
      );
      expect(
        (await service.getRequestStream(ordinary).first)!.status,
        EmergencyStatus.pending,
      );
      expect(
        (await service.getRequestStream(flagged).first)!.status,
        EmergencyStatus.pending,
      );
    },
  );

  test(
    'Only the linked driver completes an arrived response and streams agree',
    () async {
      final registered = (await service.getUsersStream().first).firstWhere(
        (u) =>
            u.isEmployee &&
            u.isActive &&
            !service.getAllEmployees().any(
              (e) => e.userId == u.id && e.status == 'busy',
            ),
      );
      final previous = service
          .getAllEmployees()
          .where((e) => e.userId == registered.id)
          .firstOrNull;
      if (previous != null) {
        await service.linkDriverAccount(previous.employeeId, '');
      }
      await service.addEmployee(_virtualDriver);
      await service.linkDriverAccount(unit().employeeId, registered.id);
      expect(unit().userId, registered.id);
      await expectLater(
        service.linkDriverAccount(unit().employeeId, 'unknown'),
        throwsStateError,
      );
      final id = await service.submitEmergencyRequest(
        _patient('simulation-citizen'),
      );
      await service.assignRequest(
        requestId: id,
        employeeId: unit().employeeId,
        employeeName: unit().name,
      );
      await expectLater(
        service.completeDriverResponse(id, registered.id),
        throwsStateError,
      );
      await expectLater(
        service.linkDriverAccount(unit().employeeId, ''),
        throwsStateError,
      );
      now = now.add(const Duration(seconds: 125));
      await service.reconcileSimulations();
      await expectLater(
        service.completeDriverResponse(id, 'other-driver'),
        throwsStateError,
      );
      await service.completeDriverResponse(id, registered.id);
      expect(
        (await service.getRequestStream(id).first)!.status,
        EmergencyStatus.completed,
      );
      expect(
        (await service.getEmployeesStream().first)
            .firstWhere((e) => e.employeeId == unit().employeeId)
            .status,
        'available',
      );
      expect(await service.completeDriverResponse(id, registered.id), isFalse);
    },
  );

  test(
    'Creating an ambulance assigns a registered driver and rejects duplicate links',
    () async {
      final previous = service.getAllEmployees().firstWhere(
        (e) => e.status != 'busy' && e.userId.isNotEmpty,
      );
      final driver = (await service.getUsersStream().first).firstWhere(
        (u) => u.id == previous.userId,
      );
      await service.linkDriverAccount(previous.employeeId, '');
      final count = service.getAllEmployees().length;
      final id = await service.addEmployee(
        _virtualDriver.copyWith(userId: driver.id),
      );
      final added = service.getAllEmployees().firstWhere(
        (e) => e.employeeId == id,
      );
      expect(added.userId, driver.id);
      expect(added.name, driver.name);
      expect(added.phone, driver.phone);
      expect(service.getAllEmployees().length, count + 1);
      await expectLater(
        service.addEmployee(
          _virtualDriver.copyWith(
            employeeId: 'duplicate-driver-unit',
            vehicleNumber: 'DUP-123',
            userId: driver.id,
          ),
        ),
        throwsStateError,
      );
      expect(service.getAllEmployees().length, count + 1);
      await expectLater(
        service.addEmployee(
          _virtualDriver.copyWith(
            employeeId: 'unknown-driver-unit',
            vehicleNumber: 'UNKNOWN-123',
            userId: 'unknown',
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        service.addEmployee(
          _virtualDriver.copyWith(
            employeeId: 'citizen-driver-unit',
            vehicleNumber: 'CITIZEN-123',
            userId: 'user_mock_1',
          ),
        ),
        throwsStateError,
      );
      await service.linkDriverAccount(id, '');
      await service.updateUserStatus(driver.id, false);
      await expectLater(
        service.addEmployee(
          _virtualDriver.copyWith(
            employeeId: 'inactive-driver-unit',
            vehicleNumber: 'INACTIVE-123',
            userId: driver.id,
          ),
        ),
        throwsStateError,
      );
      expect(service.getAllEmployees().length, count + 1);
    },
  );

  test(
    'Citizen confirms only their own arrived response and clears the assignment',
    () async {
      final id = await dispatch();
      await expectLater(
        service.completeCitizenResponse(id, 'simulation-citizen'),
        throwsStateError,
      );
      now = now.add(const Duration(seconds: 125));
      await service.reconcileSimulations();
      await expectLater(
        service.completeCitizenResponse(id, 'another-citizen'),
        throwsStateError,
      );
      expect(unit().status, 'busy');
      expect(unit().activeRequestId, id);
      expect(
        await service.completeCitizenResponse(id, 'simulation-citizen'),
        isTrue,
      );
      expect(
        (await service.getRequestStream(id).first)!.status,
        EmergencyStatus.completed,
      );
      expect(unit().status, 'available');
      expect(unit().activeRequestId, isEmpty);
      expect(unit().speedKmh, 0);
      expect(service.isTransitActive(unit().employeeId), isFalse);
      expect(
        await service.completeCitizenResponse(id, 'simulation-citizen'),
        isFalse,
      );
    },
  );

  test(
    'Citizen and driver simultaneous confirmation releases a job once',
    () async {
      await emptyDispatchPool();
      final registered = (await service.getUsersStream().first).firstWhere(
        (u) => u.isEmployee && u.isActive,
      );
      final previous = service
          .getAllEmployees()
          .where((e) => e.userId == registered.id)
          .firstOrNull;
      if (previous != null) {
        await service.linkDriverAccount(previous.employeeId, '');
      }
      final id = await dispatch();
      // Link before reserving: busy units cannot be relinked.
      await service.updateRequestStatus(
        id,
        EmergencyStatus.cancelled,
        adminOverride: true,
      );
      await service.linkDriverAccount(unit().employeeId, registered.id);
      final activeId = await service.submitEmergencyRequest(
        _patient('simulation-citizen'),
      );
      await service.assignRequest(
        requestId: activeId,
        employeeId: unit().employeeId,
        employeeName: unit().name,
      );
      now = now.add(const Duration(seconds: 125));
      await service.reconcileSimulations();
      final results = await Future.wait([
        service.completeCitizenResponse(activeId, 'simulation-citizen'),
        service.completeDriverResponse(activeId, registered.id),
      ]);
      expect(results.where((result) => result), hasLength(1));
      expect(unit().status, 'available');
      expect(unit().activeRequestId, isEmpty);
    },
  );

  test(
    'Repeating an old confirmation cannot release the next patient’s ambulance',
    () async {
      final id = await dispatch();
      now = now.add(const Duration(seconds: 125));
      await service.reconcileSimulations();
      await service.completeCitizenResponse(id, 'simulation-citizen');
      final next = await service.submitEmergencyRequest(
        _patient('next-citizen'),
      );
      await service.assignRequest(
        requestId: next,
        employeeId: unit().employeeId,
        employeeName: unit().name,
      );
      expect(
        await service.completeCitizenResponse(id, 'simulation-citizen'),
        isFalse,
      );
      expect(unit().activeRequestId, next);
      expect(unit().status, 'busy');
      expect(service.getTransitPlayback(unit().employeeId)!.requestId, next);
      expect(service.isTransitActive(unit().employeeId), isTrue);
    },
  );

  test(
    'Admin reconciles an unambiguous arrived legacy assignment before citizen completion',
    () async {
      final legacy = (await service.getRequestsStream().first).firstWhere(
        (r) => r.status == EmergencyStatus.assigned,
      );
      final driver = service.getAllEmployees().firstWhere(
        (e) => e.employeeId == legacy.assignedEmployeeId,
      );
      expect(driver.activeRequestId, isEmpty);
      await service.updateRequestStatus(
        legacy.requestId,
        EmergencyStatus.inProgress,
      );
      await service.updateRequestStatus(
        legacy.requestId,
        EmergencyStatus.arrived,
      );
      await service.reconcileSimulations();
      expect(
        service
            .getAllEmployees()
            .firstWhere((e) => e.employeeId == driver.employeeId)
            .activeRequestId,
        legacy.requestId,
      );
      expect(
        await service.completeCitizenResponse(legacy.requestId, legacy.userId),
        isTrue,
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

  test(
    'Map assignment uses the reservation, not the first historical job',
    () async {
      final old = _patient('old').copyWith(
        requestId: 'old',
        assignedEmployeeId: 'unit',
        status: EmergencyStatus.arrived,
      );
      final current = old.copyWith(
        requestId: 'current',
        status: EmergencyStatus.inProgress,
      );
      final employee = _virtualDriver.copyWith(
        employeeId: 'unit',
        status: 'busy',
        activeRequestId: 'current',
      );
      expect(
        service.getCurrentAssignment(employee, [old, current])?.requestId,
        'current',
      );
      expect(
        service.getCurrentAssignment(employee.copyWith(activeRequestId: ''), [
          old,
          current,
        ]),
        isNull,
      );
      expect(
        service.getCurrentAssignment(
          employee.copyWith(activeRequestId: 'different'),
          [old, current],
        ),
        isNull,
      );
      expect(
        service.getCurrentAssignment(employee.copyWith(status: 'available'), [
          old,
          current,
        ]),
        isNull,
      );
    },
  );

  test('A registered driver cannot be linked to two ambulances', () async {
    final registered = (await service.getUsersStream().first).firstWhere(
      (u) =>
          u.isEmployee &&
          u.isActive &&
          !service.getAllEmployees().any(
            (e) => e.userId == u.id && e.status == 'busy',
          ),
    );
    final previous = service
        .getAllEmployees()
        .where((e) => e.userId == registered.id)
        .firstOrNull;
    if (previous != null) {
      await service.linkDriverAccount(previous.employeeId, '');
    }
    await service.addEmployee(_virtualDriver);
    await service.addEmployee(
      _virtualDriver.copyWith(
        employeeId: 'second',
        vehicleNumber: 'SIM-SECOND',
      ),
    );
    await service.linkDriverAccount(unit().employeeId, registered.id);
    await expectLater(
      service.linkDriverAccount('second', registered.id),
      throwsStateError,
    );
    await service.linkDriverAccount(unit().employeeId, '');
    await service.linkDriverAccount('second', registered.id);
    expect(
      service
          .getAllEmployees()
          .firstWhere((e) => e.employeeId == 'second')
          .userId,
      registered.id,
    );
  });

  test(
    'Virtual driver has no account, stays parked, and cannot claim device GPS',
    () async {
      await service.addEmployee(_virtualDriver);
      final first = unit();
      expect(first.userId, isEmpty);
      expect(first.status, 'available');
      expect(first.isSimulated, isTrue);
      expect(first.hasFreshGps(now), isFalse);
      now = now.add(const Duration(hours: 2));
      expect(unit().currentLat, first.currentLat);
      expect(service.isTransitActive(first.employeeId), isFalse);
      await expectLater(
        service.addEmployee(
          _virtualDriver.copyWith(employeeId: 'different-id'),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'Assignment automatically moves on the saved road and reaches its endpoint',
    () async {
      final id = await dispatch();
      expect(
        (await service.getRequestStream(id).first)!.status,
        EmergencyStatus.inProgress,
      );
      expect(unit().status, 'busy');
      await expectLater(
        service.deleteEmployee(unit().employeeId),
        throwsStateError,
      );
      await expectLater(
        service.toggleDriverAvailability(unit().employeeId, true),
        throwsStateError,
      );
      final initial = unit().currentLat;
      now = now.add(const Duration(seconds: 60));
      expect(unit().currentLat, isNot(initial));
      final playback = service.getTransitPlayback(unit().employeeId)!;
      expect(playback.progressAt(now), closeTo(.5, .001));
      expect(playback.remainingSecondsAt(now), 60);
      now = now.add(const Duration(seconds: 60));
      await service.reconcileSimulations();
      expect(
        (await service.getRequestStream(id).first)!.status,
        EmergencyStatus.inProgress,
      );
      now = now.add(const Duration(milliseconds: 4999));
      await service.reconcileSimulations();
      expect(
        (await service.getRequestStream(id).first)!.status,
        EmergencyStatus.inProgress,
      );
      now = now.add(const Duration(milliseconds: 1));
      await service.reconcileSimulations();
      expect(
        (await service.getRequestStream(id).first)!.status,
        EmergencyStatus.arrived,
      );
      expect(unit().currentLat, playback.points.last.latitude);
      expect(unit().speedKmh, 0);
      expect(unit().status, 'busy');
      await service.updateRequestStatus(id, EmergencyStatus.completed);
      expect(unit().status, 'available');
      expect(unit().currentLat, playback.points.last.latitude);
    },
  );

  test(
    'Pause, speed change while paused and resume never jump or restart',
    () async {
      final id = await dispatch();
      now = now.add(const Duration(seconds: 30));
      final before = LatLng(unit().currentLat, unit().currentLng);
      await service.pauseOrResumeTransit(unit().employeeId);
      now = now.add(const Duration(minutes: 10));
      expect(LatLng(unit().currentLat, unit().currentLng), before);
      await service.setTransitSpeed(unit().employeeId, 10);
      expect(service.isTransitPaused(unit().employeeId), isTrue);
      expect(LatLng(unit().currentLat, unit().currentLng), before);
      expect(
        service.getTransitPlayback(unit().employeeId)!.durationSeconds,
        closeTo(9, .001),
      );
      await service.reconcileSimulations();
      expect(
        (await service.getRequestStream(id).first)!.status,
        EmergencyStatus.inProgress,
      );
      await service.pauseOrResumeTransit(unit().employeeId);
      expect(LatLng(unit().currentLat, unit().currentLng), before);
      now = now.add(const Duration(seconds: 14));
      await service.reconcileSimulations();
      expect(
        (await service.getRequestStream(id).first)!.status,
        EmergencyStatus.arrived,
      );
    },
  );

  test(
    '10x changes playback time, not the physical road-speed display',
    () async {
      service.setDefaultSimulationSpeed(10);
      await dispatch();
      final fast = service.getTransitPlayback(unit().employeeId)!;
      expect(fast.durationSeconds, 12);
      final normal = RoutePlayback(
        requestId: fast.requestId,
        points: fast.points,
        startedAt: fast.startedAt,
        durationSeconds: 120,
      );
      expect(fast.estimatedSpeedKmh, normal.estimatedSpeedKmh);
      expect(() => service.setDefaultSimulationSpeed(100), throwsArgumentError);
      await expectLater(
        service.setTransitSpeed(unit().employeeId, 2),
        throwsArgumentError,
      );
    },
  );

  test(
    'Next assignment starts from the endpoint, not the old staging point',
    () async {
      final id = await dispatch();
      now = now.add(const Duration(seconds: 125));
      await service.reconcileSimulations();
      await service.updateRequestStatus(id, EmergencyStatus.completed);
      final parked = LatLng(unit().currentLat, unit().currentLng);
      final second = await service.submitEmergencyRequest(
        _patient('second-citizen'),
      );
      await service.assignRequest(
        requestId: second,
        employeeId: unit().employeeId,
        employeeName: unit().name,
      );
      expect(
        service.getTransitPlayback(unit().employeeId)!.points.first,
        parked,
      );
    },
  );

  test(
    'Unavailable road leaves the request pending and ambulance available',
    () async {
      final failing = FirestoreService(
        roadLoader: (start, end) async => RoadRouteResult(
          points: [start, end],
          distanceKm: 1,
          etaMinutes: 2,
          isRealRoadRoute: false,
        ),
      );
      addTearDown(failing.dispose);
      await failing.addEmployee(_virtualDriver);
      final id = await failing.submitEmergencyRequest(_patient('road-failure'));
      await expectLater(
        failing.assignRequest(
          requestId: id,
          employeeId: _virtualDriver.employeeId,
          employeeName: _virtualDriver.name,
        ),
        throwsStateError,
      );
      expect(
        (await failing.getRequestStream(id).first)!.status,
        EmergencyStatus.pending,
      );
      expect(
        failing
            .getAllEmployees()
            .firstWhere((e) => e.employeeId == _virtualDriver.employeeId)
            .status,
        'available',
      );
    },
  );

  test(
    'Two concurrent assignments cannot reserve the same virtual driver',
    () async {
      final gate = Completer<void>();
      final racing = FirestoreService(
        roadLoader: (start, end) async {
          await gate.future;
          return _road(start, end);
        },
      );
      addTearDown(racing.dispose);
      await racing.addEmployee(_virtualDriver);
      final one = await racing.submitEmergencyRequest(_patient('race-one'));
      final two = await racing.submitEmergencyRequest(_patient('race-two'));
      Future<bool> attempt(String id) async {
        try {
          await racing.assignRequest(
            requestId: id,
            employeeId: _virtualDriver.employeeId,
            employeeName: _virtualDriver.name,
          );
          return true;
        } on StateError {
          return false;
        }
      }

      final first = attempt(one), second = attempt(two);
      gate.complete();
      final results = await Future.wait([first, second]);
      expect(results.where((success) => success).length, 1);
    },
  );

  test(
    'Random generation is bounded, unique, parked and account-free',
    () async {
      final units = await service.generateRandomDrivers(
        count: 10,
        stagingPoint: const LatLng(34.2, 73.23),
        random: Random(7),
      );
      expect(units.length, 10);
      expect(units.map((e) => e.vehicleNumber).toSet().length, 10);
      expect(
        units.every(
          (e) =>
              e.userId.isEmpty &&
              e.phone.isEmpty &&
              e.isSimulated &&
              e.status == 'available' &&
              e.hasValidLocation,
        ),
        isTrue,
      );
      await expectLater(
        service.generateRandomDrivers(
          count: 11,
          stagingPoint: const LatLng(34.2, 73.23),
        ),
        throwsArgumentError,
      );
      await expectLater(
        service.generateRandomDrivers(
          count: 1,
          stagingPoint: const LatLng(0, 0),
        ),
        throwsArgumentError,
      );
    },
  );

  test('Positioning failure cannot add a partial random fleet', () async {
    var calls = 0;
    final failing = FirestoreService(
      roadSnapper: (point) async {
        if (++calls == 2) throw StateError('Routing offline');
        return point;
      },
    );
    addTearDown(failing.dispose);
    final before = failing.getAllEmployees().length;
    await expectLater(
      failing.generateRandomDrivers(
        count: 3,
        stagingPoint: const LatLng(34.2, 73.23),
      ),
      throwsStateError,
    );
    expect(failing.getAllEmployees().length, before);
  });
}
