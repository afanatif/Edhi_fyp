import 'package:flutter_test/flutter_test.dart';
import 'package:edhiconnect_ai/services/firestore_service.dart';
import 'package:edhiconnect_ai/models/emergency_request.dart';
import 'package:edhiconnect_ai/models/donation.dart';
import 'package:edhiconnect_ai/models/blood_donor.dart';
import 'package:edhiconnect_ai/models/missing_person_report.dart';
import 'package:edhiconnect_ai/models/feedback_item.dart';
import 'package:edhiconnect_ai/core/constants/app_constants.dart';

void main() {
  group('SRS Non-Functional Requirements (NFR) Validation', () {
    late FirestoreService firestore;

    setUp(() {
      firestore = FirestoreService(automaticSimulation: false);
    });

    tearDown(() {
      firestore.dispose();
    });

    test(
      'NFR-USE-01: Simple Emergency Request Submission within 2 programmatic steps',
      () async {
        final stopwatch = Stopwatch()..start();

        // Step 1: User specifies emergency category & basic details (Tap 1)
        const category = EmergencyCategories.roadAccident;
        const location = RequestLocation(
          latitude: 34.1986,
          longitude: 73.2312,
          address: 'Mandian Chowk, Abbottabad',
        );

        // Step 2: User triggers SOS dispatch (Tap 2)
        final req = EmergencyRequest(
          requestId: '',
          userId: 'citizen_test_1',
          userName: 'Usman Waqar',
          userPhone: '03335559999',
          emergencyType: category,
          priority: 'Critical P1',
          location: location,
          description: 'Urgent assistance requested via 2-tap SOS',
          status: EmergencyStatus.pending,
          createdAt: DateTime.now(),
        );

        final newId = await firestore.submitEmergencyRequest(req);
        stopwatch.stop();

        // Assertions
        expect(newId, isNotEmpty);
        expect(newId.startsWith('REQ-'), isTrue);
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(1000),
          reason: '2-tap submission must be sub-second',
        );

        final allReqs = await firestore.getRequestsStream().first;
        final retrieved = allReqs.firstWhere((r) => r.requestId == newId);
        expect(retrieved.status, EmergencyStatus.pending);
        expect(retrieved.emergencyType, EmergencyCategories.roadAccident);
      },
    );

    test(
      'NFR-PER-01: Emergency Request Latency Benchmark (< 2000 ms to Admin Console)',
      () async {
        final stopwatch = Stopwatch()..start();

        const newLoc = RequestLocation(
          latitude: 34.2010,
          longitude: 73.2450,
          address: 'Kaghan Colony Gate, Abbottabad',
        );

        final req = EmergencyRequest(
          requestId: '',
          userId: 'user_benchmark',
          userName: 'Daniyal Murtaza',
          userPhone: '03001122334',
          emergencyType: EmergencyCategories.medical,
          priority: 'Urgent P2',
          location: newLoc,
          description: 'Severe asthma breathing distress',
          status: EmergencyStatus.pending,
          createdAt: DateTime.now(),
        );

        final id = await firestore.submitEmergencyRequest(req);
        final streamList = await firestore.getRequestsStream().first;
        stopwatch.stop();

        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(2000),
          reason: 'SLA requires arrival in under 2 seconds',
        );
        expect(streamList.any((r) => r.requestId == id), isTrue);
      },
    );

    test(
      'NFR-PER-03: Dashboard Response Time & KPI Retrieval Benchmark (< 3000 ms)',
      () async {
        final stopwatch = Stopwatch()..start();

        // Measure simultaneous stream fetches for Admin Console
        final requests = await firestore.getRequestsStream().first;
        final donations = await firestore.getDonationsStream().first;
        final donors = await firestore.getBloodDonorsStream().first;
        final users = await firestore.getUsersStream().first;
        final centers = firestore.getEdhiCenters();

        // Compute dashboard KPI rollups
        final pendingCount = requests
            .where((r) => r.status == EmergencyStatus.pending)
            .length;
        final activeCount = requests
            .where(
              (r) =>
                  r.status == EmergencyStatus.assigned ||
                  r.status == EmergencyStatus.inProgress,
            )
            .length;
        final completedCount = requests
            .where((r) => r.status == EmergencyStatus.completed)
            .length;

        stopwatch.stop();

        expect(requests, isNotEmpty);
        expect(donations, isNotEmpty);
        expect(donors, isNotEmpty);
        expect(users, isNotEmpty);
        expect(centers, isNotEmpty);
        expect(pendingCount, greaterThanOrEqualTo(0));
        expect(activeCount, greaterThanOrEqualTo(0));
        expect(completedCount, greaterThanOrEqualTo(0));
        expect(
          stopwatch.elapsedMilliseconds,
          lessThan(3000),
          reason: 'Admin dashboard must load within 3 seconds',
        );
      },
    );

    test(
      'NFR-USE-03: Driver Mission Progression & Lifecycle Updates',
      () async {
        // Create fresh request
        final reqId = await firestore.submitEmergencyRequest(
          EmergencyRequest(
            requestId: '',
            userId: 'citizen_driver_test',
            userName: 'Citizen In Need',
            userPhone: '03120001111',
            emergencyType: EmergencyCategories.fire,
            priority: 'Critical P1',
            location: const RequestLocation(
              latitude: 34.19,
              longitude: 73.22,
              address: 'Fawwara Chowk',
            ),
            description: 'Electrical fire near shop',
            status: EmergencyStatus.pending,
            createdAt: DateTime.now(),
          ),
        );

        // Admin assigns driver
        await firestore.assignRequest(
          requestId: reqId,
          employeeId: 'driver_mock_2',
          employeeName: 'Sajid Mehmood (EDHI-AMB-207)',
        );

        var list = await firestore.getRequestsStream().first;
        var assignedReq = list.firstWhere((r) => r.requestId == reqId);
        expect(assignedReq.status, EmergencyStatus.assigned);
        expect(assignedReq.assignedEmployeeId, 'driver_mock_2');

        // Driver marks En Route (In Progress)
        await firestore.updateRequestStatus(reqId, EmergencyStatus.inProgress);
        list = await firestore.getRequestsStream().first;
        expect(
          list.firstWhere((r) => r.requestId == reqId).status,
          EmergencyStatus.inProgress,
        );

        // Arrival must be explicitly confirmed before completion.
        await firestore.updateRequestStatus(reqId, EmergencyStatus.arrived);
        await firestore.updateRequestStatus(reqId, EmergencyStatus.completed);
        list = await firestore.getRequestsStream().first;
        expect(
          list.firstWhere((r) => r.requestId == reqId).status,
          EmergencyStatus.completed,
        );
      },
    );
  });

  group('Traceability Matrix & Functional Modules Verification', () {
    late FirestoreService firestore;

    setUp(() {
      firestore = FirestoreService(automaticSimulation: false);
    });

    tearDown(() {
      firestore.dispose();
    });

    test(
      'FR01 & FR02 / UC-01, 02, 20: AppUser serialization and role management',
      () async {
        final users = await firestore.getUsersStream().first;
        expect(users.length, greaterThanOrEqualTo(5));

        final citizen = users.firstWhere((u) => u.role == AppRoles.user);
        expect(citizen.isUser, isTrue);
        expect(citizen.isAdmin, isFalse);
        expect(citizen.isActive, isTrue);

        // Admin deactivates user
        await firestore.updateUserStatus(citizen.id, false);
        final updatedUsers = await firestore.getUsersStream().first;
        final updatedCitizen = updatedUsers.firstWhere(
          (u) => u.id == citizen.id,
        );
        expect(updatedCitizen.isActive, isFalse);
      },
    );

    test(
      'FR04 / UC-11-14: Donations tracking and unique receipt generation',
      () async {
        const donation = Donation(
          donationId: '',
          userId: 'donor_test_99',
          userName: 'Abdullah Sajid',
          amount: 10000,
          donationType: 'monetary',
          notes: 'Winter Blanket Drive',
        );

        final donationId = await firestore.submitDonation(donation);
        expect(donationId, startsWith('DON-'));

        final list = await firestore.getDonationsStream().first;
        final retrieved = list.firstWhere((d) => d.donationId == donationId);
        expect(retrieved.amount, 10000);
        expect(retrieved.status, 'Pending');

        // Admin verifies donation
        await firestore.verifyDonation(donationId);
        final verifiedList = await firestore.getDonationsStream().first;
        expect(
          verifiedList.firstWhere((d) => d.donationId == donationId).status,
          'Verified',
        );
      },
    );

    test(
      'FR05 / UC-15-17, 24: Blood donation network and availability toggle',
      () async {
        final initialCount = firestore.bloodDonorCount;

        await firestore.registerBloodDonor(
          const BloodDonor(
            donorId: '',
            userId: 'donor_new_1',
            userName: 'Zaid Khan',
            bloodGroup: 'O-',
            city: 'Abbottabad',
            userPhone: '0313-7766554',
          ),
        );

        expect(firestore.bloodDonorCount, initialCount + 1);

        final donors = await firestore.getBloodDonorsStream().first;
        expect(
          donors.any((d) => d.bloodGroup == 'O-' && d.userName == 'Zaid Khan'),
          isTrue,
        );

        final bloodNeeds = await firestore.getBloodNeedsStream().first;
        expect(bloodNeeds, isNotEmpty);
        expect(bloodNeeds.first.urgency, isIn(['Critical', 'Urgent']));
      },
    );

    test(
      'Scope Module 7: Missing Persons & Family Reunification workflow',
      () async {
        final initialList = await firestore.getMissingPersonsStream().first;
        final initialCount = initialList.length;

        final report = MissingPersonReport(
          reportId: '',
          personName: 'Test Missing Person',
          age: 14,
          gender: 'Male',
          lastSeenLocation: 'Mandian Market',
          description: 'Green jacket',
          contactName: 'Concerned Parent',
          contactPhone: '0300-9998877',
          status: 'Searching',
          reportedAt: DateTime.now(),
        );

        final reportId = await firestore.submitMissingPersonReport(report);
        expect(reportId, startsWith('MP-'));

        var streamList = await firestore.getMissingPersonsStream().first;
        expect(streamList.length, initialCount + 1);

        final submitted = streamList.firstWhere((r) => r.reportId == reportId);
        expect(submitted.isSearching, isTrue);

        // Mark Found
        await firestore.updateMissingPersonStatus(reportId, 'Found');
        streamList = await firestore.getMissingPersonsStream().first;
        expect(
          streamList.firstWhere((r) => r.reportId == reportId).isFound,
          isTrue,
        );
      },
    );

    test('FR11 / UC-09: Service feedback recording and calculation', () async {
      final feedback = FeedbackItem(
        feedbackId: '',
        userId: 'user_mock_1',
        userName: 'Ahmed Khan',
        comments: 'Outstanding response time and courteous ambulance driver.',
        rating: 5,
        createdAt: DateTime.now(),
      );

      await firestore.submitFeedback(feedback);

      final allFeedback = await firestore.getFeedbackStream().first;
      expect(
        allFeedback.any(
          (f) => f.comments.contains('courteous ambulance driver'),
        ),
        isTrue,
      );
    });
  });
}
