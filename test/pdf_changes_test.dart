import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:edhiconnect_ai/core/constants/app_constants.dart';
import 'package:edhiconnect_ai/core/widgets/dispatch_progress.dart';
import 'package:edhiconnect_ai/models/blood_donor.dart';
import 'package:edhiconnect_ai/models/missing_person_report.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Dispatch progress is ordered, includes completion, and does not guess arrival',
    () {
      for (final pair in [
        (EmergencyStatus.pending, 0),
        (EmergencyStatus.approved, 0),
        (EmergencyStatus.assigned, 1),
        (EmergencyStatus.inProgress, 2),
        (EmergencyStatus.arrived, 3),
        (EmergencyStatus.completed, 4),
        (EmergencyStatus.cancelled, -1),
      ]) {
        expect(DispatchProgress.stageFor(pair.$1), pair.$2);
      }
      expect(
        EmergencyStatus.canTransition(
          EmergencyStatus.assigned,
          EmergencyStatus.completed,
        ),
        isFalse,
      );
      expect(
        EmergencyStatus.canTransition(
          EmergencyStatus.completed,
          EmergencyStatus.inProgress,
        ),
        isFalse,
      );
      expect(
        EmergencyStatus.canTransition(
          EmergencyStatus.inProgress,
          EmergencyStatus.arrived,
        ),
        isTrue,
      );
    },
  );
  testWidgets('Progress fits narrow mobile screens at large text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 700),
            textScaler: TextScaler.linear(1.5),
          ),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: DispatchProgress(status: EmergencyStatus.assigned),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Arrived'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  });
  test(
    'All donors contains newly registered donors; city and blood filters agree',
    () async {
      final service = FirestoreService(automaticSimulation: false);
      addTearDown(service.dispose);
      await service.registerBloodDonor(
        const BloodDonor(
          donorId: '',
          userId: 'pdf_donor',
          userName: 'New Donor',
          userPhone: '03001112222',
          bloodGroup: 'AB-',
          city: 'Lahore',
        ),
      );
      final all = await service.getBloodDonorsStream(bloodGroup: 'All').first;
      final category = await service
          .getBloodDonorsStream(bloodGroup: 'AB-')
          .first;
      expect(all.any((d) => d.userId == 'pdf_donor'), isTrue);
      expect(category.any((d) => d.userId == 'pdf_donor'), isTrue);
      expect(
        (await service.getBloodDonorsStream(city: 'lahore').first).any(
          (d) => d.userId == 'pdf_donor',
        ),
        isTrue,
      );
      await service.registerBloodDonor(
        const BloodDonor(
          donorId: '',
          userId: 'pdf_donor',
          userName: 'New Donor',
          userPhone: '03001112222',
          bloodGroup: 'O+',
          city: 'Lahore',
        ),
      );
      expect(
        (await service.getBloodDonorsStream(bloodGroup: 'All').first)
            .where((d) => d.userId == 'pdf_donor')
            .length,
        1,
      );
    },
  );
  test(
    'Only the urgent requester can cancel; cancelled needs disappear',
    () async {
      final service = FirestoreService(automaticSimulation: false);
      addTearDown(service.dispose);
      final need = UrgentBloodNeed(
        id: 'pdf_need',
        userId: 'owner',
        patientName: 'Patient',
        hospital: 'Hospital',
        bloodGroup: 'O+',
        unitsNeeded: 2,
        contact: '03001112222',
        createdAt: DateTime.now(),
      );
      await service.submitUrgentBloodNeed(need);
      expect(need.isOwnedBy('owner'), isTrue);
      expect(need.isOwnedBy(''), isFalse);
      expect(UrgentBloodNeed.fromMap(need.toMap()).userId, 'owner');
      await expectLater(
        service.cancelUrgentBloodNeed('pdf_need', 'other'),
        throwsStateError,
      );
      await service.cancelUrgentBloodNeed('pdf_need', 'owner');
      expect(
        (await service.getBloodNeedsStream().first).any(
          (n) => n.id == 'pdf_need',
        ),
        isFalse,
      );
    },
  );
  test(
    'User and driver streams do not include unrelated or unassigned emergencies',
    () async {
      final service = FirestoreService(automaticSimulation: false);
      addTearDown(service.dispose);
      expect(await service.getUserRequestsStream('').first, isEmpty);
      expect(await service.getAssignedRequestsStream('').first, isEmpty);
      expect(
        (await service.getUserRequestsStream('user_mock_1').first).every(
          (r) => r.userId == 'user_mock_1',
        ),
        isTrue,
      );
      expect(
        (await service.getAssignedRequestsStream('driver_mock_2').first).every(
          (r) => r.assignedEmployeeId == 'driver_mock_2',
        ),
        isTrue,
      );
    },
  );
  test(
    'Missing person photo and last seen timestamps survive serialization; legacy data loads',
    () {
      final date = DateTime(2026, 9, 1, 14, 30);
      final report = MissingPersonReport(
        reportId: 'mp',
        userId: 'owner',
        personName: 'Person',
        age: 30,
        gender: 'Male',
        lastSeenLocation: 'Lahore',
        description: 'Blue shirt',
        contactName: 'Family',
        contactPhone: '03001112222',
        reportedAt: DateTime.now(),
        lastSeenAt: date,
        photoUrl: 'https://example.com/photo.jpg',
      );
      final copy = MissingPersonReport.fromMap(
        report.toMap(),
      ).copyWith(status: 'Found');
      expect(copy.lastSeenAt, date);
      expect(copy.photoUrl, report.photoUrl);
      expect(copy.userId, 'owner');
      expect(
        MissingPersonReport.fromMap({'personName': 'Legacy'}).lastSeenAt,
        isNull,
      );
    },
  );
}
