import 'package:flutter_test/flutter_test.dart';
import 'package:edhiconnect_ai/services/ai_triage_service.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';
import 'package:edhiconnect_ai/models/emergency_request.dart';
import 'package:edhiconnect_ai/models/donation.dart';
import 'package:edhiconnect_ai/models/blood_donor.dart';
import 'package:edhiconnect_ai/models/employee.dart';
import 'package:latlong2/latlong.dart';
import 'package:edhiconnect_ai/services/location_service.dart';
import 'package:edhiconnect_ai/core/constants/app_constants.dart';

void main() {
  group('AITriageService Tests', () {
    test('Classifies severe critical keywords as Critical P1', () {
      final p1 = AITriageService.classifyPriority(
        emergencyType: 'Road Accident',
        description:
            'Biker collision with unconscious victim and severe bleeding.',
      );
      expect(p1, 'Critical P1');

      final cardiac = AITriageService.classifyPriority(
        emergencyType: 'Medical Emergency',
        description: 'Suspected heart attack, patient not breathing.',
      );
      expect(cardiac, 'Critical P1');
    });

    test('Classifies urgent non-life-threatening keywords as Urgent P2', () {
      final p2 = AITriageService.classifyPriority(
        emergencyType: 'Medical Emergency',
        description: 'Patient slipped and has an ankle fracture.',
      );
      expect(p2, 'Urgent P2');
    });

    test('Classifies routine transfers as Standard P3', () {
      final p3 = AITriageService.classifyPriority(
        emergencyType: 'Medical Emergency',
        description: 'Routine patient transfer from clinic to home.',
      );
      expect(p3, 'Standard P3');
    });

    test('Detects duplicate emergency within 150m and 20 mins', () {
      final existing = EmergencyRequest(
        requestId: 'REQ-EXISTING-1',
        userId: 'u1',
        emergencyType: 'Road Accident',
        location: const RequestLocation(
          latitude: 34.1986,
          longitude: 73.2312,
          address: 'Supply Chowk',
        ),
        description: 'Car crash',
        status: 'Pending',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );

      final dup = AITriageService.detectDuplicate(
        newLoc: const RequestLocation(
          latitude: 34.1988,
          longitude: 73.2314,
          address: 'Near Supply Chowk',
        ),
        activeRequests: [existing],
      );

      expect(dup, isNotNull);
      expect(dup?.requestId, 'REQ-EXISTING-1');
    });

    test('Chatbot provides emergency advice when distress detected', () {
      final reply = AITriageService.getChatbotResponse(
        'I need an ambulance immediately!',
      );
      expect(reply.isEmergencyIntent, isTrue);
      expect(reply.text, contains('115'));
      expect(reply.text, contains('Emergency Request'));
      expect(reply.text, contains('now'));
    });

    test('Chatbot responds accurately to Blood Bank inquiries', () {
      final reply = AITriageService.getChatbotResponse(
        'How do I donate blood?',
      );
      expect(reply.text.contains('Blood Bank'), isTrue);
    });

    test(
      'Fraud Assessment: Correctly tags prank keywords and dummy phone number as High Risk',
      () {
        final assessment = AITriageService.assessFraudRisk(
          description:
              'Testing emergency button lol just a prank fake call haha',
          userPhone: '03000000000',
          location: const RequestLocation(
            latitude: 34.1986,
            longitude: 73.2312,
            address: 'Supply Chowk',
          ),
        );

        expect(assessment.level, 'High');
        expect(assessment.score, greaterThanOrEqualTo(0.55));
        expect(assessment.reasons.any((r) => r.contains('prank')), isTrue);
        expect(assessment.reasons.any((r) => r.contains('dummy')), isTrue);
      },
    );

    test(
      'Fraud Assessment: Flags keyboard mash and out-of-jurisdiction coordinates',
      () {
        final assessment = AITriageService.assessFraudRisk(
          description: 'Emergency aaaaaaaaaaaaa',
          userPhone: '03451234567',
          location: const RequestLocation(
            latitude: 51.5074,
            longitude: -0.1278,
            address: 'London, UK',
          ), // Outside PK bounds
        );

        expect(assessment.level, isIn(['Medium', 'High']));
        expect(assessment.score, greaterThanOrEqualTo(0.40));
        expect(
          assessment.reasons.any(
            (r) => r.contains('keyboard mash') || r.contains('Repetitive'),
          ),
          isTrue,
        );
        expect(
          assessment.reasons.any((r) => r.contains('jurisdiction')),
          isTrue,
        );
      },
    );

    test(
      'Fraud Assessment: Approves genuine emergency with Low Risk and clear reasons',
      () {
        final assessment = AITriageService.assessFraudRisk(
          description:
              'Head trauma victim after motorcycle fall near Mandian bazaar',
          userPhone: '03335559876',
          location: const RequestLocation(
            latitude: 34.2050,
            longitude: 73.2380,
            address: 'Mandian, Abbottabad',
          ),
        );

        expect(assessment.level, 'Low');
        expect(assessment.score, lessThan(0.30));
        expect(assessment.reasons, isEmpty);
      },
    );
  });

  group('FirestoreService Tests', () {
    late FirestoreService service;

    setUp(() {
      service = FirestoreService(automaticSimulation: false);
    });

    tearDown(() {
      service.dispose();
    });

    test('Donation submission and verification updates state', () async {
      final initialDonations = await service.getDonationsStream().first;
      final initialCount = initialDonations.length;

      final donationId = await service.submitDonation(
        const Donation(
          donationId: '',
          userId: 'test_user',
          userName: 'Test Donor',
          amount: 2500,
          donationType: 'monetary',
          notes: 'Test Relief',
        ),
      );

      expect(donationId.startsWith('DON-'), isTrue);

      final updatedDonations = await service.getDonationsStream().first;
      expect(updatedDonations.length, initialCount + 1);

      await service.verifyDonation(donationId);
      final verifiedDonations = await service.getDonationsStream().first;
      final verified = verifiedDonations.firstWhere(
        (d) => d.donationId == donationId,
      );
      expect(verified.status, 'Verified');
    });

    test('Blood donor registration persists correctly', () async {
      final initialCount = service.bloodDonorCount;

      await service.registerBloodDonor(
        const BloodDonor(
          donorId: '',
          userId: 'new_donor',
          userName: 'Hamza Khan',
          bloodGroup: 'AB+',
          city: 'Abbottabad',
        ),
      );

      expect(service.bloodDonorCount, initialCount + 1);
    });

    test(
      'Nearest ambulance detection and auto-dispatch allocates closest unit',
      () async {
        // Emergency near Sajid Mehmood (driver_mock_2: 34.1820, 73.2260)
        final nearest = service.findNearestAvailableAmbulance(34.1825, 73.2265);
        expect(nearest, isNotNull);
        expect(nearest!.employee.employeeId, 'driver_mock_2');
        expect(nearest.distanceKm, lessThan(0.5));
        expect(nearest.etaMinutes, greaterThanOrEqualTo(1));

        // Submit emergency request with autoAssignNearest = true
        final reqId = await service.submitEmergencyRequest(
          EmergencyRequest(
            requestId: '',
            userId: 'user_test_sos',
            userName: 'Urgent Citizen',
            userPhone: '03009998877',
            emergencyType: 'Cardiac Arrest',
            priority: 'Critical P1',
            location: const RequestLocation(
              latitude: 34.1825,
              longitude: 73.2265,
              address: 'Supply Road near Medical Complex',
            ),
            description: 'Immediate resuscitation required',
            status: EmergencyStatus.pending,
          ),
          autoAssignNearest: true,
        );

        final requests = await service.getRequestsStream().first;
        final assignedReq = requests.firstWhere((r) => r.requestId == reqId);
        expect(assignedReq.status, EmergencyStatus.assigned);
        expect(assignedReq.assignedEmployeeId, 'driver_mock_2');
        expect(assignedReq.assignedEmployeeName, contains('Sajid Mehmood'));

        // Verify driver_mock_2 status was updated to busy
        final drivers = service.getAllEmployees();
        final assignedDriver = drivers.firstWhere(
          (d) => d.employeeId == 'driver_mock_2',
        );
        expect(assignedDriver.status, 'busy');

        // Complete each saved dispatch stage before releasing the driver.
        await service.updateRequestStatus(reqId, EmergencyStatus.inProgress);
        await service.updateRequestStatus(reqId, EmergencyStatus.arrived);
        await service.updateRequestStatus(reqId, EmergencyStatus.completed);
        final updatedDrivers = service.getAllEmployees();
        final releasedDriver = updatedDrivers.firstWhere(
          (d) => d.employeeId == 'driver_mock_2',
        );
        expect(releasedDriver.status, 'available');
      },
    );

    test(
      'Admin manually adds driver, verifies live coordinates and assigns to request',
      () async {
        final initialCount = service.getAllEmployees().length;

        // 1. Manually add a driver stationed at Ayub Medical Complex (34.2050, 73.2380)
        final newDriverId = await service.addEmployee(
          const Employee(
            employeeId: 'driver_custom_99',
            userId: '', // Ambulance added before linking a registered account.
            name: 'Rashid Mahmood',
            phone: '03001239999',
            vehicleNumber: 'EDHI-AMB-999',
            vehicleModel: 'Mercedes-Benz Sprinter ICU Unit',
            currentLat: 34.2050,
            currentLng: 73.2380,
            batteryFuel: 98,
            speedKmh: 0,
            status: 'available',
          ),
        );

        expect(newDriverId, 'driver_custom_99');
        final allEmployees = service.getAllEmployees();
        expect(allEmployees.length, initialCount + 1);

        // Verify the driver is available and has correct coordinates
        final addedDriver = allEmployees.firstWhere(
          (e) => e.employeeId == 'driver_custom_99',
        );
        expect(addedDriver.name, 'Rashid Mahmood');
        expect(addedDriver.vehicleNumber, 'EDHI-AMB-999');
        expect(addedDriver.currentLat, 34.2050);
        expect(addedDriver.currentLng, 73.2380);
        expect(addedDriver.batteryFuel, 98);
        expect(addedDriver.status, 'available');

        // 2. Verify added driver is selected as nearest ambulance for emergency at 34.2052, 73.2382
        final nearest = service.findNearestAvailableAmbulance(34.2052, 73.2382);
        expect(nearest, isNotNull);
        expect(nearest!.employee.employeeId, 'driver_custom_99');

        // 3. Admin assigns driver manually to an emergency request
        await service.assignRequest(
          requestId: 'REQ-101',
          employeeId: addedDriver.employeeId,
          employeeName: '${addedDriver.name} (${addedDriver.vehicleNumber})',
        );

        final requests = await service.getRequestsStream().first;
        final req101 = requests.firstWhere((r) => r.requestId == 'REQ-101');
        expect(req101.status, EmergencyStatus.assigned);
        expect(req101.assignedEmployeeId, 'driver_custom_99');

        // Verify driver status became busy
        final updatedDriver = service.getAllEmployees().firstWhere(
          (e) => e.employeeId == 'driver_custom_99',
        );
        expect(updatedDriver.status, 'busy');

        // Busy units cannot be decommissioned before their response is complete.
        await expectLater(
          service.deleteEmployee('driver_custom_99'),
          throwsStateError,
        );
        await service.updateRequestStatus(
          'REQ-101',
          EmergencyStatus.inProgress,
        );
        await service.updateRequestStatus('REQ-101', EmergencyStatus.arrived);
        await service.updateRequestStatus('REQ-101', EmergencyStatus.completed);
        // 4. Admin deletes/decommissions the released driver.
        await service.deleteEmployee('driver_custom_99');
        expect(
          service.getAllEmployees().any(
            (e) => e.employeeId == 'driver_custom_99',
          ),
          isFalse,
        );
      },
    );

    test('LocationService: Computes accurate forward bearing azimuth', () {
      // Due North: bearing should be ~0 degrees
      final bearingNorth = LocationService.calculateBearing(
        const LatLng(34.0, 73.0),
        const LatLng(35.0, 73.0),
      );
      expect(bearingNorth, closeTo(0.0, 1.0));

      // Due East: bearing should be ~90 degrees
      final bearingEast = LocationService.calculateBearing(
        const LatLng(34.0, 73.0),
        const LatLng(34.0, 74.0),
      );
      expect(bearingEast, closeTo(90.0, 1.0));
    });

    test(
      'LocationService: Dynamically trims route ahead starting seamlessly from current position',
      () {
        final route = [
          const LatLng(34.1980, 73.2300),
          const LatLng(34.1990, 73.2310),
          const LatLng(34.2000, 73.2320),
          const LatLng(34.2010, 73.2330),
        ];

        // Vehicle is currently near waypoint 2 (34.1991, 73.2311)
        const currentPos = LatLng(34.1991, 73.2311);
        final trimmed = LocationService.trimRouteAhead(route, currentPos);

        expect(trimmed.first, currentPos);
        expect(trimmed.length, 3);
        expect(trimmed.last, const LatLng(34.2010, 73.2330));
      },
    );

    test(
      'FirestoreService: GPS heartbeat is not confused with demo playback',
      () async {
        final service = FirestoreService(automaticSimulation: false);
        const driverId = 'emp_heartbeat_test';

        await service.addEmployee(
          Employee(
            employeeId: driverId,
            userId: '',
            name: 'Heartbeat Driver',
            phone: '0300-1112233',
            vehicleNumber: 'EDHI-HB-1',
            currentLat: 34.1986,
            currentLng: 73.2312,
            transitRunnerSession: 'other_tab_session_999',
            transitLastHeartbeat:
                DateTime.now().millisecondsSinceEpoch -
                500, // 500ms ago (fresh)
          ),
        );

        expect(service.isTransitActive(driverId), isFalse);

        // Clean up
        await service.deleteEmployee(driverId);
        service.dispose();
      },
    );

    test(
      'FirestoreService: High fraud risk emergency withholds auto-dispatch and requires dispatcher verification',
      () async {
        final service = FirestoreService(automaticSimulation: false);

        // Submit an emergency that triggers high fraud score
        final prankReq = EmergencyRequest(
          requestId: '',
          userId: 'prankster_user',
          userName: 'Prank Caller',
          userPhone: '03000000000',
          emergencyType: EmergencyCategories.other,
          location: const RequestLocation(
            latitude: 34.1986,
            longitude: 73.2312,
            address: 'Test St',
          ),
          description: 'Just testing lol haha fake request',
        );

        final reqId = await service.submitEmergencyRequest(
          prankReq,
          autoAssignNearest: true,
        );
        final requests = await service.getRequestsStream().first;
        final submitted = requests.firstWhere((r) => r.requestId == reqId);

        // High fraud calls MUST NOT be auto-assigned to ambulances
        expect(submitted.fraudRiskLevel, 'High');
        expect(submitted.status, EmergencyStatus.pending);
        expect(submitted.assignedEmployeeId, isNull);
        expect(submitted.fraudReason, isNotNull);

        await expectLater(
          service.assignRequest(
            requestId: reqId,
            employeeId: 'driver_mock_2',
            employeeName: 'Sajid Mehmood (EDHI-AMB-207)',
          ),
          throwsA(isA<StateError>()),
        );

        // Dispatcher verifies the call
        await service.verifyEmergencyRequest(reqId);
        final verifiedRequests = await service.getRequestsStream().first;
        final verified = verifiedRequests.firstWhere(
          (r) => r.requestId == reqId,
        );
        expect(verified.isVerified, isTrue);
        expect(verified.fraudRiskLevel, 'Low');

        service.dispose();
      },
    );

    test(
      'FirestoreService: Dispatcher rejects fraudulent request and marks as cancelled',
      () async {
        final service = FirestoreService(automaticSimulation: false);

        final prankReq = EmergencyRequest(
          requestId: '',
          userId: 'prankster_user_2',
          userName: 'Spam User',
          userPhone: '1111111111',
          emergencyType: EmergencyCategories.other,
          location: const RequestLocation(
            latitude: 34.1986,
            longitude: 73.2312,
            address: 'Test St',
          ),
          description: 'Prank call 123456789',
        );

        final reqId = await service.submitEmergencyRequest(prankReq);
        await service.rejectFraudEmergencyRequest(
          reqId,
          reason: 'Identified as confirmed prank',
        );

        final requests = await service.getRequestsStream().first;
        final cancelled = requests.firstWhere((r) => r.requestId == reqId);
        expect(cancelled.status, EmergencyStatus.cancelled);
        expect(cancelled.fraudReason, 'Identified as confirmed prank');

        service.dispose();
      },
    );

    test(
      'FirestoreService: findNearestAvailableAmbulance dynamically identifies closest unit for pinpointed coordinates',
      () async {
        final service = FirestoreService(automaticSimulation: false);

        // Pinpointed location near Supply Chowk (34.1986, 73.2312)
        final nearestSupply = service.findNearestAvailableAmbulance(
          34.1986,
          73.2312,
        );
        expect(nearestSupply, isNotNull);
        expect(nearestSupply!.employee.status, 'available');
        expect(nearestSupply.distanceKm, greaterThan(0.0));
        expect(nearestSupply.etaMinutes, greaterThanOrEqualTo(2));

        // Submit pinpointed emergency with auto-assign enabled
        final req = EmergencyRequest(
          requestId: '',
          userId: 'pinpoint_user',
          userName: 'Zubair Shah',
          userPhone: '03339876543',
          emergencyType: EmergencyCategories.roadAccident,
          location: const RequestLocation(
            latitude: 34.1986,
            longitude: 73.2312,
            address: 'Supply Chowk Pinpoint',
          ),
          description: 'Two cars collided, driver trapped.',
        );

        final reqId = await service.submitEmergencyRequest(
          req,
          autoAssignNearest: true,
        );
        final requests = await service.getRequestsStream().first;
        final submitted = requests.firstWhere((r) => r.requestId == reqId);

        expect(submitted.status, EmergencyStatus.assigned);
        expect(submitted.assignedEmployeeId, nearestSupply.employee.employeeId);
        expect(
          submitted.assignedEmployeeName,
          contains(nearestSupply.employee.vehicleNumber),
        );

        // Verify the allocated driver is now marked busy
        final assignedDriver = service.getAllEmployees().firstWhere(
          (e) => e.employeeId == nearestSupply.employee.employeeId,
        );
        expect(assignedDriver.status, 'busy');

        service.dispose();
      },
    );

    test('Response planning matches trauma equipment and nearby hospitals', () {
      final service = FirestoreService(automaticSimulation: false);
      final plan = service.buildResponsePlan(
        const EmergencyRequest(
          requestId: 'REQ-PLAN',
          userId: 'user-plan',
          emergencyType: EmergencyCategories.roadAccident,
          location: RequestLocation(
            latitude: 34.1986,
            longitude: 73.2312,
            address: 'Supply Chowk',
          ),
          description:
              'Vehicle collision with possible neck injury and bleeding',
        ),
      );

      expect(plan.requiredEquipment, contains('Cervical collar'));
      expect(plan.requiredEquipment, contains('Spinal board'));
      expect(plan.hospitals, isNotEmpty);
      expect(
        plan.hospitals.first.distanceKm,
        lessThanOrEqualTo(plan.hospitals.last.distanceKm),
      );
      service.dispose();
    });

    test(
      'Operations audit records emergency creation and status changes',
      () async {
        final service = FirestoreService(automaticSimulation: false);
        final requestId = await service.submitEmergencyRequest(
          const EmergencyRequest(
            requestId: '',
            userId: 'audit-user',
            emergencyType: EmergencyCategories.medical,
            location: RequestLocation(
              latitude: 34.1986,
              longitude: 73.2312,
              address: 'Audit Street',
            ),
            description: 'Patient needs urgent medical support',
          ),
        );
        await service.updateRequestStatus(requestId, EmergencyStatus.approved);

        final events = await service.getAuditEventsStream().first;
        expect(
          events.any(
            (event) => event.entityId == requestId && event.action == 'created',
          ),
          isTrue,
        );
        expect(
          events.any(
            (event) =>
                event.entityId == requestId && event.action == 'status_changed',
          ),
          isTrue,
        );
        service.dispose();
      },
    );
  });
}
