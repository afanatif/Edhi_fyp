import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'photo_codec.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/emergency_request.dart';
import '../models/emergency_usage.dart';
import '../models/route_playback.dart';
import '../data/edhi_center_directory.dart';
import '../data/simulated_fleet.dart';
import '../models/donation.dart';
import '../models/blood_donor.dart';
import '../models/employee.dart';
import '../models/edhi_center.dart';
import '../models/chat_message.dart';
import '../models/feedback_item.dart';
import '../models/app_user.dart';
import '../models/missing_person_report.dart';
import '../models/audit_event.dart';
import '../models/response_plan.dart';
import '../core/constants/app_constants.dart';
import '../firebase_options.dart';
import 'package:latlong2/latlong.dart';
import 'notification_service.dart';
import 'ai_triage_service.dart';
import 'welfare_knowledge_service.dart';
import 'location_service.dart';
import 'route_service.dart';
import 'chat_context_service.dart';

class NearestAmbulanceResult {
  final Employee employee;
  final double distanceKm;
  final int etaMinutes;

  const NearestAmbulanceResult({
    required this.employee,
    required this.distanceKm,
    required this.etaMinutes,
  });
}

class SystemHealthSnapshot {
  final bool databaseOnline;
  final int activeUnits;
  final int staleUnits;
  final int queuedWrites;
  final DateTime checkedAt;

  const SystemHealthSnapshot({
    required this.databaseOnline,
    required this.activeUnits,
    required this.staleUnits,
    required this.queuedWrites,
    required this.checkedAt,
  });

  bool get isHealthy => databaseOnline && staleUnits == 0 && queuedWrites == 0;
}

class UrgentBloodNeed {
  final String id;
  final String patientName;
  final String hospital;
  final String bloodGroup;
  final int unitsNeeded;
  final String contact;
  final String urgency;
  final DateTime createdAt;
  final String userId;
  final String status;

  bool isOwnedBy(String id) => id.isNotEmpty && id == userId;

  const UrgentBloodNeed({
    required this.id,
    required this.patientName,
    required this.hospital,
    required this.bloodGroup,
    required this.unitsNeeded,
    required this.contact,
    this.urgency = 'Critical',
    this.userId = '',
    this.status = 'active',
    required this.createdAt,
  });

  factory UrgentBloodNeed.fromMap(Map<String, dynamic> map, {String? docId}) {
    final rawDate = map['createdAt'];
    final createdAt = rawDate is Timestamp
        ? rawDate.toDate()
        : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();
    return UrgentBloodNeed(
      id: docId ?? map['id']?.toString() ?? '',
      patientName: map['patientName']?.toString() ?? '',
      hospital: map['hospital']?.toString() ?? '',
      bloodGroup: map['bloodGroup']?.toString() ?? 'O+',
      unitsNeeded: (map['unitsNeeded'] as num?)?.toInt() ?? 1,
      contact: map['contact']?.toString() ?? '',
      urgency: map['urgency']?.toString() ?? 'Critical',
      userId: map['userId']?.toString() ?? '',
      status: map['status']?.toString() ?? 'active',
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'patientName': patientName,
    'hospital': hospital,
    'bloodGroup': bloodGroup,
    'unitsNeeded': unitsNeeded,
    'contact': contact,
    'urgency': urgency,
    'userId': userId,
    'status': status,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}

class FirestoreService extends ChangeNotifier {
  /// Fleet playback is managed by Operations.
  static const simulatedFleetEnabled = true;
  final bool automaticSimulation;
  final Future<RoadRouteResult> Function(LatLng, LatLng) _roadLoader;
  final Future<LatLng> Function(LatLng) _roadSnapper;
  final DateTime Function() _now;
  FirebaseFirestore? _firestore;
  int _localIdSequence = 0;

  bool get isLiveFirebase =>
      DefaultFirebaseOptions.isConfigured && _firestore != null;

  String _newRecordId(String prefix) {
    _localIdSequence = (_localIdSequence + 1) % 1296;
    final time = DateTime.now().microsecondsSinceEpoch
        .toRadixString(36)
        .toUpperCase();
    final sequence = _localIdSequence
        .toRadixString(36)
        .padLeft(2, '0')
        .toUpperCase();
    return '$prefix-$time$sequence';
  }

  // In-memory mock storage for rapid testing & fallback
  final List<EmergencyRequest> _mockRequests = [];
  final List<Donation> _mockDonations = [];
  final List<BloodDonor> _mockBloodDonors = [];
  final List<UrgentBloodNeed> _mockBloodNeeds = [];
  final List<Employee> _mockEmployees = [];
  final List<EdhiCenter> _mockCenters = [];
  final List<FeedbackItem> _mockFeedback = [];
  final List<ChatMessage> _mockChatMessages = [];
  final List<AppUser> _mockUsers = [];
  final List<MissingPersonReport> _mockMissingPersons = [];
  final List<AuditEvent> _auditEvents = [];
  final Map<String, EmergencyRequest> _pendingEmergencyWrites = {};
  bool _disposed = false;

  final StreamController<List<EmergencyRequest>> _requestsController =
      StreamController<List<EmergencyRequest>>.broadcast();
  final StreamController<List<Donation>> _donationsController =
      StreamController<List<Donation>>.broadcast();
  final StreamController<List<BloodDonor>> _donorsController =
      StreamController<List<BloodDonor>>.broadcast();
  final StreamController<List<UrgentBloodNeed>> _bloodNeedsController =
      StreamController<List<UrgentBloodNeed>>.broadcast();
  final StreamController<List<ChatMessage>> _chatController =
      StreamController<List<ChatMessage>>.broadcast();
  final StreamController<List<FeedbackItem>> _feedbackController =
      StreamController<List<FeedbackItem>>.broadcast();
  final StreamController<List<AppUser>> _usersController =
      StreamController<List<AppUser>>.broadcast();
  final StreamController<List<MissingPersonReport>> _missingPersonsController =
      StreamController<List<MissingPersonReport>>.broadcast();
  final StreamController<List<Employee>> _employeesController =
      StreamController<List<Employee>>.broadcast();
  final StreamController<List<AuditEvent>> _auditController =
      StreamController<List<AuditEvent>>.broadcast();
  final Map<String, StreamSubscription<LatLng>> _liveLocationSubscriptions = {};

  int get pendingSyncCount => _pendingEmergencyWrites.length;
  bool isRequestQueued(String requestId) =>
      _pendingEmergencyWrites.containsKey(requestId);

  Future<void> registerPushToken(String userId, String token) async {
    if (userId.trim().isEmpty || token.trim().isEmpty || !isLiveFirebase) {
      return;
    }
    await _firestore!.collection(AppConstants.usersCollection).doc(userId).set({
      'pushTokens': FieldValue.arrayUnion([token.trim()]),
      'lastPushRegistrationAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  final List<Employee> _liveEmployees = [];
  final List<EdhiCenter> _liveCenters = [];
  StreamSubscription? _empSub;
  StreamSubscription? _centersSub;

  // Unique instance session ID to identify which tab is the authoritative simulation runner
  static final String _localSessionId =
      'session_${DateTime.now().microsecondsSinceEpoch}';

  final Map<String, RoutePlayback> _routeDemos = {};
  final Map<String, EmergencyUsage> _mockUsage = {};
  StreamSubscription? _demoSub;
  Timer? _demoTicker;
  String? _sessionUserId;
  String? _sessionRole;
  final Set<String> _pendingTransitStarts = {};
  StreamSubscription? _simulationRequestsSub;
  final Map<String, EmergencyRequest> _simulationRequests = {};
  final Map<String, String> _simulationErrors = {};
  final Map<String, DateTime> _simulationRetryAt = {};
  final Map<String, DateTime> _autoDispatchRetryAt = {};
  bool _autoDispatchBusy = false;
  final Set<String> _finishingSimulations = {};
  bool _repairingAssignmentLinks = false;
  double _simulationSpeed = 1;
  bool _routesLoaded = false;
  String? _simulationSyncError;
  String? get simulationSyncError => _simulationSyncError;
  double get simulationSpeed => _simulationSpeed;
  String? simulationError(String employeeId) => _simulationErrors[employeeId];

  // A denied Firestore listener closes. Restart after the active profile loads.
  void bindSession(String? userId, {String? role}) {
    if (!isLiveFirebase || (_sessionUserId == userId && _sessionRole == role)) {
      return;
    }
    _sessionUserId = userId;
    _sessionRole = role;
    _empSub?.cancel();
    _centersSub?.cancel();
    _demoSub?.cancel();
    _simulationRequestsSub?.cancel();
    _simulationRequests.clear();
    _simulationErrors.clear();
    _autoDispatchRetryAt.clear();
    _routesLoaded = false;
    _simulationSyncError = null;
    _pendingTransitStarts.clear();
    _liveEmployees.clear();
    _liveCenters.clear();
    _routeDemos.clear();
    _driverLocationErrors.clear();
    for (final id in _liveLocationSubscriptions.keys.toList()) {
      stopLiveDriverLocation(id);
    }
    if (userId != null) {
      _listenToLiveStreams();
    }
    scheduleMicrotask(() {
      if (!_employeesController.isClosed) {
        _employeesController.add(getAllEmployees());
        notifyListeners();
      }
    });
  }

  NotificationService? _notificationService;

  void attachNotificationService(NotificationService ns) {
    _notificationService = ns;
  }

  FirestoreService({
    this.automaticSimulation = true,
    Future<RoadRouteResult> Function(LatLng, LatLng)? roadLoader,
    Future<LatLng> Function(LatLng)? roadSnapper,
    DateTime Function()? clock,
  }) : _roadLoader = roadLoader ?? RouteService.getRoadRoute,
       _roadSnapper = roadSnapper ?? RouteService.snapToRoad,
       _now = clock ?? DateTime.now {
    _initialize();
  }

  void _initialize() {
    if (DefaultFirebaseOptions.isConfigured) {
      try {
        _firestore = FirebaseFirestore.instance;
        // Existing project data must never be deleted during startup.
      } catch (e) {
        debugPrint('Firestore initialization notice: $e');
        // Only seed mock data if running in headless unit tests
        if (!kIsWeb) {
          _seedMockData();
        }
      }
    } else {
      if (!kIsWeb) {
        _seedMockData();
      }
    }
  }

  void _listenToLiveStreams() {
    if (_firestore == null) {
      return;
    }
    _demoSub?.cancel();
    Query<Map<String, dynamic>> demoQuery = _firestore!.collection(
      'route_demos',
    );
    if (_sessionRole != AppRoles.admin) {
      demoQuery = demoQuery.where(
        _sessionRole == AppRoles.employee ? 'driverUserId' : 'userId',
        isEqualTo: _sessionUserId,
      );
    }
    _demoSub = demoQuery.snapshots().listen(
      (snapshot) {
        _routeDemos.clear();
        for (final doc in snapshot.docs) {
          try {
            final demo = RoutePlayback.fromMap(doc.data());
            _routeDemos[doc.id] = demo;
          } catch (error) {
            debugPrint('Invalid route demo: $error');
          }
        }
        _routesLoaded = true;
        _simulationSyncError = null;
        _ensureDemoTicker();
        _employeesController.add(getAllEmployees());
        notifyListeners();
      },
      onError: (Object error) {
        _simulationSyncError =
            'Road journeys could not load. Check connection and deploy the included Firebase rules.';
        if (!_disposed) {
          notifyListeners();
        }
        debugPrint('Simulation route access: $error');
      },
    );
    _empSub?.cancel();
    _empSub = _firestore!
        .collection(AppConstants.employeesCollection)
        .snapshots()
        .listen(
          (snap) {
            final confirmed = {for (final e in _liveEmployees) e.employeeId: e};
            final updates = snap.docs
                .map(
                  (doc) =>
                      doc.metadata.hasPendingWrites &&
                          confirmed.containsKey(doc.id)
                      ? confirmed[doc.id]!
                      : Employee.fromFirestore(doc),
                )
                .toList();
            _liveEmployees.clear();
            _liveEmployees.addAll(updates);
            final ownDriver = _liveEmployees
                .where((e) => e.userId == _sessionUserId && e.role == 'driver')
                .firstOrNull;
            if (!simulatedFleetEnabled &&
                _sessionRole == AppRoles.employee &&
                ownDriver != null) {
              if (ownDriver.status == 'offline') {
                stopLiveDriverLocation(ownDriver.employeeId);
              } else if (driverLocationError(ownDriver.employeeId) == null) {
                startLiveDriverLocation(ownDriver.employeeId);
              }
            }
            _employeesController.add(getAllEmployees());
            notifyListeners();
          },
          onError: (err) {
            debugPrint('Firestore live employees stream notice: $err');
          },
        );

    if (_sessionRole == AppRoles.admin && automaticSimulation) {
      _simulationRequestsSub = _firestore!
          .collection(AppConstants.requestsCollection)
          .snapshots()
          .listen(
            (snapshot) {
              _simulationRequests.clear();
              for (final doc in snapshot.docs) {
                final request = EmergencyRequest.fromFirestore(doc);
                if ([
                  EmergencyStatus.pending,
                  EmergencyStatus.approved,
                  EmergencyStatus.assigned,
                  EmergencyStatus.inProgress,
                  EmergencyStatus.arrived,
                ].contains(request.status)) {
                  _simulationRequests[request.requestId] = request;
                }
              }
              _ensureDemoTicker();
              unawaited(reconcileSimulations());
            },
            onError: (Object error) =>
                debugPrint('Simulation assignments: $error'),
          );
    }

    _centersSub?.cancel();
    _centersSub = _firestore!
        .collection('edhi_centers')
        .snapshots()
        .listen(
          (snap) {
            _liveCenters.clear();
            _liveCenters.addAll(
              snap.docs.map((d) => EdhiCenter.fromFirestore(d)),
            );
            notifyListeners();
          },
          onError: (err) {
            debugPrint('Firestore live centers stream notice: $err');
          },
        );
  }

  /// Purges sample/mock documents from Firestore
  Future<void> purgeMockDataFromFirestore() async {
    if (_firestore == null) {
      return;
    }
    try {
      final mockRequestIds = ['REQ-101', 'REQ-102'];
      for (final id in mockRequestIds) {
        await _firestore!
            .collection(AppConstants.requestsCollection)
            .doc(id)
            .delete();
      }

      final mockEmployeeIds = [
        'driver_mock_1',
        'driver_mock_2',
        'driver_mock_3',
        'driver_mock_4',
        'driver_mock_5',
      ];
      for (final id in mockEmployeeIds) {
        await _firestore!
            .collection(AppConstants.employeesCollection)
            .doc(id)
            .delete();
        await _firestore!
            .collection(AppConstants.usersCollection)
            .doc(id)
            .delete();
      }

      final mockCenterIds = ['center_1', 'center_2', 'center_3'];
      for (final id in mockCenterIds) {
        await _firestore!.collection('edhi_centers').doc(id).delete();
      }

      final mockDonationIds = ['DON-501', 'DON-502', 'DON-503'];
      for (final id in mockDonationIds) {
        await _firestore!.collection('donations').doc(id).delete();
      }

      final mockDonorIds = ['BLD-301', 'BLD-302', 'BLD-303'];
      for (final id in mockDonorIds) {
        await _firestore!.collection('blood_donors').doc(id).delete();
      }

      final mockBloodNeedIds = ['BNEED-101', 'BNEED-102'];
      for (final id in mockBloodNeedIds) {
        await _firestore!.collection('urgent_blood_needs').doc(id).delete();
      }

      final mockReportIds = ['MP-801', 'MP-802', 'MP-803'];
      for (final id in mockReportIds) {
        await _firestore!.collection('missing_persons').doc(id).delete();
      }

      final mockFeedbackIds = ['FDB-001'];
      for (final id in mockFeedbackIds) {
        await _firestore!.collection('feedback').doc(id).delete();
      }
    } catch (e) {
      debugPrint('Purge mock data notice: $e');
    }
  }

  /// Completely wipes all data across all collections in Firestore
  Future<void> wipeAllDataFromFirestore() async {
    if (_firestore == null) {
      return;
    }
    final collections = [
      AppConstants.requestsCollection,
      AppConstants.employeesCollection,
      'edhi_centers',
      'donations',
      'blood_donors',
      'urgent_blood_needs',
      'missing_persons',
      'feedback',
    ];
    for (final col in collections) {
      try {
        final snap = await _firestore!.collection(col).get();
        for (final doc in snap.docs) {
          await doc.reference.delete();
        }
      } catch (e) {
        debugPrint('Error wiping collection $col: $e');
      }
    }
    _liveEmployees.clear();
    _liveCenters.clear();
    notifyListeners();
  }

  void _seedMockData() {
    _mockCenters.addAll(edhiCenterDirectory);

    _mockEmployees.addAll([
      const Employee(
        employeeId: 'driver_mock_1',
        userId: 'driver_mock_1',
        name: 'Muhammad Tariq',
        phone: '03129876543',
        role: 'driver',
        status: 'busy',
        vehicleNumber: 'EDHI-AMB-402',
        assignedCenterId: 'center_1',
        vehicleModel: 'Toyota HiAce ICU Unit',
        currentLat: 34.1986,
        currentLng: 73.2350,
        batteryFuel: 88,
        speedKmh: 45,
      ),
      const Employee(
        employeeId: 'driver_mock_2',
        userId: 'driver_mock_2',
        name: 'Sajid Mehmood',
        phone: '03217654321',
        role: 'driver',
        status: 'available',
        vehicleNumber: 'EDHI-AMB-108',
        assignedCenterId: 'center_1',
        vehicleModel: 'Mercedes Sprinter ALS',
        currentLat: 34.1820,
        currentLng: 73.2260,
        batteryFuel: 94,
        speedKmh: 0,
      ),
      const Employee(
        employeeId: 'driver_mock_3',
        userId: 'driver_mock_3',
        name: 'Kamran Ali',
        phone: '03337651234',
        role: 'driver',
        status: 'available',
        vehicleNumber: 'EDHI-AMB-215',
        assignedCenterId: 'center_1',
        vehicleModel: 'Toyota Land Cruiser 4x4 Mountain Unit',
        currentLat: 34.1550,
        currentLng: 73.2180,
        batteryFuel: 76,
        speedKmh: 0,
      ),
      const Employee(
        employeeId: 'driver_mock_4',
        userId: 'driver_mock_4',
        name: 'Zubair Farooq',
        phone: '03459871234',
        role: 'driver',
        status: 'available',
        vehicleNumber: 'EDHI-AMB-330',
        assignedCenterId: 'center_1',
        vehicleModel: 'Suzuki Bolan Rapid Response',
        currentLat: 34.2150,
        currentLng: 73.2450,
        batteryFuel: 65,
        speedKmh: 0,
      ),
      const Employee(
        employeeId: 'driver_mock_5',
        userId: 'driver_mock_5',
        name: 'Naveed Akhter',
        phone: '03008765432',
        role: 'driver',
        status: 'available',
        vehicleNumber: 'EDHI-AMB-505',
        assignedCenterId: 'center_1',
        vehicleModel: 'Iveco Mobile Trauma Unit',
        currentLat: 34.1700,
        currentLng: 73.2300,
        batteryFuel: 82,
        speedKmh: 0,
      ),
    ]);

    _mockRequests.addAll([
      EmergencyRequest(
        requestId: 'REQ-101',
        userId: 'user_mock_1',
        userName: 'Ahmed Khan',
        userPhone: '03335551234',
        emergencyType: EmergencyCategories.roadAccident,
        priority: 'Critical P1',
        fraudRiskScore: 0.05,
        fraudRiskLevel: 'Low',
        isVerified: true,
        location: const RequestLocation(
          latitude: 34.1986,
          longitude: 73.2312,
          address: 'Supply Chowk, Abbottabad',
        ),
        description: 'Biker collision, unconscious rider with heavy bleeding.',
        status: EmergencyStatus.pending,
        createdAt: DateTime.now().subtract(const Duration(minutes: 8)),
      ),
      EmergencyRequest(
        requestId: 'REQ-102',
        userId: 'user_mock_2',
        userName: 'Ayesha Bibi',
        userPhone: '03456789012',
        emergencyType: EmergencyCategories.medical,
        priority: 'Urgent P2',
        fraudRiskScore: 0.10,
        fraudRiskLevel: 'Low',
        isVerified: true,
        location: const RequestLocation(
          latitude: 34.1688,
          longitude: 73.2215,
          address: 'Kaghan Colony, Abbottabad',
        ),
        description:
            'Elderly patient with severe chest pain and breathlessness.',
        status: EmergencyStatus.assigned,
        assignedEmployeeId: 'driver_mock_1',
        assignedEmployeeName: 'Muhammad Tariq (Ambulance EDHI-402)',
        createdAt: DateTime.now().subtract(const Duration(minutes: 35)),
      ),
      EmergencyRequest(
        requestId: 'REQ-103',
        userId: 'user_mock_3',
        userName: 'Prank Caller',
        userPhone: '03000000000',
        emergencyType: EmergencyCategories.other,
        priority: 'Standard P3',
        fraudRiskScore: 0.85,
        fraudRiskLevel: 'High',
        fraudReason:
            'Description contains prank/test term "testing"; Dummy contact phone pattern detected',
        isVerified: false,
        location: const RequestLocation(
          latitude: 34.2045,
          longitude: 73.2355,
          address: 'Pine View Road, Abbottabad',
        ),
        description:
            'Testing emergency button lol haha just a joke fake request asdf',
        status: EmergencyStatus.pending,
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
    ]);

    _mockDonations.addAll([
      Donation(
        donationId: 'DON-501',
        userId: 'user_mock_1',
        userName: 'Ahmed Khan',
        amount: 5000,
        donationType: 'monetary',
        status: 'Verified',
        notes: 'Emergency Ambulance Fuel Fund',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      Donation(
        donationId: 'DON-502',
        userId: 'user_mock_1',
        userName: 'Ahmed Khan',
        amount: 15000,
        donationType: 'monetary',
        status: 'Verified',
        notes: 'Flood Relief Campaign 2026',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
      Donation(
        donationId: 'DON-503',
        userId: 'user_mock_2',
        userName: 'Fatima Zahra',
        amount: 0,
        donationType: 'ration',
        status: 'Pending',
        notes: '3 Ration packages for needy families (Mandian pickup)',
        createdAt: DateTime.now().subtract(const Duration(hours: 4)),
      ),
    ]);

    _mockBloodDonors.addAll([
      BloodDonor(
        donorId: 'BLD-301',
        userId: 'user_mock_1',
        userName: 'Ahmed Khan',
        userPhone: '03335551234',
        bloodGroup: 'O+',
        availability: true,
        city: 'Abbottabad',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
      BloodDonor(
        donorId: 'BLD-302',
        userId: 'user_mock_2',
        userName: 'Usman Waqar',
        userPhone: '03125556789',
        bloodGroup: 'B+',
        availability: true,
        city: 'Abbottabad',
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
      ),
      BloodDonor(
        donorId: 'BLD-303',
        userId: 'user_mock_3',
        userName: 'Daniyal Murtaza',
        userPhone: '03451112233',
        bloodGroup: 'A-',
        availability: false,
        city: 'Islamabad',
        createdAt: DateTime.now().subtract(const Duration(days: 14)),
      ),
    ]);

    _mockBloodNeeds.addAll([
      UrgentBloodNeed(
        id: 'BNEED-101',
        patientName: 'Bilal Tariq',
        hospital: 'Ayub Teaching Hospital, Abbottabad',
        bloodGroup: 'O+',
        unitsNeeded: 2,
        contact: '0333-9876543',
        urgency: 'Critical',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      UrgentBloodNeed(
        id: 'BNEED-102',
        patientName: 'Zainab Bibi',
        hospital: 'District Headquarter Hospital (DHQ), Haripur',
        bloodGroup: 'B+',
        unitsNeeded: 1,
        contact: '0312-3456789',
        urgency: 'Urgent',
        createdAt: DateTime.now().subtract(const Duration(hours: 6)),
      ),
    ]);

    _mockFeedback.addAll([
      FeedbackItem(
        feedbackId: 'FDB-001',
        userId: 'user_mock_1',
        userName: 'Ahmed Khan',
        comments:
            'Prompt response by Edhi ambulance team in Mandian. Life saving service!',
        rating: 5,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ]);

    _mockChatMessages.addAll([
      ChatMessage(
        messageId: 'MSG-001',
        threadId: 'thread_default',
        sender: 'bot',
        message:
            'Assalam-o-Alaikum! I am EdhiConnect AI Assistant. How may I assist you with emergency response, blood donation, or charitable contributions today?',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      ),
    ]);

    _mockUsers.addAll([
      AppUser(
        id: 'user_mock_1',
        name: 'Ahmed Khan',
        email: 'citizen@edhi.org',
        phone: '03335551234',
        cnic: '37405-1234567-1',
        role: AppRoles.user,
        address: 'Mandian, Abbottabad',
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      ),
      AppUser(
        id: 'user_mock_2',
        name: 'Ayesha Bibi',
        email: 'ayesha@example.com',
        phone: '03456789012',
        cnic: '37405-7654321-2',
        role: AppRoles.user,
        address: 'Kaghan Colony, Abbottabad',
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(days: 18)),
      ),
      AppUser(
        id: 'driver_mock_1',
        name: 'Muhammad Tariq',
        email: 'driver@edhi.org',
        phone: '03129876543',
        cnic: '37405-1150001-1',
        role: AppRoles.employee,
        address: 'Rescue Station 1, Abbottabad',
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(days: 60)),
      ),
      AppUser(
        id: 'driver_mock_2',
        name: 'Sajid Mehmood',
        email: 'sajid@edhi.org',
        phone: '03217654321',
        cnic: '37405-1150002-2',
        role: AppRoles.employee,
        address: 'Rescue Station 1, Abbottabad',
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(days: 45)),
      ),
      AppUser(
        id: 'driver_mock_3',
        name: 'Kamran Ali',
        email: 'kamran@edhi.org',
        phone: '03337651234',
        cnic: '37405-1150003-3',
        role: AppRoles.employee,
        address: 'Station 2, Islamabad',
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
      ),
      AppUser(
        id: 'driver_mock_4',
        name: 'Zubair Farooq',
        email: 'zubair@edhi.org',
        phone: '03459871234',
        cnic: '37405-1150004-4',
        role: AppRoles.employee,
        address: 'Mansehra Road Station, Abbottabad',
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(days: 20)),
      ),
      AppUser(
        id: 'driver_mock_5',
        name: 'Naveed Akhter',
        email: 'naveed@edhi.org',
        phone: '03008765432',
        cnic: '37405-1150005-5',
        role: AppRoles.employee,
        address: 'Havelian Outpost, Abbottabad',
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
      ),
      AppUser(
        id: 'admin_mock_1',
        name: 'Muneeb Ur Rehman',
        email: 'admin@edhi.org',
        phone: '03001234567',
        cnic: '37405-0000001-9',
        role: AppRoles.admin,
        address: 'Edhi Central Operations HQ',
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(days: 120)),
      ),
    ]);

    _mockMissingPersons.addAll([
      MissingPersonReport(
        reportId: 'MP-801',
        personName: 'Ali Raza',
        age: 11,
        gender: 'Male',
        lastSeenLocation: 'Near Jinnah Abad Park, Abbottabad',
        description:
            'Wearing navy blue polo shirt and jeans. Responds to nickname Ali.',
        contactName: 'Raza Ullah (Father)',
        contactPhone: '0301-5554321',
        status: 'Searching',
        reportedAt: DateTime.now().subtract(const Duration(hours: 16)),
      ),
      MissingPersonReport(
        reportId: 'MP-802',
        personName: 'Bibi Zainab',
        age: 72,
        gender: 'Female',
        lastSeenLocation: 'Fawwara Chowk, Abbottabad',
        description:
            'Elderly woman with mild dementia, wearing grey shawl and spectacles.',
        contactName: 'Tariq Mehmood (Son)',
        contactPhone: '0312-9988776',
        status: 'Found',
        reportedAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      MissingPersonReport(
        reportId: 'MP-803',
        personName: 'Hamza Bilal',
        age: 19,
        gender: 'Male',
        lastSeenLocation: 'Main Bazar, Haripur',
        description: 'Black jacket, brown trousers, carrying school backpack.',
        contactName: 'Bilal Ahmed',
        contactPhone: '0344-1234567',
        status: 'Reunited',
        reportedAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
    ]);

    _broadcastAll();
  }

  void _broadcastAll() {
    if (_disposed) {
      return;
    }
    _requestsController.add(List.unmodifiable(_mockRequests));
    _donationsController.add(List.unmodifiable(_mockDonations));
    _donorsController.add(List.unmodifiable(_mockBloodDonors));
    _bloodNeedsController.add(List.unmodifiable(_mockBloodNeeds));
    _chatController.add(List.unmodifiable(_mockChatMessages));
    _feedbackController.add(List.unmodifiable(_mockFeedback));
    _usersController.add(List.unmodifiable(_mockUsers));
    _missingPersonsController.add(List.unmodifiable(_mockMissingPersons));
    _employeesController.add(getAllEmployees());
    _auditController.add(List.unmodifiable(_auditEvents));
    notifyListeners();
  }

  // ================= Requests =================

  Stream<List<EmergencyRequest>> getRequestsStream() async* {
    if (isLiveFirebase) {
      yield* _firestore!
          .collection(AppConstants.requestsCollection)
          .orderBy('createdAt', descending: true)
          .snapshots(includeMetadataChanges: true)
          .map((snapshot) {
            final remote = snapshot.docs
                .map((doc) => EmergencyRequest.fromFirestore(doc))
                .toList();
            final remoteIds = remote.map((item) => item.requestId).toSet();
            return [
              ..._pendingEmergencyWrites.values.where(
                (item) => !remoteIds.contains(item.requestId),
              ),
              ...remote,
            ];
          });
      return;
    }
    yield kIsWeb ? const [] : List.unmodifiable(_mockRequests);
    yield* _requestsController.stream;
  }

  Stream<EmergencyRequest?> getRequestStream(String id) async* {
    if (isLiveFirebase) {
      yield* _firestore!
          .collection(AppConstants.requestsCollection)
          .doc(id)
          .snapshots()
          .map(
            (doc) => doc.exists
                ? EmergencyRequest.fromFirestore(doc)
                : _pendingEmergencyWrites[id],
          );
    } else {
      yield _mockRequests.where((r) => r.requestId == id).firstOrNull;
      yield* _requestsController.stream.map(
        (list) => list.where((r) => r.requestId == id).firstOrNull,
      );
    }
  }

  Stream<List<EmergencyRequest>> getUserRequestsStream(String userId) async* {
    if (userId.isEmpty) {
      yield const [];
      return;
    }
    if (isLiveFirebase) {
      yield* _firestore!
          .collection(AppConstants.requestsCollection)
          .where('userId', isEqualTo: userId)
          .snapshots()
          .map(
            (snapshot) => _activeRequests([
              ...snapshot.docs.map(EmergencyRequest.fromFirestore),
              ..._pendingEmergencyWrites.values.where(
                (r) =>
                    r.userId == userId &&
                    !snapshot.docs.any((doc) => doc.id == r.requestId),
              ),
            ]),
          );
    } else {
      yield _activeRequests(_mockRequests.where((r) => r.userId == userId));
      yield* _requestsController.stream.map(
        (list) => _activeRequests(list.where((r) => r.userId == userId)),
      );
    }
  }

  Stream<List<EmergencyRequest>> getAssignedRequestsStream(
    String employeeId,
  ) async* {
    if (employeeId.isEmpty) {
      yield const [];
      return;
    }
    if (isLiveFirebase) {
      yield* _firestore!
          .collection(AppConstants.requestsCollection)
          .where('assignedEmployeeId', isEqualTo: employeeId)
          .snapshots()
          .map(
            (snapshot) => _activeRequests(
              snapshot.docs.map(EmergencyRequest.fromFirestore),
            ),
          );
    } else {
      yield _activeRequests(
        _mockRequests.where((r) => r.assignedEmployeeId == employeeId),
      );
      yield* _requestsController.stream.map(
        (list) => _activeRequests(
          list.where((r) => r.assignedEmployeeId == employeeId),
        ),
      );
    }
  }

  List<EmergencyRequest> _activeRequests(Iterable<EmergencyRequest> requests) {
    final list = requests
        .where(
          (r) =>
              r.status != EmergencyStatus.completed &&
              r.status != EmergencyStatus.cancelled,
        )
        .toList();
    list.sort(
      (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
        a.createdAt ?? DateTime(1970),
      ),
    );
    return list;
  }

  NearestAmbulanceResult? findNearestAvailableAmbulance(
    double reqLat,
    double reqLng,
  ) {
    if (!RequestLocation(
      latitude: reqLat,
      longitude: reqLng,
    ).hasValidCoordinates) {
      return null;
    }
    final pool = isLiveFirebase ? _liveEmployees : _mockEmployees;
    final available = pool
        .where(
          (e) =>
              e.role == 'driver' &&
              e.status == 'available' &&
              e.hasValidLocation &&
              (simulatedFleetEnabled ||
                  !isLiveFirebase ||
                  e.hasFreshGps(DateTime.now())),
        )
        .toList();

    if (available.isEmpty) {
      return null;
    }

    Employee? bestDriver;
    double minDistance = double.infinity;

    for (final driver in available) {
      final dist = LocationService.calculateDistanceInKm(
        driver.currentLat,
        driver.currentLng,
        reqLat,
        reqLng,
      );
      if (dist < minDistance) {
        minDistance = dist;
        bestDriver = driver;
      }
    }

    if (bestDriver == null) {
      return null;
    }
    final eta = LocationService.calculateEtaMinutes(
      minDistance,
      averageSpeedKmH: 45,
    );
    return NearestAmbulanceResult(
      employee: bestDriver,
      distanceKm: minDistance,
      etaMinutes: eta,
    );
  }

  Future<NearestAmbulanceResult?> autoDispatchNearestAmbulance(
    String requestId,
  ) async {
    EmergencyRequest? req;
    if (isLiveFirebase) {
      final doc = await _firestore!
          .collection(AppConstants.requestsCollection)
          .doc(requestId)
          .get();
      if (doc.exists && doc.data() != null) {
        req = EmergencyRequest.fromFirestore(doc);
      }
    } else {
      final reqIndex = _mockRequests.indexWhere(
        (r) => r.requestId == requestId,
      );
      if (reqIndex != -1) {
        req = _mockRequests[reqIndex];
      }
    }
    if (req == null) {
      return null;
    }
    if (!req.location.hasValidCoordinates) {
      throw StateError('Confirm the patient location before dispatch.');
    }
    if (req.status != EmergencyStatus.pending &&
        req.status != EmergencyStatus.approved) {
      return null;
    }
    if (req.fraudRiskLevel == 'High' && !req.isVerified) {
      return null;
    }

    final reqLat = req.location.latitude != 0.0
        ? req.location.latitude
        : LocationService.defaultLocation.latitude;
    final reqLng = req.location.longitude != 0.0
        ? req.location.longitude
        : LocationService.defaultLocation.longitude;

    final destination = LatLng(reqLat, reqLng);
    final candidates =
        getAvailableDrivers().where((e) => e.hasValidLocation).toList()..sort(
          (a, b) =>
              const Distance()(
                LatLng(a.currentLat, a.currentLng),
                destination,
              ).compareTo(
                const Distance()(
                  LatLng(b.currentLat, b.currentLng),
                  destination,
                ),
              ),
        );
    Object? lastError;
    for (final candidate in candidates) {
      try {
        await assignRequest(
          requestId: requestId,
          employeeId: candidate.employeeId,
          employeeName: '${candidate.name} (${candidate.vehicleNumber})',
        );
        final distance = const Distance().as(
          LengthUnit.Kilometer,
          LatLng(candidate.currentLat, candidate.currentLng),
          destination,
        );
        return NearestAmbulanceResult(
          employee: candidate,
          distanceKm: distance,
          etaMinutes:
              (getTransitPlayback(
                        candidate.employeeId,
                      )?.remainingSecondsAt(_now()) ??
                      60) ~/
                  60 +
              1,
        );
      } catch (error) {
        // Another admin may have reserved this unit or completed this request.
        final current = await getRequestStream(requestId).first;
        if (current == null ||
            ![
              EmergencyStatus.pending,
              EmergencyStatus.approved,
            ].contains(current.status)) {
          return null;
        }
        lastError = error;
      }
    }
    if (lastError != null) {
      throw StateError('No available unit could be routed: $lastError');
    }
    return null;
  }

  /// Authorized admin client processes the shared queue; citizens cannot write
  /// fleet reservations. Multiple admin clients are safe through assignRequest's
  /// atomic request/unit checks. A server worker is needed for unattended use.
  Future<void> dispatchQueuedRequests() async {
    if (_disposed ||
        _autoDispatchBusy ||
        !automaticSimulation ||
        (isLiveFirebase &&
            (_sessionRole != AppRoles.admin || !_routesLoaded))) {
      return;
    }
    _autoDispatchBusy = true;
    final session = _sessionUserId;
    try {
      final queue =
          (isLiveFirebase ? _simulationRequests.values : _mockRequests)
              .where(
                (r) =>
                    [
                      EmergencyStatus.pending,
                      EmergencyStatus.approved,
                    ].contains(r.status) &&
                    (r.fraudRiskLevel != 'High' || r.isVerified) &&
                    r.location.hasValidCoordinates,
              )
              .toList();
      int rank(EmergencyRequest r) =>
          int.tryParse(
            RegExp(r'P([1-4])').firstMatch(r.priority)?.group(1) ?? '',
          ) ??
          4;
      queue.sort((a, b) {
        final priority = rank(a).compareTo(rank(b));
        return priority != 0
            ? priority
            : (a.createdAt ?? DateTime(1970)).compareTo(
                b.createdAt ?? DateTime(1970),
              );
      });
      for (final request in queue) {
        if (_disposed ||
            (isLiveFirebase &&
                (_sessionUserId != session ||
                    _sessionRole != AppRoles.admin))) {
          break;
        }
        if (getAvailableDrivers().where((e) => e.hasValidLocation).isEmpty) {
          break;
        }
        if (_autoDispatchRetryAt[request.requestId]?.isAfter(_now()) == true) {
          continue;
        }
        try {
          await autoDispatchNearestAmbulance(request.requestId);
          _autoDispatchRetryAt.remove(request.requestId);
        } catch (error) {
          _autoDispatchRetryAt[request.requestId] = _now().add(
            const Duration(seconds: 30),
          );
          debugPrint('Automatic dispatch retry: $error');
        }
      }
    } finally {
      _autoDispatchBusy = false;
    }
  }

  Future<String> submitEmergencyRequest(
    EmergencyRequest request, {
    bool autoAssignNearest = false,
  }) async {
    final usage = await getEmergencyUsage(request.userId);
    if (usage.isBanned(_now())) {
      throw StateError(
        usage.adminBanned
            ? 'Emergency requests blocked by Operations. Contact Operations to restore access, or call Edhi 115 for urgent help.'
            : 'Emergency requests blocked until ${usage.bannedUntil!.toLocal()} after three cancellations. Call Edhi 115 for urgent help.',
      );
    }
    if (request.userId.isEmpty || !request.location.hasValidCoordinates) {
      throw ArgumentError(
        'Confirm your location using GPS or the map before requesting an ambulance.',
      );
    }
    final requestId = _newRecordId('REQ');

    var comparisonRequests = List<EmergencyRequest>.of(_mockRequests);
    if (isLiveFirebase) {
      try {
        final snapshot = await _firestore!
            .collection(AppConstants.requestsCollection)
            .where('userId', isEqualTo: request.userId)
            .get();
        comparisonRequests = snapshot.docs
            .map(EmergencyRequest.fromFirestore)
            .toList(growable: false);
      } catch (e) {
        debugPrint('Live request risk comparison fallback: $e');
      }
    }

    // AI Prioritization classification (Increment 3)
    final priority = AITriageService.classifyPriority(
      emergencyType: request.emergencyType,
      description: request.description,
    );

    // AI Duplicate Detection (Proposal Module 9)
    final duplicateMatch = AITriageService.detectDuplicate(
      newLoc: request.location,
      activeRequests: comparisonRequests,
    );

    // AI Fraud & Prank Detection (Security & Integrity Engine)
    final fraudAssessment = AITriageService.assessFraudRisk(
      description: request.description,
      userPhone: request.userPhone,
      location: request.location,
      recentRequests: comparisonRequests,
    );

    // Citizens create Pending only. The authorized admin dispatcher reserves
    // available units; offline tests use the same transactional assignment path.
    NearestAmbulanceResult? nearest;

    final newRequest = request.copyWith(
      requestId: requestId,
      status: EmergencyStatus.pending,
      assignedEmployeeId: null,
      assignedEmployeeName: null,
      priority: priority,
      isDuplicate: duplicateMatch != null,
      duplicateOfRequestId: duplicateMatch?.requestId,
      fraudRiskScore: fraudAssessment.score,
      fraudRiskLevel: fraudAssessment.level,
      fraudReason: fraudAssessment.reasons.isNotEmpty
          ? fraudAssessment.reasons.join('; ')
          : null,
      isVerified: fraudAssessment.score < 0.30,
      createdAt: _now(),
    );

    if (isLiveFirebase) {
      try {
        await _firestore!
            .collection(AppConstants.requestsCollection)
            .doc(requestId)
            .set({
              ...newRequest.toMap(),
              'createdAt': FieldValue.serverTimestamp(),
            });
      } catch (error) {
        if (error is FirebaseException &&
            !const ['unavailable', 'deadline-exceeded'].contains(error.code)) {
          rethrow;
        }
        // Keep the SOS visible and retryable even when a web client loses its
        // connection. Native Firestore also keeps its own durable write queue.
        _pendingEmergencyWrites[requestId] = newRequest;
        _mockRequests.removeWhere((item) => item.requestId == requestId);
        _mockRequests.insert(0, newRequest);
        _broadcastAll();
        debugPrint('Emergency queued for retry: $error');
      }
    } else {
      _mockRequests.insert(0, newRequest);
      _broadcastAll();
    }

    if (autoAssignNearest &&
        !isLiveFirebase &&
        fraudAssessment.level != 'High') {
      try {
        nearest = await autoDispatchNearestAmbulance(requestId);
      } catch (error) {
        debugPrint('Request remains queued for dispatch: $error');
      }
    }
    _notificationService?.sendNotification(
      userId: request.userId,
      title: fraudAssessment.level == 'High'
          ? 'Emergency Request Under Review #${newRequest.requestId}'
          : (nearest != null
                ? 'Ambulance Dispatched #${newRequest.requestId} (${nearest.employee.vehicleNumber})'
                : 'Emergency Request #${newRequest.requestId} ($priority)'),
      message: fraudAssessment.level == 'High'
          ? 'Flagged for dispatcher verification: ${newRequest.fraudReason ?? "Suspicious activity detected"}'
          : (nearest != null
                ? 'Nearest unit ${nearest.employee.vehicleNumber} has been dispatched to ${newRequest.location.address} (ETA ~${nearest.etaMinutes} min)'
                : 'New ${newRequest.emergencyType} submitted at ${newRequest.location.address}'),
      type: 'emergency',
    );

    await _logAudit(
      action: _pendingEmergencyWrites.containsKey(requestId)
          ? 'queued_offline'
          : 'created',
      entityType: 'emergency',
      entityId: requestId,
      actorId: request.userId,
      details: '${request.emergencyType} at ${request.location.address}',
    );

    return requestId;
  }

  Future<int> retryPendingEmergencyWrites() async {
    if (!isLiveFirebase || _pendingEmergencyWrites.isEmpty) {
      return 0;
    }
    var synced = 0;
    for (final entry in List.of(_pendingEmergencyWrites.entries)) {
      try {
        await _firestore!
            .collection(AppConstants.requestsCollection)
            .doc(entry.key)
            .set({
              ...entry.value.toMap(),
              'createdAt': FieldValue.serverTimestamp(),
            });
        _pendingEmergencyWrites.remove(entry.key);
        _mockRequests.removeWhere((item) => item.requestId == entry.key);
        synced++;
        await _logAudit(
          action: 'synced',
          entityType: 'emergency',
          entityId: entry.key,
          actorId: entry.value.userId,
          details: 'Offline SOS synchronized with operations center',
        );
      } catch (_) {
        // Keep remaining records queued for the next retry.
      }
    }
    _broadcastAll();
    notifyListeners();
    return synced;
  }

  Future<EmergencyUsage> getEmergencyUsage(String userId) async {
    if (!isLiveFirebase) {
      return _mockUsage[userId] ?? const EmergencyUsage();
    }
    final doc = await _firestore!
        .collection('emergency_usage')
        .doc(userId)
        .get();
    return EmergencyUsage.fromMap(doc.data() ?? {});
  }

  Stream<EmergencyUsage> watchEmergencyUsage(String userId) async* {
    if (!isLiveFirebase) {
      yield _mockUsage[userId] ?? const EmergencyUsage();
      yield* _requestsController.stream.map(
        (_) => _mockUsage[userId] ?? const EmergencyUsage(),
      );
    } else {
      yield* _firestore!
          .collection('emergency_usage')
          .doc(userId)
          .snapshots()
          .map((doc) => EmergencyUsage.fromMap(doc.data() ?? {}));
    }
  }

  Future<EmergencyUsage> cancelEmergencyRequest(
    String requestId,
    String userId,
  ) async {
    EmergencyUsage result = const EmergencyUsage();
    String? employeeId;
    void validate(
      EmergencyRequest request,
      EmergencyUsage usage,
      DateTime now,
    ) {
      if (request.userId != userId) {
        throw StateError('This is not your request.');
      }
      if (!EmergencyUsage.canCancel(request, now)) {
        throw StateError(
          'Cancellation closes 60 seconds after you submit your request. Driver assignment does not reset this window. Contact Operations or call 115.',
        );
      }
      if (usage.isBanned(now)) {
        throw StateError(
          'Requests are blocked for 24 hours. Call 115 for urgent help.',
        );
      }
    }

    if (isLiveFirebase) {
      final ref = _firestore!
          .collection(AppConstants.requestsCollection)
          .doc(requestId);
      final usageRef = _firestore!.collection('emergency_usage').doc(userId);
      await _firestore!.runTransaction((tx) async {
        final doc = await tx.get(ref);
        final usageDoc = await tx.get(usageRef);
        if (!doc.exists) {
          throw StateError('Request no longer exists.');
        }
        final request = EmergencyRequest.fromFirestore(doc);
        final usage = EmergencyUsage.fromMap(usageDoc.data() ?? {});
        final now = _now();
        validate(request, usage, now);
        employeeId = request.assignedEmployeeId;
        DocumentSnapshot<Map<String, dynamic>>? employee;
        if (employeeId != null) {
          employee = await tx.get(
            _firestore!
                .collection(AppConstants.employeesCollection)
                .doc(employeeId),
          );
        }
        final demoRef = employeeId == null
            ? null
            : _firestore!.collection('route_demos').doc(employeeId);
        final demo = demoRef == null ? null : await tx.get(demoRef);
        result = usage.afterCancellation(now);
        tx.set(usageRef, {
          'cancellationCount': result.cancellationCount,
          'windowStartedAt': usage.startsNewWindow(now)
              ? FieldValue.serverTimestamp()
              : Timestamp.fromDate(usage.windowStartedAt!),
          'banStartedAt': result.cancellationCount >= 3
              ? FieldValue.serverTimestamp()
              : null,
          'lastCancelledRequestId': requestId,
        });
        tx.update(ref, {
          'status': EmergencyStatus.cancelled,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (employee?.exists == true &&
            employee!.data()?['activeRequestId'] == requestId) {
          tx.update(employee.reference, {
            'status': 'available',
            'activeRequestId': '',
            'speedKmh': 0,
          });
        }
        if (demo?.exists == true &&
            demo!.data()?['requestId'] == requestId &&
            demo.data()?['enabled'] == true) {
          tx.update(demoRef!, {
            'enabled': false,
            'stoppedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } else {
      final index = _mockRequests.indexWhere((r) => r.requestId == requestId);
      if (index < 0) {
        throw StateError('Request no longer exists.');
      }
      final request = _mockRequests[index];
      final usage = _mockUsage[userId] ?? const EmergencyUsage();
      final now = _now();
      validate(request, usage, now);
      result = usage.afterCancellation(now);
      _mockUsage[userId] = result;
      employeeId = request.assignedEmployeeId;
      await updateRequestStatus(requestId, EmergencyStatus.cancelled);
    }
    if (employeeId != null) {
      _pendingTransitStarts.remove(employeeId);
    }
    _broadcastAll();
    return result;
  }

  Future<void> updateRequestStatus(
    String requestId,
    String status, {
    bool adminOverride = false,
    String? fraudReason,
    String? completingDriverUserId,
  }) async {
    if (adminOverride && isLiveFirebase && _sessionRole != AppRoles.admin) {
      throw StateError('Only admin can override a response.');
    }
    if (!EmergencyStatus.all.contains(status)) {
      throw ArgumentError('Unsupported status');
    }
    String? assignedEmployeeId;
    String userId = '';
    void validate(String current) {
      if ((adminOverride || _sessionRole == AppRoles.admin) &&
          status == EmergencyStatus.cancelled &&
          ![
            EmergencyStatus.completed,
            EmergencyStatus.cancelled,
          ].contains(current)) {
        return;
      }
      if (!EmergencyStatus.canTransition(current, status)) {
        throw StateError(
          'Cannot change $current to $status. Refresh the request and try again.',
        );
      }
    }

    if (isLiveFirebase) {
      final ref = _firestore!
          .collection(AppConstants.requestsCollection)
          .doc(requestId);
      await _firestore!.runTransaction((transaction) async {
        final doc = await transaction.get(ref);
        if (!doc.exists) {
          throw StateError('Request no longer exists.');
        }
        final request = EmergencyRequest.fromFirestore(doc);
        validate(request.status);
        assignedEmployeeId = request.assignedEmployeeId;
        userId = request.userId;
        DocumentSnapshot<Map<String, dynamic>>? employee;
        DocumentSnapshot<Map<String, dynamic>>? demo;
        final terminal =
            status == EmergencyStatus.completed ||
            status == EmergencyStatus.cancelled;
        if ((terminal || status == EmergencyStatus.arrived) &&
            assignedEmployeeId != null) {
          employee = await transaction.get(
            _firestore!
                .collection(AppConstants.employeesCollection)
                .doc(assignedEmployeeId),
          );
          demo = await transaction.get(
            _firestore!.collection('route_demos').doc(assignedEmployeeId),
          );
        }
        if (completingDriverUserId != null &&
            (status != EmergencyStatus.completed ||
                request.status != EmergencyStatus.arrived ||
                employee?.data()?['userId'] != completingDriverUserId ||
                employee?.data()?['activeRequestId'] != requestId)) {
          throw StateError(
            'Only the linked driver can complete this current job after arrival.',
          );
        }
        transaction.update(ref, {
          'status': status,
          'fraudReason': ?fraudReason,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (employee?.exists == true &&
            employee!.data()?['activeRequestId'] == requestId) {
          final parked = demo?.exists == true
              ? RoutePlayback.fromMap(demo!.data()!).positionAt(_now())
              : null;
          transaction.update(employee.reference, {
            'status': terminal ? 'available' : 'busy',
            if (_sessionRole == AppRoles.admin) ...{
              if (terminal) 'activeRequestId': '',
              if (parked != null) 'currentLat': parked.latitude,
              if (parked != null) 'currentLng': parked.longitude,
              'speedKmh': 0,
            },
          });
        }
        if (demo?.exists == true &&
            demo!.data()?['requestId'] == requestId &&
            (_sessionRole == AppRoles.admin ||
                demo.data()?['enabled'] == true)) {
          transaction.update(demo.reference, {
            'enabled': false,
            'stoppedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } else {
      final index = _mockRequests.indexWhere((r) => r.requestId == requestId);
      if (index < 0) {
        throw StateError('Request no longer exists.');
      }
      final request = _mockRequests[index];
      validate(request.status);
      if (completingDriverUserId != null &&
          (status != EmergencyStatus.completed ||
              request.status != EmergencyStatus.arrived ||
              !_mockEmployees.any(
                (e) =>
                    e.employeeId == request.assignedEmployeeId &&
                    e.userId == completingDriverUserId &&
                    e.status == 'busy',
              ))) {
        throw StateError(
          'Only the linked driver can complete this current job after arrival.',
        );
      }
      userId = request.userId;
      assignedEmployeeId = request.assignedEmployeeId;
      _mockRequests[index] = request.copyWith(
        status: status,
        fraudReason: fraudReason,
        updatedAt: DateTime.now(),
      );
      if (status == EmergencyStatus.completed ||
          status == EmergencyStatus.cancelled ||
          status == EmergencyStatus.arrived) {
        final employeeIndex = _mockEmployees.indexWhere(
          (e) => e.employeeId == assignedEmployeeId,
        );
        if (employeeIndex >= 0) {
          final route = _routeDemos[assignedEmployeeId];
          final parked = route?.positionAt(_now());
          _mockEmployees[employeeIndex] = _mockEmployees[employeeIndex]
              .copyWith(
                status: status == EmergencyStatus.arrived
                    ? 'busy'
                    : 'available',
                activeRequestId: status == EmergencyStatus.arrived ? null : '',
                currentLat: parked?.latitude,
                currentLng: parked?.longitude,
                speedKmh: 0,
              );
          if (route != null) {
            _routeDemos[assignedEmployeeId!] = RoutePlayback(
              requestId: route.requestId,
              points: route.points,
              startedAt: route.startedAt,
              durationSeconds: route.durationSeconds,
              speedFactor: route.speedFactor,
              enabled: false,
              pausedAt: route.pausedAt,
              stoppedAt: _now(),
            );
          }
        }
      }
      _broadcastAll();
    }
    if (assignedEmployeeId != null &&
        (status == EmergencyStatus.arrived ||
            status == EmergencyStatus.completed ||
            status == EmergencyStatus.cancelled)) {
      _pendingTransitStarts.remove(assignedEmployeeId);
    }
    _notificationService?.sendNotification(
      userId: userId,
      title: 'Dispatch update',
      message: 'Request #$requestId: $status',
      type: 'emergency',
    );
    await _logAudit(
      action: 'status_changed',
      entityType: 'emergency',
      entityId: requestId,
      actorId: assignedEmployeeId ?? 'dispatcher',
      details: 'Status changed to $status',
    );
  }

  /// Manually clears a flagged emergency request as verified by the human dispatcher.
  Future<void> verifyEmergencyRequest(String requestId) async {
    if (isLiveFirebase) {
      await _firestore!
          .collection(AppConstants.requestsCollection)
          .doc(requestId)
          .update({
            'isVerified': true,
            'fraudRiskLevel': 'Low',
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } else {
      final index = _mockRequests.indexWhere((r) => r.requestId == requestId);
      if (index != -1) {
        _mockRequests[index] = _mockRequests[index].copyWith(
          isVerified: true,
          fraudRiskLevel: 'Low',
          updatedAt: DateTime.now(),
        );
        _broadcastAll();
      }
    }

    _notificationService?.sendNotification(
      userId: 'all',
      title: 'Request Verified: #$requestId',
      message:
          'Dispatcher verified emergency request #$requestId as legitimate.',
      type: 'emergency',
    );
    await _logAudit(
      action: 'fraud_check_verified',
      entityType: 'emergency',
      entityId: requestId,
      actorId: 'dispatcher',
      details: 'Human dispatcher marked the request as legitimate',
    );
  }

  /// Admin rejection also freezes movement and releases only this assignment.
  Future<void> rejectFraudEmergencyRequest(
    String requestId, {
    String reason = 'Flagged as fake/prank call',
  }) async {
    await updateRequestStatus(
      requestId,
      EmergencyStatus.cancelled,
      adminOverride: true,
      fraudReason: reason,
    );
    await _logAudit(
      action: 'rejected',
      entityType: 'emergency',
      entityId: requestId,
      actorId: _sessionUserId ?? 'dispatcher',
      details: reason,
    );
  }

  Future<void> assignRequest({
    required String requestId,
    required String employeeId,
    required String employeeName,
  }) async {
    EmergencyRequest? request;
    if (isLiveFirebase) {
      final requestDoc = await _firestore!
          .collection(AppConstants.requestsCollection)
          .doc(requestId)
          .get();
      if (requestDoc.exists && requestDoc.data() != null) {
        request = EmergencyRequest.fromFirestore(requestDoc);
      }
    } else {
      request = _mockRequests
          .where((item) => item.requestId == requestId)
          .firstOrNull;
    }

    if (request == null) {
      throw StateError('Emergency request $requestId no longer exists.');
    }
    if (!request.location.hasValidCoordinates) {
      throw StateError(
        'Confirm the patient map location before assigning an ambulance.',
      );
    }
    if (request.status != EmergencyStatus.pending &&
        request.status != EmergencyStatus.approved) {
      throw StateError(
        'Only pending or approved emergencies can be dispatched.',
      );
    }
    if (request.fraudRiskLevel == 'High' && !request.isVerified) {
      throw StateError(
        'Verify this high-risk request before assigning an ambulance.',
      );
    }

    final driver = getAllEmployees()
        .where((employee) => employee.employeeId == employeeId)
        .firstOrNull;
    if (driver == null || driver.role != 'driver') {
      throw StateError('The selected ambulance driver is no longer available.');
    }
    if (!driver.hasValidLocation) {
      throw StateError(
        'Choose a valid staging point for this ambulance first.',
      );
    }
    if (driver.status != 'available') {
      throw StateError(
        '${driver.name} is currently ${driver.status}. Select another unit.',
      );
    }

    // Obtain a usable road route BEFORE reserving either request or ambulance.
    // A routing failure must not leave a busy unit stuck on an assigned job.
    final simulationSpeed = _simulationSpeed;
    final route = automaticSimulation
        ? await _loadSimulationRoute(
            LatLng(driver.currentLat, driver.currentLng),
            LatLng(request.location.latitude, request.location.longitude),
          )
        : null;
    final points = route == null
        ? <LatLng>[]
        : _boundedRoutePoints(route.points);
    final duration = route == null
        ? 1.0
        : (route.travelSeconds / simulationSpeed).clamp(1.0, 86400.0);

    if (isLiveFirebase) {
      final requestRef = _firestore!
          .collection(AppConstants.requestsCollection)
          .doc(requestId);
      final driverRef = _firestore!
          .collection(AppConstants.employeesCollection)
          .doc(employeeId);
      await _firestore!.runTransaction((transaction) async {
        final currentRequest = await transaction.get(requestRef);
        final currentDriver = await transaction.get(driverRef);
        final data = currentRequest.data();
        if (data == null ||
            !const [
              EmergencyStatus.pending,
              EmergencyStatus.approved,
            ].contains(data['status'])) {
          throw StateError(
            'This request has already changed. Refresh and try again.',
          );
        }
        if (data['fraudRiskLevel'] == 'High' && data['isVerified'] != true) {
          throw StateError('Verify this request first.');
        }
        if (currentDriver.data()?['status'] != 'available' ||
            currentDriver.data()?['role'] != 'driver') {
          throw StateError('This driver is no longer available.');
        }
        transaction.update(requestRef, {
          'status': automaticSimulation
              ? EmergencyStatus.inProgress
              : EmergencyStatus.assigned,
          'assignedEmployeeId': employeeId,
          'assignedEmployeeName': employeeName,
          'assignedDriverUserId': currentDriver.data()?['userId'],
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(driverRef, {
          'status': 'busy',
          'activeRequestId': requestId,
        });
        // New shared journey replaces the previous patient's route atomically.
        transaction.set(_firestore!.collection('route_demos').doc(employeeId), {
          'requestId': requestId,
          'userId': data['userId'],
          'driverUserId': currentDriver.data()?['userId'],
          'enabled': automaticSimulation,
          'points': points
              .map((p) => {'lat': p.latitude, 'lng': p.longitude})
              .toList(),
          'startedAt': FieldValue.serverTimestamp(),
          'durationSeconds': duration,
          'speedFactor': simulationSpeed,
          'pausedAt': null,
          'stoppedAt': null,
          'simulation': true,
        });
      });
    } else {
      final index = _mockRequests.indexWhere((r) => r.requestId == requestId);
      if (index != -1) {
        final req = _mockRequests[index];
        final latestDriver = _mockEmployees
            .where((e) => e.employeeId == employeeId)
            .firstOrNull;
        if (latestDriver?.status != 'available' ||
            ![
              EmergencyStatus.pending,
              EmergencyStatus.approved,
            ].contains(req.status)) {
          throw StateError(
            'Request or ambulance was already assigned while routing.',
          );
        }
        _mockRequests[index] = req.copyWith(
          status: automaticSimulation
              ? EmergencyStatus.inProgress
              : EmergencyStatus.assigned,
          assignedEmployeeId: employeeId,
          assignedEmployeeName: employeeName,
          updatedAt: DateTime.now(),
        );

        // Mark assigned driver as busy
        final empIdx = _mockEmployees.indexWhere(
          (e) => e.employeeId == employeeId,
        );
        if (empIdx != -1) {
          _mockEmployees[empIdx] = _mockEmployees[empIdx].copyWith(
            status: 'busy',
            activeRequestId: requestId,
          );
        }
        if (automaticSimulation) {
          _routeDemos[employeeId] = RoutePlayback(
            requestId: requestId,
            points: points,
            startedAt: _now(),
            durationSeconds: duration,
            speedFactor: simulationSpeed,
          );
          _ensureDemoTicker();
        }
        _broadcastAll();
      }
    }

    _notificationService?.sendNotification(
      userId: 'all',
      title: 'Ambulance Dispatched: #$requestId',
      message:
          'Ambulance unit $employeeName has been assigned to request #$requestId',
      type: 'emergency',
    );
    await _logAudit(
      action: 'ambulance_assigned',
      entityType: 'emergency',
      entityId: requestId,
      actorId: employeeId,
      details: 'Assigned to $employeeName',
    );
  }

  // ================= Shared simulated fleet journeys =================
  bool isTransitActive(String employeeId) =>
      _routeDemos[employeeId]?.movingAt(_now()) ?? false;
  bool isTransitPaused(String employeeId) =>
      _routeDemos[employeeId]?.pausedAt != null &&
      _routeDemos[employeeId]?.enabled == true;
  double getTransitSpeed(String employeeId) =>
      _routeDemos[employeeId]?.speedFactor ?? _simulationSpeed;
  RoutePlayback? getTransitPlayback(String employeeId) =>
      _routeDemos[employeeId];
  List<LatLng>? getRemainingTransitRoute(String employeeId) =>
      _routeDemos[employeeId]?.remainingPointsAt(_now());

  void setDefaultSimulationSpeed(double speed) {
    _validateSimulationSpeed(speed);
    _simulationSpeed = speed;
    notifyListeners();
  }

  void _validateSimulationSpeed(double speed) {
    if (![1.0, 3.0, 10.0].contains(speed)) {
      throw ArgumentError('Choose 1×, 3× or 10× playback speed.');
    }
  }

  List<LatLng> _boundedRoutePoints(List<LatLng> points) => points.length <= 4000
      ? points
      : List.generate(
          4000,
          (i) => points[(i * (points.length - 1) / 3999).round()],
        );

  Future<RoadRouteResult> _loadSimulationRoute(
    LatLng origin,
    LatLng destination,
  ) async {
    final route = await _roadLoader(origin, destination);
    if (!route.isRealRoadRoute ||
        route.points.length < 2 ||
        !route.travelSeconds.isFinite ||
        route.travelSeconds <= 0 ||
        route.points.any(
          (p) => !RequestLocation(
            latitude: p.latitude,
            longitude: p.longitude,
          ).hasValidCoordinates,
        )) {
      throw StateError(
        'A usable road route is unavailable. Nothing was dispatched; retry when connected.',
      );
    }
    if (const Distance().as(LengthUnit.Meter, route.points.first, origin) >
            1500 ||
        const Distance().as(LengthUnit.Meter, route.points.last, destination) >
            1000) {
      throw StateError(
        'The staging point or patient pin is too far from a drivable road. Adjust the pin.',
      );
    }
    return route;
  }

  void _ensureDemoTicker() {
    _demoTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed || _employeesController.isClosed) {
        return;
      }
      if (_routeDemos.values.any((route) => route.enabled)) {
        _employeesController.add(getAllEmployees());
        notifyListeners();
      }
      unawaited(reconcileSimulations());
    });
  }

  /// Any authorized mission viewer can commit arrival after the five-second dwell.
  Future<void> reconcileSimulations() async {
    if (_disposed ||
        (isLiveFirebase && !_routesLoaded) ||
        !automaticSimulation) {
      return;
    }
    if (!isLiveFirebase || _sessionRole == AppRoles.admin) {
      await _repairLegacyAssignmentLinks();
      await dispatchQueuedRequests();
    }
    for (final entry in _routeDemos.entries.toList()) {
      final route = entry.value;
      if (!route.arrivalReadyAt(_now()) ||
          !_finishingSimulations.add(entry.key)) {
        continue;
      }
      try {
        await _finishSimulatedArrival(entry.key, route.requestId);
        _simulationErrors.remove(entry.key);
      } catch (error) {
        _simulationErrors[entry.key] =
            'Arrival could not sync. Check Firebase rules/connection.';
        debugPrint('Simulated arrival: $error');
      } finally {
        _finishingSimulations.remove(entry.key);
      }
    }
    if (isLiveFirebase && _sessionRole != AppRoles.admin) {
      return;
    }
    // Resume older active assignments which did not yet have a saved road journey.
    final jobs = isLiveFirebase
        ? _simulationRequests.values.toList()
        : _mockRequests
              .where(
                (r) => [
                  EmergencyStatus.assigned,
                  EmergencyStatus.inProgress,
                ].contains(r.status),
              )
              .toList();
    for (final job in jobs) {
      if (![
        EmergencyStatus.assigned,
        EmergencyStatus.inProgress,
      ].contains(job.status)) {
        continue;
      }
      final id = job.assignedEmployeeId;
      if (id == null || _pendingTransitStarts.contains(id)) continue;
      final existing = _routeDemos[id];
      if (existing != null &&
          existing.requestId == job.requestId &&
          existing.points.isNotEmpty) {
        continue;
      }
      if (_simulationRetryAt[id]?.isAfter(_now()) == true) continue;
      _simulationRetryAt[id] = _now().add(const Duration(seconds: 30));
      unawaited(
        startAutomaticRoadTransit(
          employeeId: id,
          requestId: job.requestId,
          destination: LatLng(job.location.latitude, job.location.longitude),
          speedFactor: _simulationSpeed,
          callerRole: AppRoles.admin,
        ).catchError((Object error) {
          if (_disposed) {
            return;
          }
          _simulationErrors[id] = 'Route unavailable: $error';
          notifyListeners();
        }),
      );
    }
  }

  // Older records lacked activeRequestId. Repair only an unambiguous busy
  // unit's one active job; never guess between multiple patients or overwrite
  // a new reservation. This also lets arrived legacy jobs be released safely.
  Future<void> _repairLegacyAssignmentLinks() async {
    if (_repairingAssignmentLinks) {
      return;
    }
    _repairingAssignmentLinks = true;
    try {
      final jobs = isLiveFirebase ? _simulationRequests.values : _mockRequests;
      for (final employee in getAllEmployees().where(
        (e) => e.status == 'busy' && e.activeRequestId.isEmpty,
      )) {
        final matches = jobs
            .where(
              (r) =>
                  r.assignedEmployeeId == employee.employeeId &&
                  [
                    EmergencyStatus.assigned,
                    EmergencyStatus.inProgress,
                    EmergencyStatus.arrived,
                  ].contains(r.status),
            )
            .toList();
        if (matches.length != 1) continue;
        final job = matches.single;
        if (isLiveFirebase) {
          final employeeRef = _firestore!
              .collection(AppConstants.employeesCollection)
              .doc(employee.employeeId);
          final requestRef = _firestore!
              .collection(AppConstants.requestsCollection)
              .doc(job.requestId);
          await _firestore!.runTransaction((tx) async {
            final freshEmployee = await tx.get(employeeRef);
            final freshRequest = await tx.get(requestRef);
            if (freshEmployee.data()?['status'] != 'busy' ||
                (freshEmployee.data()?['activeRequestId'] as String? ?? '')
                    .isNotEmpty ||
                freshRequest.data()?['assignedEmployeeId'] !=
                    employee.employeeId ||
                ![
                  EmergencyStatus.assigned,
                  EmergencyStatus.inProgress,
                  EmergencyStatus.arrived,
                ].contains(freshRequest.data()?['status'])) {
              return;
            }
            tx.update(employeeRef, {'activeRequestId': job.requestId});
          });
        } else {
          final index = _mockEmployees.indexWhere(
            (e) => e.employeeId == employee.employeeId,
          );
          if (index >= 0 && _mockEmployees[index].activeRequestId.isEmpty) {
            _mockEmployees[index] = _mockEmployees[index].copyWith(
              activeRequestId: job.requestId,
            );
            _broadcastAll();
          }
        }
      }
    } catch (error) {
      debugPrint('Legacy assignment link repair: $error');
    } finally {
      _repairingAssignmentLinks = false;
    }
  }

  Future<void> _finishSimulatedArrival(
    String employeeId,
    String requestId,
  ) async {
    final route = _routeDemos[employeeId];
    if (route == null || route.points.isEmpty) {
      return;
    }
    if (isLiveFirebase) {
      final requestRef = _firestore!
          .collection(AppConstants.requestsCollection)
          .doc(requestId);
      final employeeRef = _firestore!
          .collection(AppConstants.employeesCollection)
          .doc(employeeId);
      final routeRef = _firestore!.collection('route_demos').doc(employeeId);
      await _firestore!.runTransaction((tx) async {
        final request = await tx.get(requestRef);
        final employee = await tx.get(employeeRef);
        final saved = await tx.get(routeRef);
        if (!saved.exists || !employee.exists || !request.exists) {
          return;
        }
        final fresh = RoutePlayback.fromMap(saved.data()!);
        if (fresh.requestId != requestId ||
            !fresh.arrivalReadyAt(_now()) ||
            fresh.points.isEmpty ||
            employee.data()?['activeRequestId'] != requestId ||
            request.data()?['assignedEmployeeId'] != employeeId ||
            ![
              EmergencyStatus.assigned,
              EmergencyStatus.inProgress,
            ].contains(request.data()?['status'])) {
          return;
        }
        tx.update(requestRef, {
          'status': EmergencyStatus.arrived,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(employeeRef, {
          'currentLat': fresh.points.last.latitude,
          'currentLng': fresh.points.last.longitude,
          'speedKmh': 0,
        });
        tx.update(routeRef, {
          'enabled': false,
          'stoppedAt': FieldValue.serverTimestamp(),
        });
      });
    } else {
      final index = _mockRequests.indexWhere(
        (r) =>
            r.requestId == requestId &&
            r.assignedEmployeeId == employeeId &&
            [
              EmergencyStatus.assigned,
              EmergencyStatus.inProgress,
            ].contains(r.status),
      );
      if (index < 0) {
        return;
      }
      _mockRequests[index] = _mockRequests[index].copyWith(
        status: EmergencyStatus.arrived,
        updatedAt: _now(),
      );
      final employeeIndex = _mockEmployees.indexWhere(
        (e) => e.employeeId == employeeId,
      );
      if (employeeIndex >= 0) {
        _mockEmployees[employeeIndex] = _mockEmployees[employeeIndex].copyWith(
          currentLat: route.points.last.latitude,
          currentLng: route.points.last.longitude,
          speedKmh: 0,
        );
      }
      _routeDemos[employeeId] = RoutePlayback(
        requestId: route.requestId,
        points: route.points,
        startedAt: route.startedAt,
        durationSeconds: route.durationSeconds,
        speedFactor: route.speedFactor,
        enabled: false,
        stoppedAt: _now(),
      );
      _broadcastAll();
    }
  }

  Future<void> setTransitSpeed(
    String employeeId,
    double speedMultiplier,
  ) async {
    _validateSimulationSpeed(speedMultiplier);
    await _retimeTransit(employeeId, speedMultiplier);
  }

  Future<void> pauseOrResumeTransit(String employeeId) async {
    final route = _routeDemos[employeeId];
    if (route == null || !route.enabled) {
      throw StateError('No active road journey.');
    }
    await _retimeTransit(
      employeeId,
      route.speedFactor,
      pause: route.pausedAt == null,
    );
  }

  Map<String, dynamic> _playbackMap(RoutePlayback route) => {
    'requestId': route.requestId,
    'enabled': route.enabled,
    'points': route.points
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList(),
    'startedAt': FieldValue.serverTimestamp(),
    'durationSeconds': route.durationSeconds,
    'speedFactor': route.speedFactor,
    'pausedAt': route.pausedAt == null ? null : FieldValue.serverTimestamp(),
    'stoppedAt': null,
    'simulation': true,
  };

  Future<void> _retimeTransit(
    String employeeId,
    double factor, {
    bool? pause,
  }) async {
    if (isLiveFirebase && _sessionRole != AppRoles.admin) {
      throw StateError('Only admin can control route playback.');
    }
    if (isLiveFirebase) {
      final ref = _firestore!.collection('route_demos').doc(employeeId);
      await _firestore!.runTransaction((tx) async {
        final saved = await tx.get(ref);
        if (!saved.exists) {
          throw StateError('No saved journey.');
        }
        final route = RoutePlayback.fromMap(saved.data()!);
        final request = await tx.get(
          _firestore!
              .collection(AppConstants.requestsCollection)
              .doc(route.requestId),
        );
        if (!route.enabled ||
            route.progressAt(_now()) >= 1 ||
            ![
              EmergencyStatus.assigned,
              EmergencyStatus.inProgress,
            ].contains(request.data()?['status']) ||
            request.data()?['assignedEmployeeId'] != employeeId) {
          throw StateError('This journey has ended.');
        }
        final changed = route.retimed(
          _now(),
          factor,
          pause: pause ?? route.pausedAt != null,
        );
        tx.update(ref, _playbackMap(changed));
      });
    } else {
      final route = _routeDemos[employeeId];
      if (route == null || !route.enabled || route.progressAt(_now()) >= 1) {
        throw StateError('This journey has ended.');
      }
      _routeDemos[employeeId] = route.retimed(
        _now(),
        factor,
        pause: pause ?? route.pausedAt != null,
      );
      _broadcastAll();
    }
  }

  Future<void> startAutomaticRoadTransit({
    required String employeeId,
    required String requestId,
    required LatLng destination,
    double speedFactor = 1.0,
    String callerRole = 'user',
  }) async {
    _validateSimulationSpeed(speedFactor);
    if (isLiveFirebase &&
        (callerRole != AppRoles.admin || _sessionRole != AppRoles.admin)) {
      throw StateError('Only admin can start a road journey.');
    }
    if (!_pendingTransitStarts.add(employeeId)) {
      return;
    }
    try {
      final employee = getAllEmployees()
          .where((e) => e.employeeId == employeeId)
          .firstOrNull;
      if (employee == null || !employee.hasValidLocation) {
        throw StateError('Set a valid staging point first.');
      }
      final request = isLiveFirebase
          ? EmergencyRequest.fromFirestore(
              await _firestore!
                  .collection(AppConstants.requestsCollection)
                  .doc(requestId)
                  .get(),
            )
          : _mockRequests.where((r) => r.requestId == requestId).firstOrNull;
      if (request == null ||
          request.assignedEmployeeId != employeeId ||
          ![
            EmergencyStatus.assigned,
            EmergencyStatus.inProgress,
          ].contains(request.status) ||
          !request.location.hasValidCoordinates) {
        throw StateError(
          'This unit needs an active assignment with a valid patient pin.',
        );
      }
      final route = await _loadSimulationRoute(
        LatLng(employee.currentLat, employee.currentLng),
        LatLng(request.location.latitude, request.location.longitude),
      );
      if (_disposed || !_pendingTransitStarts.contains(employeeId)) {
        return;
      }
      final playback = RoutePlayback(
        requestId: requestId,
        points: _boundedRoutePoints(route.points),
        startedAt: _now(),
        durationSeconds: (route.travelSeconds / speedFactor).clamp(
          1.0,
          86400.0,
        ),
        speedFactor: speedFactor,
      );
      if (isLiveFirebase) {
        final ref = _firestore!.collection('route_demos').doc(employeeId);
        final requestRef = _firestore!
            .collection(AppConstants.requestsCollection)
            .doc(requestId);
        final employeeRef = _firestore!
            .collection(AppConstants.employeesCollection)
            .doc(employeeId);
        await _firestore!.runTransaction((tx) async {
          final fresh = await tx.get(requestRef);
          final freshEmployee = await tx.get(employeeRef);
          if (fresh.data()?['assignedEmployeeId'] != employeeId ||
              freshEmployee.data()?['activeRequestId'] != requestId ||
              ![
                EmergencyStatus.assigned,
                EmergencyStatus.inProgress,
              ].contains(fresh.data()?['status'])) {
            throw StateError('Assignment changed while loading the route.');
          }
          tx.set(ref, {
            ..._playbackMap(playback),
            'userId': fresh.data()?['userId'],
            'driverUserId': employee.userId,
          });
          tx.update(requestRef, {
            'status': EmergencyStatus.inProgress,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
      } else {
        _routeDemos[employeeId] = playback;
        final index = _mockRequests.indexWhere((r) => r.requestId == requestId);
        _mockRequests[index] = request.copyWith(
          status: EmergencyStatus.inProgress,
          updatedAt: _now(),
        );
        _broadcastAll();
      }
      _simulationErrors.remove(employeeId);
      _ensureDemoTicker();
    } finally {
      _pendingTransitStarts.remove(employeeId);
    }
  }

  // Compatibility with earlier map controls; stopping now pauses, not teleports.
  Future<void> stopAutomaticRoadTransit(String employeeId) =>
      pauseOrResumeTransit(employeeId);

  Future<void> updateEmployeeLocation(
    String employeeId, {
    required double lat,
    required double lng,
    int? speedKmh,
    int? batteryFuel,
    bool syncToFirestore = true,
    bool recordHeartbeat = false,
    bool clearHeartbeat = false,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final session = clearHeartbeat
        ? null
        : (recordHeartbeat ? _localSessionId : null);
    final heartbeat = clearHeartbeat ? null : (recordHeartbeat ? nowMs : null);
    if (!RequestLocation(latitude: lat, longitude: lng).hasValidCoordinates) {
      throw ArgumentError('Invalid GPS coordinates.');
    }
    if (isLiveFirebase && syncToFirestore) {
      final update = <String, dynamic>{
        'currentLat': lat,
        'currentLng': lng,
        'updatedAt': FieldValue.serverTimestamp(),
        'locationUpdatedAt': FieldValue.serverTimestamp(),
        'speedKmh': ?speedKmh,
        'batteryFuel': ?batteryFuel,
        if (recordHeartbeat) 'transitRunnerSession': _localSessionId,
        if (recordHeartbeat) 'transitLastHeartbeat': nowMs,
        if (clearHeartbeat) 'transitRunnerSession': null,
        if (clearHeartbeat) 'transitLastHeartbeat': null,
      };
      // A denied write must never appear as confirmed live GPS.
      await _firestore!
          .collection(AppConstants.employeesCollection)
          .doc(employeeId)
          .update(update)
          .timeout(const Duration(seconds: 10));
    }
    if (_disposed) {
      return;
    }

    final idx = _mockEmployees.indexWhere((e) => e.employeeId == employeeId);
    if (idx != -1) {
      _mockEmployees[idx] = _mockEmployees[idx].copyWith(
        currentLat: lat,
        currentLng: lng,
        speedKmh: speedKmh ?? _mockEmployees[idx].speedKmh,
        batteryFuel: batteryFuel ?? _mockEmployees[idx].batteryFuel,
        transitRunnerSession:
            session ?? _mockEmployees[idx].transitRunnerSession,
        transitLastHeartbeat:
            heartbeat ?? _mockEmployees[idx].transitLastHeartbeat,
        clearTransitState: clearHeartbeat,
        locationUpdatedAt: DateTime.now(),
      );
      _broadcastAll();
    }

    final liveIdx = _liveEmployees.indexWhere(
      (e) => e.employeeId == employeeId,
    );
    if (liveIdx != -1) {
      _liveEmployees[liveIdx] = _liveEmployees[liveIdx].copyWith(
        currentLat: lat,
        currentLng: lng,
        speedKmh: speedKmh ?? _liveEmployees[liveIdx].speedKmh,
        batteryFuel: batteryFuel ?? _liveEmployees[liveIdx].batteryFuel,
        transitRunnerSession:
            session ?? _liveEmployees[liveIdx].transitRunnerSession,
        transitLastHeartbeat:
            heartbeat ?? _liveEmployees[liveIdx].transitLastHeartbeat,
        clearTransitState: clearHeartbeat,
        locationUpdatedAt: DateTime.now(),
      );
      _employeesController.add(getAllEmployees());
      notifyListeners();
    }
  }

  final Map<String, String> _driverLocationErrors = {};
  final Map<String, Timer> _gpsPollers = {};
  final Set<String> _gpsWrites = {};
  final Map<String, (LatLng, DateTime)> _lastGpsPoints = {};
  String? driverLocationError(String id) => _driverLocationErrors[id];

  Future<void> _publishDriverPoint(String id, LatLng point) async {
    if (!_liveLocationSubscriptions.containsKey(id) || !_gpsWrites.add(id)) {
      return;
    }
    try {
      final previous = _lastGpsPoints[id];
      final now = DateTime.now();
      final elapsed = previous == null
          ? 0.0
          : now.difference(previous.$2).inMilliseconds / 1000;
      final meters = previous == null
          ? 0.0
          : const Distance().as(LengthUnit.Meter, previous.$1, point);
      final speed = elapsed < 1 || meters < 5
          ? 0
          : (meters / elapsed * 3.6).round().clamp(0, 130);
      await updateEmployeeLocation(
        id,
        lat: point.latitude,
        lng: point.longitude,
        speedKmh: speed,
        recordHeartbeat: true,
      );
      if (_disposed || !_liveLocationSubscriptions.containsKey(id)) {
        return;
      }
      _lastGpsPoints[id] = (point, now);
      _driverLocationErrors.remove(id);
      notifyListeners();
    } catch (error) {
      if (_disposed || !_liveLocationSubscriptions.containsKey(id)) {
        return;
      }
      _driverLocationErrors[id] =
          'GPS could not sync. Check your connection and driver permissions, then retry. No live update was confirmed.';
      notifyListeners();
      debugPrint('Driver GPS sync failed: $error');
    } finally {
      _gpsWrites.remove(id);
    }
  }

  /// Tracks the on-duty session, including the dashboard. Web tracking requires
  /// an open foreground tab; mobile background tracking needs a native service.
  void startLiveDriverLocation(String employeeId) {
    if (simulatedFleetEnabled) {
      return;
    }
    if (!isLiveFirebase ||
        employeeId.isEmpty ||
        _liveLocationSubscriptions.containsKey(employeeId)) {
      return;
    }
    final employee = _liveEmployees
        .where((e) => e.employeeId == employeeId)
        .firstOrNull;
    if (employee == null ||
        employee.userId != FirebaseAuth.instance.currentUser?.uid ||
        employee.status == 'offline') {
      return;
    }
    _driverLocationErrors.remove(employeeId);
    _liveLocationSubscriptions[employeeId] =
        LocationService.watchCurrentLocation().listen(
          (point) => unawaited(_publishDriverPoint(employeeId, point)),
          onError: (Object error) {
            if (_disposed) {
              return;
            }
            stopLiveDriverLocation(employeeId);
            _driverLocationErrors[employeeId] =
                'GPS unavailable. Enable device location and browser/app location permission, then retry.';
            notifyListeners();
            debugPrint('Driver GPS unavailable: $error');
          },
        );
    // Fresh stationary fixes are essential: position streams may emit only on movement.
    _gpsPollers[employeeId] = Timer.periodic(const Duration(seconds: 20), (
      _,
    ) async {
      if (_gpsWrites.contains(employeeId)) {
        return;
      }
      try {
        final point = await LocationService.getCurrentLocation(
          allowFallback: false,
        );
        await _publishDriverPoint(employeeId, point);
      } catch (error) {
        if (_disposed || !_liveLocationSubscriptions.containsKey(employeeId)) {
          return;
        }
        _driverLocationErrors[employeeId] =
            'No fresh GPS fix. Check location permissions. The map shows the last confirmed position.';
        notifyListeners();
      }
    });
  }

  void stopLiveDriverLocation(String employeeId) {
    _liveLocationSubscriptions.remove(employeeId)?.cancel();
    _gpsPollers.remove(employeeId)?.cancel();
    _lastGpsPoints.remove(employeeId);
  }

  ResponsePlan buildResponsePlan(EmergencyRequest request) {
    final type = '${request.emergencyType} ${request.description}'
        .toLowerCase();
    final equipment = <String>{
      'First-aid kit',
      'Oxygen cylinder',
      'Vitals monitor',
    };
    var note =
        'Stabilize, reassess vitals, and transport per dispatcher guidance.';

    if (type.contains('accident') ||
        type.contains('trauma') ||
        type.contains('injur')) {
      equipment.addAll({
        'Trauma bag',
        'Cervical collar',
        'Spinal board',
        'Splints',
      });
      note = 'Use spinal precautions and control bleeding before transport.';
    }
    if (type.contains('cardiac') ||
        type.contains('heart') ||
        type.contains('unconscious')) {
      equipment.addAll({
        'AED / defibrillator',
        'Bag-valve mask',
        'Emergency medicines',
      });
      note =
          'Prepare AED and airway support; prioritize a cardiac-capable facility.';
    }
    if (type.contains('fire') || type.contains('burn')) {
      equipment.addAll({'Burn dressings', 'Sterile saline', 'Thermal blanket'});
      note = 'Cool burns safely, avoid adherent material, and monitor airway.';
    }
    if (type.contains('maternity') ||
        type.contains('pregnan') ||
        type.contains('delivery')) {
      equipment.addAll({'Obstetric kit', 'Newborn blanket', 'Suction bulb'});
      note = 'Prepare for imminent delivery and maternal hemorrhage control.';
    }

    final origin = request.location.latitude == 0
        ? LocationService.defaultLocation
        : LatLng(request.location.latitude, request.location.longitude);
    final candidates =
        <({String name, String capability, String phone, LatLng point})>[
          (
            name: 'Ayub Teaching Hospital',
            capability: 'Level III trauma, cardiac and surgical emergency',
            phone: '0992-9311155',
            point: const LatLng(34.2037, 73.2376),
          ),
          (
            name: 'DHQ Hospital Abbottabad',
            capability: 'General emergency, medicine and burns stabilization',
            phone: '0992-9310066',
            point: const LatLng(34.1463, 73.2151),
          ),
          (
            name: 'Women & Children Hospital',
            capability: 'Maternity, pediatric and neonatal emergency',
            phone: '0992-9310071',
            point: const LatLng(34.1491, 73.2185),
          ),
        ];
    final hospitals = candidates.map((item) {
      final distance = LocationService.calculateDistanceInKm(
        origin.latitude,
        origin.longitude,
        item.point.latitude,
        item.point.longitude,
      );
      return HospitalMatch(
        name: item.name,
        capability: item.capability,
        phone: item.phone,
        location: item.point,
        distanceKm: distance,
      );
    }).toList()..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    return ResponsePlan(
      requiredEquipment: equipment.toList(growable: false),
      hospitals: hospitals,
      clinicalNote: note,
    );
  }

  Future<void> _logAudit({
    required String action,
    required String entityType,
    required String entityId,
    required String actorId,
    required String details,
  }) async {
    final event = AuditEvent(
      id: _newRecordId('AUD'),
      action: action,
      entityType: entityType,
      entityId: entityId,
      actorId: actorId,
      details: details,
      createdAt: DateTime.now(),
    );
    _auditEvents.insert(0, event);
    if (_auditEvents.length > 250) {
      _auditEvents.removeLast();
    }
    _auditController.add(List.unmodifiable(_auditEvents));
    if (isLiveFirebase) {
      try {
        await _firestore!
            .collection('audit_events')
            .doc(event.id)
            .set(event.toMap());
      } catch (error) {
        debugPrint('Audit event queued locally: $error');
      }
    }
  }

  Stream<List<AuditEvent>> getAuditEventsStream() async* {
    if (isLiveFirebase) {
      yield* _firestore!
          .collection('audit_events')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => AuditEvent.fromMap(doc.data(), docId: doc.id))
                .toList(),
          );
      return;
    }
    yield List.unmodifiable(_auditEvents);
    yield* _auditController.stream;
  }

  SystemHealthSnapshot getSystemHealth() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final employees = getAllEmployees();
    final stale = employees.where((employee) {
      if (simulatedFleetEnabled || employee.isSimulated) {
        return false;
      }
      if (employee.status == 'offline') {
        return true;
      }
      final heartbeat = employee.transitLastHeartbeat;
      return heartbeat != null && nowMs - heartbeat > 30000;
    }).length;
    return SystemHealthSnapshot(
      databaseOnline: isLiveFirebase || !kIsWeb,
      activeUnits: employees
          .where((employee) => employee.status != 'offline')
          .length,
      staleUnits: stale,
      queuedWrites: pendingSyncCount,
      checkedAt: DateTime.now(),
    );
  }

  // ================= Donations =================

  Stream<List<Donation>> getDonationsStream({String? userId}) async* {
    if (isLiveFirebase) {
      Query<Map<String, dynamic>> query = _firestore!.collection('donations');
      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }
      yield* query.snapshots().map(
        (snapshot) =>
            snapshot.docs.map((doc) => Donation.fromFirestore(doc)).toList(),
      );
      return;
    }
    List<Donation> filter(List<Donation> list) =>
        list.where((d) => userId == null || d.userId == userId).toList()..sort(
          (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
            a.createdAt ?? DateTime(1970),
          ),
        );
    yield filter(_mockDonations);
    yield* _donationsController.stream.map(filter);
  }

  Future<String> submitDonation(Donation donation) async {
    if (donation.amount < 0) {
      throw ArgumentError.value(
        donation.amount,
        'amount',
        'Donation amount cannot be negative.',
      );
    }
    if (donation.donationType == 'monetary' && donation.amount <= 0) {
      throw ArgumentError('A monetary donation must be greater than zero.');
    }
    if (donation.donationType == 'monetary' &&
        donation.paymentMethod.trim().isNotEmpty &&
        donation.transactionReference.trim().length < 6) {
      throw ArgumentError('Enter the payment transaction/reference ID.');
    }
    if (donation.transactionReference.trim().isNotEmpty) {
      final duplicate = _mockDonations.any(
        (item) =>
            item.transactionReference.toLowerCase() ==
            donation.transactionReference.trim().toLowerCase(),
      );
      if (duplicate) {
        throw StateError('This payment reference has already been submitted.');
      }
    }

    final donationId = _newRecordId('DON');
    final newDonation = donation.copyWith(
      donationId: donationId,
      status: 'Pending',
      paymentStatus: donation.donationType == 'monetary'
          ? 'AwaitingVerification'
          : 'NotApplicable',
      createdAt: DateTime.now(),
    );

    if (isLiveFirebase) {
      await _firestore!
          .collection('donations')
          .doc(donationId)
          .set(newDonation.toMap());
    } else {
      _mockDonations.insert(0, newDonation);
      _broadcastAll();
    }

    _notificationService?.sendNotification(
      userId: donation.userId,
      title: 'Donation Received (#$donationId)',
      message:
          'Thank you for your generous ${donation.donationType} contribution.',
      type: 'donation',
    );

    await _logAudit(
      action: 'donation_created',
      entityType: 'donation',
      entityId: donationId,
      actorId: donation.userId,
      details:
          '${donation.donationType} donation, PKR ${donation.amount.toStringAsFixed(0)}',
    );

    return donationId;
  }

  Future<void> verifyDonation(String donationId) async {
    if (isLiveFirebase) {
      await _firestore!.collection('donations').doc(donationId).update({
        'status': 'Verified',
        'paymentStatus': 'Verified',
      });
    } else {
      final idx = _mockDonations.indexWhere((d) => d.donationId == donationId);
      if (idx != -1) {
        _mockDonations[idx] = _mockDonations[idx].copyWith(
          status: 'Verified',
          paymentStatus: 'Verified',
        );
        _broadcastAll();
      }
    }

    _notificationService?.sendNotification(
      userId: 'all',
      title: 'Donation Verified',
      message:
          'Donation #$donationId has been officially verified by Edhi Admin.',
      type: 'donation',
    );
    await _logAudit(
      action: 'donation_verified',
      entityType: 'donation',
      entityId: donationId,
      actorId: 'admin',
      details: 'Donation verified and receipt finalized',
    );
  }

  // ================= Blood Donors & Needs =================

  int get bloodDonorCount => _mockBloodDonors.length;

  Stream<List<BloodDonor>> getBloodDonorsStream({
    String? bloodGroup,
    String? city,
  }) async* {
    if (isLiveFirebase) {
      Query<Map<String, dynamic>> query = _firestore!.collection(
        'blood_donors',
      );
      if (bloodGroup != null && bloodGroup.isNotEmpty && bloodGroup != 'All') {
        query = query.where('bloodGroup', isEqualTo: bloodGroup);
      }
      yield* query.snapshots().map(
        (s) => s.docs
            .map((doc) => BloodDonor.fromFirestore(doc))
            .where(
              (d) =>
                  city == null ||
                  city.isEmpty ||
                  d.city.toLowerCase().contains(city.toLowerCase()),
            )
            .toList(),
      );
      return;
    }
    List<BloodDonor> filter(List<BloodDonor> list) {
      var res = list;
      if (bloodGroup != null && bloodGroup.isNotEmpty && bloodGroup != 'All') {
        res = res.where((d) => d.bloodGroup == bloodGroup).toList();
      }
      if (city != null && city.isNotEmpty) {
        res = res
            .where((d) => d.city.toLowerCase().contains(city.toLowerCase()))
            .toList();
      }
      return res;
    }

    yield List.unmodifiable(filter(_mockBloodDonors));
    yield* _donorsController.stream.map(filter);
  }

  Stream<List<UrgentBloodNeed>> getBloodNeedsStream() async* {
    if (isLiveFirebase) {
      yield* _firestore!
          .collection(AppConstants.bloodNeedsCollection)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(
                  (doc) => UrgentBloodNeed.fromMap(doc.data(), docId: doc.id),
                )
                .where((need) => need.status == 'active')
                .toList(),
          );
      return;
    }
    yield List.unmodifiable(_mockBloodNeeds.where((n) => n.status == 'active'));
    yield* _bloodNeedsController.stream.map(
      (list) => list.where((n) => n.status == 'active').toList(),
    );
  }

  Future<void> registerBloodDonor(BloodDonor donor) async {
    if (!const [
      'A+',
      'A-',
      'B+',
      'B-',
      'AB+',
      'AB-',
      'O+',
      'O-',
    ].contains(donor.bloodGroup)) {
      throw ArgumentError.value(
        donor.bloodGroup,
        'bloodGroup',
        'Unsupported blood group.',
      );
    }

    String? existingDonorId;
    if (isLiveFirebase && donor.userId.isNotEmpty) {
      final existing = await _firestore!
          .collection(AppConstants.bloodDonorsCollection)
          .where('userId', isEqualTo: donor.userId)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        existingDonorId = existing.docs.first.id;
      }
    } else {
      existingDonorId = _mockBloodDonors
          .where(
            (item) =>
                (donor.userId.isNotEmpty && item.userId == donor.userId) ||
                (donor.userPhone.isNotEmpty &&
                    item.userPhone == donor.userPhone),
          )
          .firstOrNull
          ?.donorId;
    }

    final donorId = existingDonorId ?? _newRecordId('BLD');
    final newDonor = donor.copyWith(
      donorId: donorId,
      createdAt: DateTime.now(),
    );

    if (isLiveFirebase) {
      await _firestore!
          .collection('blood_donors')
          .doc(donorId)
          .set(newDonor.toMap());
    } else {
      final existingIndex = _mockBloodDonors.indexWhere(
        (item) => item.donorId == donorId,
      );
      if (existingIndex == -1) {
        _mockBloodDonors.insert(0, newDonor);
      } else {
        _mockBloodDonors[existingIndex] = newDonor;
      }
      _broadcastAll();
    }

    _notificationService?.sendNotification(
      userId: donor.userId,
      title: 'Blood Donor Registration Complete',
      message:
          'You are now registered as an active ${donor.bloodGroup} blood donor.',
      type: 'blood',
    );
  }

  Future<void> updateDonorAvailability(
    String donorId,
    bool availability,
  ) async {
    if (isLiveFirebase) {
      await _firestore!.collection('blood_donors').doc(donorId).update({
        'availability': availability,
      });
    } else {
      final idx = _mockBloodDonors.indexWhere((d) => d.donorId == donorId);
      if (idx != -1) {
        _mockBloodDonors[idx] = _mockBloodDonors[idx].copyWith(
          availability: availability,
        );
        _broadcastAll();
      }
    }
  }

  Future<void> submitUrgentBloodNeed(UrgentBloodNeed need) async {
    if (need.patientName.trim().isEmpty || need.hospital.trim().isEmpty) {
      throw ArgumentError('Patient name and hospital are required.');
    }
    if (need.userId.isEmpty || !AppUser.isValidPhone(need.contact)) {
      throw ArgumentError('Sign in and provide a valid mobile contact.');
    }
    if (!const [
      'A+',
      'A-',
      'B+',
      'B-',
      'AB+',
      'AB-',
      'O+',
      'O-',
    ].contains(need.bloodGroup)) {
      throw ArgumentError('Select a valid blood group.');
    }
    if (need.unitsNeeded <= 0 || need.unitsNeeded > 20) {
      throw ArgumentError.value(
        need.unitsNeeded,
        'unitsNeeded',
        'Units must be greater than zero.',
      );
    }

    final id = need.id.trim().isEmpty ? _newRecordId('BNEED') : need.id.trim();
    final savedNeed = UrgentBloodNeed(
      id: id,
      patientName: need.patientName.trim(),
      hospital: need.hospital.trim(),
      bloodGroup: need.bloodGroup,
      unitsNeeded: need.unitsNeeded,
      contact: need.contact.trim(),
      urgency: need.urgency,
      userId: need.userId,
      status: need.status,
      createdAt: need.createdAt,
    );

    if (isLiveFirebase) {
      await _firestore!
          .collection(AppConstants.bloodNeedsCollection)
          .doc(id)
          .set(savedNeed.toMap());
    } else {
      _mockBloodNeeds.insert(0, savedNeed);
      _broadcastAll();
    }

    _notificationService?.sendNotification(
      userId: 'all',
      title: 'URGENT BLOOD NEED: ${need.bloodGroup}',
      message:
          '${need.unitsNeeded} unit(s) of ${need.bloodGroup} required at ${need.hospital}',
      type: 'blood',
    );
  }

  Future<void> cancelUrgentBloodNeed(String id, String userId) async {
    if (userId.isEmpty) {
      throw StateError('Please sign in.');
    }
    if (isLiveFirebase) {
      final ref = _firestore!
          .collection(AppConstants.bloodNeedsCollection)
          .doc(id);
      await _firestore!.runTransaction((transaction) async {
        final doc = await transaction.get(ref);
        if (!doc.exists || doc.data()?['userId'] != userId) {
          throw StateError('Only the requester can cancel this need.');
        }
        transaction.update(ref, {
          'status': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        });
      });
    } else {
      final index = _mockBloodNeeds.indexWhere((n) => n.id == id);
      if (index < 0 || !_mockBloodNeeds[index].isOwnedBy(userId)) {
        throw StateError('Only the requester can cancel this need.');
      }
      _mockBloodNeeds.removeAt(index);
      _broadcastAll();
    }
  }

  // ================= AI Chatbot =================
  final Map<String, List<String>> _chatHistory = {};
  String get _chatThreadId => _sessionUserId ?? 'local_demo';

  Stream<List<ChatMessage>> getChatStream() async* {
    if (isLiveFirebase) {
      final threadId = _chatThreadId;
      yield* _firestore!
          .collection(AppConstants.chatMessagesCollection)
          .where('threadId', isEqualTo: threadId)
          .snapshots()
          .map((snapshot) {
            final messages = snapshot.docs
                .map(ChatMessage.fromFirestore)
                .toList();
            messages.sort(
              (a, b) => (a.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0))
                  .compareTo(
                    b.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
                  ),
            );
            _chatHistory[threadId] = messages
                .where((m) => m.sender == 'user')
                .map((m) => m.message)
                .toList()
                .reversed
                .take(8)
                .toList()
                .reversed
                .toList();
            return messages;
          });
      return;
    }
    yield List.unmodifiable(_mockChatMessages);
    yield* _chatController.stream;
  }

  Future<void> sendChatMessage(String messageText) async {
    final cleanText = messageText.trim();
    if (cleanText.isEmpty) {
      return;
    }
    if (cleanText.length > 2000) {
      throw ArgumentError('Please keep messages under 2,000 characters.');
    }
    final threadId = _chatThreadId;
    await WelfareKnowledgeService.initialize();
    final history = ChatContextService.topicHistory(
      cleanText,
      _chatHistory[threadId] ?? [],
    );
    final missingIntent = ChatContextService.hasMissingIntent(
      cleanText,
      history: history,
    );
    final requestStatus = ChatContextService.wantsRequestStatus(
      cleanText,
      history: history,
    );
    final bloodNeedsIntent = ChatContextService.wantsBloodNeeds(
      cleanText,
      history: history,
    );
    List<Map<String, dynamic>>? bloodNeeds;
    List<MissingPersonReport>? missingReports;
    List<EmergencyRequest>? ownRequests;
    if (missingIntent) {
      if (isLiveFirebase) {
        try {
          final saved = await _firestore!
              .collection('missing_persons')
              .orderBy('reportedAt', descending: true)
              .limit(100)
              .get()
              .timeout(const Duration(seconds: 2));
          missingReports = saved.docs
              .map(MissingPersonReport.fromFirestore)
              .toList();
        } catch (_) {
          /* Failed lookup is not an empty result. */
        }
      } else {
        missingReports = List.of(_mockMissingPersons);
      }
    }
    if (requestStatus) {
      if (isLiveFirebase) {
        try {
          final saved = await _firestore!
              .collection('emergency_requests')
              .where('userId', isEqualTo: threadId)
              .limit(30)
              .get()
              .timeout(const Duration(seconds: 2));
          ownRequests = saved.docs.map(EmergencyRequest.fromFirestore).toList();
        } catch (_) {
          /* Keep failed lookups distinct from no open request. */
        }
      } else {
        ownRequests = _mockRequests.where((r) => r.userId == threadId).toList();
      }
    }
    if (bloodNeedsIntent) {
      if (isLiveFirebase) {
        try {
          final saved = await _firestore!
              .collection('blood_needs')
              .orderBy('createdAt', descending: true)
              .limit(50)
              .get()
              .timeout(const Duration(seconds: 2));
          bloodNeeds = saved.docs.map((d) => d.data()).toList();
        } catch (_) {
          /* Do not invent availability when a lookup fails. */
        }
      } else {
        bloodNeeds = _mockBloodNeeds.map((n) => n.toMap()).toList();
      }
    }
    List<BloodDonor>? donors;
    if (!bloodNeedsIntent &&
        WelfareKnowledgeService.hasBloodIntent(cleanText, history: history)) {
      if (isLiveFirebase) {
        try {
          Query<Map<String, dynamic>> query = _firestore!.collection(
            'blood_donors',
          );
          final group = WelfareKnowledgeService.bloodGroupFor(
            cleanText,
            history: history,
          );
          if (group != null) {
            query = query.where('bloodGroup', isEqualTo: group);
          }
          final result = await query
              .limit(100)
              .get()
              .timeout(const Duration(seconds: 2));
          donors = result.docs.map(BloodDonor.fromFirestore).toList();
        } catch (_) {
          /* Keep the direct workflow answer when lookup is unavailable. */
        }
      } else {
        donors = List.of(_mockBloodDonors);
      }
    }
    final guide = WelfareKnowledgeService.answer(
      cleanText,
      history: history,
      donors: donors,
    );
    final botReply = guide.isEmergencyIntent
        ? guide
        : missingIntent
        ? ChatContextService.missingReply(
            cleanText,
            history: history,
            reports: missingReports,
            city: WelfareKnowledgeService.cityFor(cleanText, history: history),
          )
        : requestStatus
        ? ChatContextService.requestReply(ownRequests)
        : bloodNeedsIntent
        ? ChatContextService.bloodNeedsReply(
            bloodNeeds,
            group: WelfareKnowledgeService.bloodGroupFor(
              cleanText,
              history: history,
            ),
            city: WelfareKnowledgeService.cityFor(cleanText, history: history),
          )
        : guide;

    final userMsg = ChatMessage(
      messageId: _newRecordId('MSG'),
      threadId: threadId,
      sender: 'user',
      message: cleanText,
      timestamp: DateTime.now(),
    );

    final botMsg = ChatMessage(
      messageId: _newRecordId('MSG'),
      threadId: threadId,
      sender: 'bot',
      message: botReply.text,
      isEmergency: botReply.isEmergencyIntent,
      quickSuggestions: botReply.quickSuggestions,
      sourceUrls: botReply.sourceUrls,
      timestamp: DateTime.now(),
    );

    if (isLiveFirebase) {
      final batch = _firestore!.batch();
      final collection = _firestore!.collection(
        AppConstants.chatMessagesCollection,
      );
      batch.set(collection.doc(userMsg.messageId), userMsg.toMap());
      batch.set(collection.doc(botMsg.messageId), botMsg.toMap());
      await batch.commit();
    } else {
      _mockChatMessages.addAll([userMsg, botMsg]);
      _broadcastAll();
    }
    _chatHistory[threadId] = [
      ...history,
      cleanText,
    ].reversed.take(8).toList().reversed.toList();
  }

  // ================= Feedback =================

  Stream<List<FeedbackItem>> getFeedbackStream() async* {
    yield List.unmodifiable(_mockFeedback);
    yield* _feedbackController.stream;
  }

  Future<void> submitFeedback(FeedbackItem item) async {
    if (item.rating < 1 || item.rating > 5) {
      throw ArgumentError.value(
        item.rating,
        'rating',
        'Rating must be between 1 and 5.',
      );
    }
    final feedbackId = _newRecordId('FDB');
    final newItem = FeedbackItem(
      feedbackId: feedbackId,
      userId: item.userId,
      userName: item.userName,
      comments: item.comments,
      rating: item.rating,
      createdAt: DateTime.now(),
    );

    if (isLiveFirebase) {
      await _firestore!
          .collection('feedback')
          .doc(feedbackId)
          .set(newItem.toMap());
    } else {
      _mockFeedback.insert(0, newItem);
      _broadcastAll();
    }
  }

  // ================= Centers & Staff =================

  Future<bool> completeDriverResponse(
    String requestId,
    String driverUserId,
  ) async {
    if (driverUserId.isEmpty ||
        (isLiveFirebase &&
            FirebaseAuth.instance.currentUser?.uid != driverUserId)) {
      throw StateError('Sign in to the linked driver account first.');
    }
    return _completeAssignedResponse(requestId, driverUserId, citizen: false);
  }

  Future<bool> completeCitizenResponse(String requestId, String userId) async {
    if (userId.isEmpty ||
        (isLiveFirebase && FirebaseAuth.instance.currentUser?.uid != userId)) {
      throw StateError('Sign in to the account that requested this ambulance.');
    }
    return _completeAssignedResponse(requestId, userId, citizen: true);
  }

  Future<bool> _completeAssignedResponse(
    String requestId,
    String actorId, {
    required bool citizen,
  }) async {
    String check(EmergencyRequest? request, Employee? employee) {
      if (request == null) {
        return 'Request no longer exists.';
      }
      if (citizen ? request.userId != actorId : employee?.userId != actorId) {
        return 'You cannot complete another person’s response.';
      }
      if (request.status == EmergencyStatus.completed) {
        return 'already_completed';
      }
      if (request.status != EmergencyStatus.arrived) {
        return 'Confirm completion only after the ambulance has arrived.';
      }
      if (employee == null ||
          employee.status != 'busy' ||
          employee.activeRequestId != requestId) {
        return 'The ambulance assignment needs admin review before it can be released.';
      }
      return 'ok';
    }

    String outcome;
    String recipientId = '';
    if (isLiveFirebase) {
      final requestRef = _firestore!
          .collection(AppConstants.requestsCollection)
          .doc(requestId);
      outcome = await _firestore!.runTransaction<String>((tx) async {
        final saved = await tx.get(requestRef);
        if (!saved.exists) {
          return 'Request no longer exists.';
        }
        final request = EmergencyRequest.fromFirestore(saved);
        final employeeRef = request.assignedEmployeeId == null
            ? null
            : _firestore!
                  .collection(AppConstants.employeesCollection)
                  .doc(request.assignedEmployeeId);
        final employeeDoc = employeeRef == null
            ? null
            : await tx.get(employeeRef);
        final employee = employeeDoc?.exists == true
            ? Employee.fromFirestore(employeeDoc!)
            : null;
        final result = check(request, employee);
        if (result != 'ok') {
          return result;
        }
        recipientId = request.userId;
        final routeRef = _firestore!
            .collection('route_demos')
            .doc(employee!.employeeId);
        final route = await tx.get(routeRef);
        tx.update(requestRef, {
          'status': EmergencyStatus.completed,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(employeeRef!, {
          'status': 'available',
          'activeRequestId': '',
          'speedKmh': 0,
        });
        if (route.exists &&
            route.data()?['requestId'] == requestId &&
            route.data()?['enabled'] == true) {
          tx.update(routeRef, {
            'enabled': false,
            'stoppedAt': FieldValue.serverTimestamp(),
          });
        }
        return 'ok';
      });
    } else {
      final index = _mockRequests.indexWhere((r) => r.requestId == requestId);
      final request = index < 0 ? null : _mockRequests[index];
      final employee = _mockEmployees
          .where((e) => e.employeeId == request?.assignedEmployeeId)
          .firstOrNull;
      outcome = check(request, employee);
      if (outcome == 'ok') {
        recipientId = request!.userId;
        final employeeIndex = _mockEmployees.indexWhere(
          (e) => e.employeeId == employee!.employeeId,
        );
        // Commit the in-memory equivalent together, before any asynchronous
        // audit/notification work. A simultaneous confirmation is a no-op.
        _mockRequests[index] = request.copyWith(
          status: EmergencyStatus.completed,
          updatedAt: _now(),
        );
        _mockEmployees[employeeIndex] = _mockEmployees[employeeIndex].copyWith(
          status: 'available',
          activeRequestId: '',
          speedKmh: 0,
        );
        final route = _routeDemos[employee!.employeeId];
        if (route?.requestId == requestId && route!.enabled) {
          _routeDemos[employee.employeeId] = RoutePlayback(
            requestId: route.requestId,
            points: route.points,
            startedAt: route.startedAt,
            durationSeconds: route.durationSeconds,
            speedFactor: route.speedFactor,
            pausedAt: route.pausedAt,
            stoppedAt: _now(),
            enabled: false,
          );
        }
        _broadcastAll();
      }
    }
    if (outcome == 'already_completed') {
      return false;
    }
    if (outcome != 'ok') {
      throw StateError(outcome);
    }
    _notificationService?.sendNotification(
      userId: recipientId,
      title: 'Response completed',
      message:
          'Request #$requestId is completed. The ambulance is available for another response.',
      type: 'emergency',
    );
    await _logAudit(
      action: citizen
          ? 'citizen_response_completed'
          : 'driver_response_completed',
      entityType: 'emergency',
      entityId: requestId,
      actorId: actorId,
      details: citizen
          ? 'Citizen confirmed help received; ambulance released.'
          : 'Driver completed response; ambulance released.',
    );
    return true;
  }

  Future<void> linkDriverAccount(String employeeId, String userId) async {
    final uid = userId.trim();
    if (isLiveFirebase) {
      if (_sessionRole != AppRoles.admin) {
        throw StateError('Only admin can link driver accounts.');
      }
      if (uid.isNotEmpty) {
        final linked = await _firestore!
            .collection(AppConstants.employeesCollection)
            .where('userId', isEqualTo: uid)
            .get();
        if (linked.docs.any((doc) => doc.id != employeeId)) {
          throw StateError(
            'This driver is already linked to another ambulance. Unlink it first.',
          );
        }
      }
      final ref = _firestore!
          .collection(AppConstants.employeesCollection)
          .doc(employeeId);
      await _firestore!.runTransaction((tx) async {
        final employee = await tx.get(ref);
        if (!employee.exists) {
          throw StateError('Ambulance no longer exists.');
        }
        final oldUid = employee.data()?['userId'] as String? ?? '';
        final newClaimRef = uid.isEmpty
            ? null
            : _firestore!.collection('driver_links').doc(uid);
        final newClaim = newClaimRef == null ? null : await tx.get(newClaimRef);
        final profile = uid.isEmpty
            ? null
            : await tx.get(
                _firestore!.collection(AppConstants.usersCollection).doc(uid),
              );
        final oldClaimRef = oldUid.isEmpty || oldUid == uid
            ? null
            : _firestore!.collection('driver_links').doc(oldUid);
        final oldClaim = oldClaimRef == null ? null : await tx.get(oldClaimRef);
        if (employee.data()?['status'] == 'busy') {
          throw StateError(
            'Complete the active response before changing its driver.',
          );
        }
        if (uid.isNotEmpty &&
            (profile?.data()?['role'] != AppRoles.employee ||
                profile?.data()?['isActive'] != true)) {
          throw StateError('Choose an active registered Driver account.');
        }
        if (newClaim?.exists == true &&
            newClaim!.data()?['employeeId'] != employeeId) {
          throw StateError(
            'This driver is already linked to another ambulance.',
          );
        }
        tx.update(ref, {
          'userId': uid,
          'isSimulated': true,
          if (profile != null)
            'name': profile.data()?['name'] ?? employee.data()?['name'],
          'phone': profile?.data()?['phone'] ?? '',
        });
        if (newClaimRef != null) {
          tx.set(newClaimRef, {
            'employeeId': employeeId,
            'linkedAt': FieldValue.serverTimestamp(),
          });
        }
        if (oldClaim?.exists == true &&
            oldClaim!.data()?['employeeId'] == employeeId) {
          tx.delete(oldClaimRef!);
        }
      });
    } else {
      final index = _mockEmployees.indexWhere(
        (e) => e.employeeId == employeeId,
      );
      if (index < 0) {
        throw StateError('Ambulance no longer exists.');
      }
      if (_mockEmployees[index].status == 'busy') {
        throw StateError(
          'Complete the active response before changing its driver.',
        );
      }
      final profile = _mockUsers
          .where((u) => u.id == uid && u.isEmployee && u.isActive)
          .firstOrNull;
      if (uid.isNotEmpty && profile == null) {
        throw StateError('Choose an active registered Driver account.');
      }
      if (uid.isNotEmpty &&
          _mockEmployees.any(
            (e) => e.employeeId != employeeId && e.userId == uid,
          )) {
        throw StateError('This driver is already linked to another ambulance.');
      }
      _mockEmployees[index] = _mockEmployees[index].copyWith(
        userId: uid,
        name: profile?.name,
        phone: profile?.phone ?? '',
      );
      _broadcastAll();
    }
    await _logAudit(
      action: 'driver_account_linked',
      entityType: 'employee',
      entityId: employeeId,
      actorId: _sessionUserId ?? 'admin',
      details: uid.isEmpty
          ? 'No driver account linked'
          : 'Registered driver linked',
    );
  }

  Stream<List<Employee>> getEmployeesStream() async* {
    yield getAllEmployees();
    yield* _employeesController.stream;
  }

  List<Employee> getAvailableDrivers() {
    final pool = getAllEmployees();
    return pool
        .where((e) => e.role == 'driver' && e.status == 'available')
        .toList();
  }

  EmergencyRequest? getCurrentAssignment(
    Employee employee,
    Iterable<EmergencyRequest> requests,
  ) {
    if (employee.status != 'busy') {
      return null;
    }
    final jobs = requests
        .where(
          (r) =>
              r.assignedEmployeeId == employee.employeeId &&
              [
                EmergencyStatus.assigned,
                EmergencyStatus.inProgress,
                EmergencyStatus.arrived,
              ].contains(r.status),
        )
        .toList();
    final bound = jobs
        .where((r) => r.requestId == employee.activeRequestId)
        .firstOrNull;
    if (employee.activeRequestId.isNotEmpty) {
      return bound;
    }
    final routeId = _routeDemos[employee.employeeId]?.requestId;
    final routed = jobs.where((r) => r.requestId == routeId).firstOrNull;
    if (routed != null) {
      return routed;
    }
    return jobs.length == 1 ? jobs.single : null;
  }

  List<Employee> getAllEmployees() {
    final pool = isLiveFirebase ? _liveEmployees : _mockEmployees;
    final now = _now();
    return List.unmodifiable(
      pool.map((employee) {
        final demo = _routeDemos[employee.employeeId];
        final position = demo?.positionAt(now);
        return position == null
            ? employee.copyWith(
                isDemo: simulatedFleetEnabled && employee.role == 'driver',
                isSimulated: simulatedFleetEnabled || employee.isSimulated,
                speedKmh: 0,
              )
            : employee.copyWith(
                currentLat: position.latitude,
                currentLng: position.longitude,
                isDemo: true,
                isSimulated: true,
                speedKmh: demo!.movingAt(now) ? demo.estimatedSpeedKmh : 0,
              );
      }),
    );
  }

  Future<void> updateEmployeeStatus(String employeeId, String newStatus) async {
    if (!['available', 'offline'].contains(newStatus)) {
      throw ArgumentError('Only dispatch can mark a unit busy.');
    }
    if (isLiveFirebase) {
      final ref = _firestore!
          .collection(AppConstants.employeesCollection)
          .doc(employeeId);
      await _firestore!.runTransaction((tx) async {
        final current = await tx.get(ref);
        if (!current.exists) {
          throw StateError('Ambulance no longer exists.');
        }
        if (current.data()?['status'] == 'busy') {
          throw StateError(
            'Complete the active response before changing availability.',
          );
        }
        tx.update(ref, {'status': newStatus});
      });
    } else {
      final idx = _mockEmployees.indexWhere((e) => e.employeeId == employeeId);
      if (idx < 0) {
        throw StateError('Ambulance no longer exists.');
      }
      if (_mockEmployees[idx].status == 'busy') {
        throw StateError(
          'Complete the active response before changing availability.',
        );
      }
      _mockEmployees[idx] = _mockEmployees[idx].copyWith(status: newStatus);
      _broadcastAll();
    }
    unawaited(
      _logAudit(
        action: 'availability_changed',
        entityType: 'ambulance',
        entityId: employeeId,
        actorId: employeeId,
        details: 'Unit status changed to $newStatus',
      ),
    );
  }

  void _validateFleetEntry(Employee employee) {
    if (employee.name.trim().isEmpty || employee.vehicleNumber.trim().isEmpty) {
      throw ArgumentError('Enter a driver name and unique vehicle number.');
    }
    if (!['available', 'offline'].contains(employee.status)) {
      throw ArgumentError(
        'A new ambulance must be parked/available or offline.',
      );
    }
    if (!employee.hasValidLocation) {
      throw ArgumentError('Enter a valid parking position.');
    }
    if (getAllEmployees().any(
      (e) =>
          e.vehicleNumber.trim().toUpperCase() ==
          employee.vehicleNumber.trim().toUpperCase(),
    )) {
      throw StateError('This vehicle number is already registered.');
    }
  }

  Future<LatLng> prepareSimulatedParkingPoint(LatLng point) =>
      _roadSnapper(point);

  Future<String> addEmployee(Employee employee) async {
    _validateFleetEntry(employee);
    final sanitizedPlate = employee.vehicleNumber
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '_');
    final id = employee.employeeId.isNotEmpty
        ? employee.employeeId
        : 'driver_$sanitizedPlate';
    final newEmp = employee.copyWith(
      employeeId: id,
      userId: employee.userId.trim(),
      name: employee.name.trim(),
      vehicleNumber: employee.vehicleNumber.trim().toUpperCase(),
      isSimulated: true,
      speedKmh: 0,
    );
    if (isLiveFirebase) {
      if (newEmp.userId.isNotEmpty) {
        final linked = await _firestore!
            .collection(AppConstants.employeesCollection)
            .where('userId', isEqualTo: newEmp.userId)
            .get();
        if (linked.docs.isNotEmpty) {
          throw StateError(
            'This driver is already linked to another ambulance.',
          );
        }
      }
      final ref = _firestore!
          .collection(AppConstants.employeesCollection)
          .doc(id);
      await _firestore!.runTransaction((tx) async {
        final existing = await tx.get(ref);
        final claimRef = newEmp.userId.isEmpty
            ? null
            : _firestore!.collection('driver_links').doc(newEmp.userId);
        final claim = claimRef == null ? null : await tx.get(claimRef);
        final profile = newEmp.userId.isEmpty
            ? null
            : await tx.get(
                _firestore!
                    .collection(AppConstants.usersCollection)
                    .doc(newEmp.userId),
              );
        if (existing.exists) {
          throw StateError('This vehicle number is already registered.');
        }
        if (claim?.exists == true) {
          throw StateError(
            'This driver is already linked to another ambulance.',
          );
        }
        if (newEmp.userId.isNotEmpty &&
            (profile?.data()?['role'] != AppRoles.employee ||
                profile?.data()?['isActive'] != true)) {
          throw StateError('Choose an active registered Driver account.');
        }
        tx.set(ref, {
          ...newEmp.toMap(),
          'activeRequestId': '',
          if (profile != null) 'name': profile.data()!['name'],
          if (profile != null) 'phone': profile.data()!['phone'],
        });
        if (claimRef != null) {
          tx.set(claimRef, {
            'employeeId': id,
            'linkedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } else {
      if (_mockEmployees.any((e) => e.employeeId == id)) {
        throw StateError('This vehicle number is already registered.');
      }
      final profile = _mockUsers
          .where((u) => u.id == newEmp.userId && u.isEmployee && u.isActive)
          .firstOrNull;
      if (newEmp.userId.isNotEmpty) {
        if (profile == null) {
          throw StateError('Choose an active registered Driver account.');
        }
        if (_mockEmployees.any((e) => e.userId == newEmp.userId)) {
          throw StateError(
            'This driver is already linked to another ambulance.',
          );
        }
      }
      _mockEmployees.add(
        newEmp.copyWith(name: profile?.name, phone: profile?.phone),
      );
      _broadcastAll();
    }
    await _logAudit(
      action: 'simulated_unit_added',
      entityType: 'employee',
      entityId: id,
      actorId: _sessionUserId ?? 'admin',
      details: '${newEmp.name} • ${newEmp.vehicleNumber}',
    );
    return id;
  }

  /// Road positions are prepared first; one atomic batch adds the entire group.
  Future<List<Employee>> generateRandomDrivers({
    required int count,
    required LatLng stagingPoint,
    String? centerId,
    Random? random,
  }) async {
    if (count < 1 || count > 10) {
      throw ArgumentError('Generate between 1 and 10 units at a time.');
    }
    if (!RequestLocation(
          latitude: stagingPoint.latitude,
          longitude: stagingPoint.longitude,
        ).hasValidCoordinates ||
        stagingPoint.latitude.abs() > 85) {
      throw ArgumentError('Choose a valid staging area.');
    }
    final generator = random ?? Random.secure();
    final prepared = <Employee>[];
    for (var i = 0; i < count; i++) {
      final position = await _roadSnapper(
        SimulatedFleet.nearbyPoint(stagingPoint, generator),
      );
      final id = _newRecordId('SIM');
      final plate = 'AMB-${id.substring(4)}';
      final employee = Employee(
        employeeId: id,
        userId: '',
        name: SimulatedFleet
            .names[generator.nextInt(SimulatedFleet.names.length)],
        phone: '',
        vehicleNumber: plate,
        assignedCenterId: centerId,
        currentLat: position.latitude,
        currentLng: position.longitude,
        isSimulated: true,
        batteryFuel: 75 + generator.nextInt(26),
      );
      _validateFleetEntry(employee);
      prepared.add(employee);
    }
    if (isLiveFirebase) {
      final batch = _firestore!.batch();
      for (final employee in prepared) {
        batch.set(
          _firestore!
              .collection(AppConstants.employeesCollection)
              .doc(employee.employeeId),
          {...employee.toMap(), 'activeRequestId': ''},
        );
      }
      await batch.commit();
    } else {
      _mockEmployees.addAll(prepared);
      _broadcastAll();
    }
    await _logAudit(
      action: 'simulated_fleet_generated',
      entityType: 'employee',
      entityId: centerId ?? 'local-staging',
      actorId: _sessionUserId ?? 'admin',
      details: '${prepared.length} parked units added',
    );
    return prepared;
  }

  Future<void> deleteEmployee(String employeeId) async {
    if (isLiveFirebase) {
      final ref = _firestore!
          .collection(AppConstants.employeesCollection)
          .doc(employeeId);
      final routeRef = _firestore!.collection('route_demos').doc(employeeId);
      await _firestore!.runTransaction((tx) async {
        final employee = await tx.get(ref);
        final route = await tx.get(routeRef);
        if (!employee.exists) {
          return;
        }
        final uid = employee.data()?['userId'] as String? ?? '';
        final claimRef = uid.isEmpty
            ? null
            : _firestore!.collection('driver_links').doc(uid);
        final claim = claimRef == null ? null : await tx.get(claimRef);
        if (employee.data()?['status'] == 'busy') {
          throw StateError(
            'Complete this unit’s active response before decommissioning it.',
          );
        }
        tx.delete(ref);
        if (route.exists) {
          tx.delete(routeRef);
        }
        if (claim?.data()?['employeeId'] == employeeId) {
          tx.delete(claimRef!);
        }
      });
    } else {
      if (_mockEmployees.any(
        (e) => e.employeeId == employeeId && e.status == 'busy',
      )) {
        throw StateError(
          'Complete this unit’s active response before decommissioning it.',
        );
      }
      _mockEmployees.removeWhere((e) => e.employeeId == employeeId);
    }
    _routeDemos.remove(employeeId);
    _pendingTransitStarts.remove(employeeId);
    _broadcastAll();
    await _logAudit(
      action: 'staff_removed',
      entityType: 'employee',
      entityId: employeeId,
      actorId: 'admin',
      details: 'Fleet record removed; login profiles are unchanged',
    );
  }

  List<EdhiCenter> getEdhiCenters() {
    final centers = {
      for (final center in edhiCenterDirectory) center.centerId: center,
    };
    for (final center in isLiveFirebase ? _liveCenters : _mockCenters) {
      centers[center.centerId] = center;
    }
    final list = centers.values.toList()
      ..sort((a, b) {
        final city = a.city.compareTo(b.city);
        return city == 0 ? a.name.compareTo(b.name) : city;
      });
    return List.unmodifiable(list);
  }

  Stream<List<EdhiCenter>> getCentersStream() async* {
    if (isLiveFirebase) {
      yield* _firestore!
          .collection('edhi_centers')
          .snapshots()
          .map(
            (snap) => {
              for (final c in edhiCenterDirectory) c.centerId: c,
              for (final doc in snap.docs)
                doc.id: EdhiCenter.fromFirestore(doc),
            }.values.toList(),
          );
    } else {
      yield getEdhiCenters();
    }
  }

  Future<String> addCenter(EdhiCenter center) async {
    final id = center.centerId.isNotEmpty
        ? center.centerId
        : 'center_${DateTime.now().millisecondsSinceEpoch}';
    final newCenter = EdhiCenter(
      centerId: id,
      name: center.name,
      address: center.address,
      contact: center.contact,
      city: center.city,
      ambulanceCount: center.ambulanceCount,
      services: center.services,
      latitude: center.latitude,
      longitude: center.longitude,
      sourceUrl: center.sourceUrl,
      verifiedOn: center.verifiedOn,
    );
    if (isLiveFirebase) {
      await _firestore!
          .collection('edhi_centers')
          .doc(id)
          .set(newCenter.toMap());
    } else {
      _mockCenters.add(newCenter);
      notifyListeners();
    }
    return id;
  }

  // ================= User & Driver Management =================

  Stream<Map<String, EmergencyUsage>> watchAllEmergencyUsage() async* {
    if (isLiveFirebase) {
      yield* _firestore!
          .collection('emergency_usage')
          .snapshots()
          .map(
            (snap) => {
              for (final doc in snap.docs)
                doc.id: EmergencyUsage.fromMap(doc.data()),
            },
          );
    } else {
      yield Map.unmodifiable(_mockUsage);
      yield* _usersController.stream.map(
        (_) => Map<String, EmergencyUsage>.unmodifiable(_mockUsage),
      );
    }
  }

  void _requireAdmin() {
    if (isLiveFirebase && _sessionRole != AppRoles.admin) {
      throw StateError('Administrator access is required.');
    }
  }

  Future<void> unbanEmergencyUser(String userId) async {
    _requireAdmin();
    if (isLiveFirebase) {
      // Keep history for the review highlight, but restart the counting window.
      await _firestore!.collection('emergency_usage').doc(userId).set({
        'banStartedAt': null,
        'adminBanned': false,
        'windowStartedAt': Timestamp.fromDate(
          _now().subtract(EmergencyUsage.countingWindow),
        ),
      }, SetOptions(merge: true));
    } else {
      final old = _mockUsage[userId] ?? const EmergencyUsage();
      _mockUsage[userId] = EmergencyUsage(
        cancellationCount: old.cancellationCount,
        windowStartedAt: _now().subtract(EmergencyUsage.countingWindow),
      );
      _broadcastAll();
    }
    await _logAudit(
      action: 'emergency_ban_lifted',
      entityType: 'user',
      entityId: userId,
      actorId: _sessionUserId ?? 'admin',
      details: 'Administrator restored emergency request access.',
    );
  }

  Future<void> banEmergencyUser(String userId) async {
    _requireAdmin();
    if (userId == _sessionUserId) {
      throw StateError('You cannot ban your own administrator account.');
    }
    if (isLiveFirebase) {
      await _firestore!.runTransaction((tx) async {
        final profile = await tx.get(
          _firestore!.collection('users').doc(userId),
        );
        final ref = _firestore!.collection('emergency_usage').doc(userId);
        final usage = await tx.get(ref);
        if (!profile.exists) throw StateError('User no longer exists.');
        tx.set(ref, {
          if (!usage.exists) ...{
            'cancellationCount': 0,
            'windowStartedAt': FieldValue.serverTimestamp(),
            'banStartedAt': null,
          },
          'adminBanned': true,
        }, SetOptions(merge: true));
      });
    } else {
      if (!_mockUsers.any((u) => u.id == userId)) {
        throw StateError('User no longer exists.');
      }
      final old = _mockUsage[userId] ?? const EmergencyUsage();
      _mockUsage[userId] = EmergencyUsage(
        cancellationCount: old.cancellationCount,
        windowStartedAt: old.windowStartedAt,
        banStartedAt: old.banStartedAt,
        adminBanned: true,
      );
      _broadcastAll();
    }
    await _logAudit(
      action: 'emergency_user_banned',
      entityType: 'user',
      entityId: userId,
      actorId: _sessionUserId ?? 'admin',
      details: 'Emergency requests blocked until administrator unbans.',
    );
  }

  Future<void> updateUserProfile(
    String userId, {
    required String name,
    required String address,
  }) async {
    _requireAdmin();
    if (name.trim().isEmpty) {
      throw ArgumentError('Name is required.');
    }
    if (isLiveFirebase) {
      await _firestore!.collection('users').doc(userId).update({
        'name': name.trim(),
        'address': address.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final index = _mockUsers.indexWhere((u) => u.id == userId);
      if (index < 0) {
        throw StateError('Profile not found.');
      }
      _mockUsers[index] = _mockUsers[index].copyWith(
        name: name.trim(),
        address: address.trim(),
      );
      _broadcastAll();
    }
    await _logAudit(
      action: 'profile_updated',
      entityType: 'user',
      entityId: userId,
      actorId: _sessionUserId ?? 'admin',
      details: 'Administrator updated profile.',
    );
  }

  Future<AppUser> createManagedUser({
    required String name,
    required String cnic,
    required String phone,
    required String password,
    required String role,
    String email = '',
    String address = '',
  }) async {
    _requireAdmin();
    if (name.trim().length < 2) throw ArgumentError('Enter the full name.');
    if (!AppUser.isValidCnic(cnic)) {
      throw ArgumentError('Enter a valid 13-digit CNIC.');
    }
    if (!AppUser.isValidPhone(phone)) {
      throw ArgumentError('Enter a valid Pakistani mobile number.');
    }
    if (password.length < 8) {
      throw ArgumentError('Password must be at least 8 characters.');
    }
    if (![AppRoles.user, AppRoles.employee].contains(role)) {
      throw ArgumentError('Choose Citizen or Driver.');
    }
    if (email.trim().isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
      throw ArgumentError('Enter a valid contact email.');
    }
    final digits = AppUser.cleanCnic(cnic);
    final normalizedPhone = AppUser.normalizePhone(phone);
    final random = Random.secure();
    final opaque = base64UrlEncode(
      List.generate(16, (_) => random.nextInt(256)),
    ).replaceAll('=', '').toLowerCase();
    final authEmail = 'account_$opaque@citizen.edhi.org';
    FirebaseApp? secondary;
    FirebaseAuth? secondaryAuth;
    User? created;
    bool saved = false;
    late AppUser profile;
    try {
      if (isLiveFirebase) {
        final aliases = await Future.wait([
          _firestore!.collection('login_aliases').doc('cnic_$digits').get(),
          _firestore!
              .collection('login_aliases')
              .doc('phone_$normalizedPhone')
              .get(),
        ]);
        if (aliases.any((a) => a.exists)) {
          throw StateError('This CNIC or phone number is already registered.');
        }
        // A separate Auth instance preserves the administrator's session.
        secondary = await Firebase.initializeApp(
          name: 'admin-create-$opaque',
          options: Firebase.app().options,
        );
        secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
        if (kIsWeb) await secondaryAuth.setPersistence(Persistence.NONE);
        created = (await secondaryAuth.createUserWithEmailAndPassword(
          email: authEmail,
          password: password,
        )).user;
        if (created == null) {
          throw StateError('Account creation did not complete.');
        }
      } else if (_mockUsers.any(
        (u) =>
            AppUser.cleanCnic(u.cnic) == digits ||
            AppUser.normalizePhone(u.phone) == normalizedPhone,
      )) {
        throw StateError('This CNIC or phone number is already registered.');
      }
      profile = AppUser(
        id: created?.uid ?? _newRecordId('USR'),
        name: name.trim(),
        email: email.trim().isEmpty ? authEmail : email.trim().toLowerCase(),
        cnic: AppUser.formatCnic(cnic),
        phone: normalizedPhone,
        role: role,
        address: address.trim(),
        createdAt: _now(),
      );
      if (isLiveFirebase) {
        final claimed = await _firestore!.runTransaction<bool>((tx) async {
          final phoneRef = _firestore!
              .collection('phone_claims')
              .doc(normalizedPhone);
          final cnicRef = _firestore!
              .collection('login_aliases')
              .doc('cnic_$digits');
          final aliasRef = _firestore!
              .collection('login_aliases')
              .doc('phone_$normalizedPhone');
          final phoneClaim = await tx.get(phoneRef);
          final cnicClaim = await tx.get(cnicRef);
          final aliasClaim = await tx.get(aliasRef);
          if (phoneClaim.exists || cnicClaim.exists || aliasClaim.exists) {
            return false;
          }
          tx.set(phoneRef, {'userId': profile.id});
          tx.set(cnicRef, {'authEmail': authEmail});
          tx.set(aliasRef, {'authEmail': authEmail});
          tx.set(_firestore!.collection('users').doc(profile.id), {
            ...profile.toMap(),
            'authEmail': authEmail,
          });
          return true;
        });
        if (!claimed) {
          throw StateError('This CNIC or phone number is already registered.');
        }
      } else {
        _mockUsers.add(profile);
        _broadcastAll();
      }
      saved = true;
    } catch (error) {
      if (created != null && !saved) {
        try {
          await created.delete();
        } catch (_) {
          throw StateError(
            'Account setup failed and Auth cleanup could not complete. Contact Operations before retrying.',
          );
        }
      }
      rethrow;
    } finally {
      try {
        await secondaryAuth?.signOut();
      } finally {
        await secondary?.delete();
      }
    }
    await _logAudit(
      action: 'user_created',
      entityType: 'user',
      entityId: profile.id,
      actorId: _sessionUserId ?? 'admin',
      details: 'Administrator created a $role account.',
    );
    return profile;
  }

  Future<void> deleteManagedUser(String userId) async {
    _requireAdmin();
    if (userId == _sessionUserId ||
        (isLiveFirebase && FirebaseAuth.instance.currentUser?.uid == userId)) {
      throw StateError('You cannot delete your own administrator account.');
    }
    bool open(String status) => ![
      EmergencyStatus.completed,
      EmergencyStatus.cancelled,
    ].contains(status);
    if (isLiveFirebase) {
      final jobs = await _firestore!
          .collection('emergency_requests')
          .where('userId', isEqualTo: userId)
          .get();
      final units = await _firestore!
          .collection('employees')
          .where('userId', isEqualTo: userId)
          .get();
      final result = await _firestore!.runTransaction<String>((tx) async {
        final profileRef = _firestore!.collection('users').doc(userId);
        final profile = await tx.get(profileRef);
        if (!profile.exists) return 'User no longer exists.';
        final data = profile.data()!;
        final unitRefs = <String, DocumentReference<Map<String, dynamic>>>{
          for (final u in units.docs) u.id: u.reference,
        };
        final linkRef = _firestore!.collection('driver_links').doc(userId);
        final link = await tx.get(linkRef);
        final unitId = link.data()?['employeeId'] as String?;
        if (unitId != null && unitId.isNotEmpty) {
          unitRefs[unitId] = _firestore!.collection('employees').doc(unitId);
        }
        final freshUnits = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final ref in unitRefs.values) {
          freshUnits.add(await tx.get(ref));
        }
        for (final job in jobs.docs) {
          final fresh = await tx.get(job.reference);
          if (fresh.exists &&
              open(fresh.data()?['status'] as String? ?? 'Pending')) {
            return 'Complete or cancel this user’s active emergency requests before deleting.';
          }
        }
        if (freshUnits.any(
          (u) =>
              u.data()?['userId'] == userId &&
              (u.data()?['status'] == 'busy' ||
                  (u.data()?['activeRequestId'] as String? ?? '').isNotEmpty),
        )) {
          return 'Complete the driver’s active mission before deleting.';
        }
        final phone = data['phone'] as String? ?? '';
        final cnic = AppUser.cleanCnic(data['cnic'] as String? ?? '');
        final aliases = <DocumentReference<Map<String, dynamic>>>[
          if (phone.isNotEmpty)
            _firestore!
                .collection('login_aliases')
                .doc('phone_${AppUser.normalizePhone(phone)}'),
          if (cnic.isNotEmpty)
            _firestore!.collection('login_aliases').doc('cnic_$cnic'),
        ];
        final claimRef = phone.isEmpty
            ? null
            : _firestore!
                  .collection('phone_claims')
                  .doc(AppUser.normalizePhone(phone));
        final claim = claimRef == null ? null : await tx.get(claimRef);
        final aliasDocs = <DocumentSnapshot<Map<String, dynamic>>>[];
        for (final ref in aliases) {
          aliasDocs.add(await tx.get(ref));
        }
        final authEmail = data['authEmail'] ?? '$cnic@citizen.edhi.org';
        for (final alias in aliasDocs) {
          if (alias.data()?['authEmail'] == authEmail) {
            tx.delete(alias.reference);
          }
        }
        if (claim?.data()?['userId'] == userId) tx.delete(claimRef!);
        for (final unit in freshUnits) {
          if (unit.data()?['userId'] == userId) {
            tx.update(unit.reference, {
              'userId': '',
              'phone': '',
              'status': 'offline',
            });
          }
        }
        tx.delete(linkRef);
        tx.delete(_firestore!.collection('emergency_usage').doc(userId));
        tx.delete(profileRef);
        return '';
      });
      if (result.isNotEmpty) throw StateError(result);
    } else {
      if (!_mockUsers.any((u) => u.id == userId)) {
        throw StateError('User no longer exists.');
      }
      if (_mockRequests.any((r) => r.userId == userId && open(r.status))) {
        throw StateError(
          'Complete or cancel this user’s active emergency requests before deleting.',
        );
      }
      if (_mockEmployees.any(
        (u) =>
            u.userId == userId &&
            (u.status == 'busy' || u.activeRequestId.isNotEmpty),
      )) {
        throw StateError(
          'Complete the driver’s active mission before deleting.',
        );
      }
      for (var i = 0; i < _mockEmployees.length; i++) {
        if (_mockEmployees[i].userId == userId) {
          _mockEmployees[i] = _mockEmployees[i].copyWith(
            userId: '',
            phone: '',
            status: 'offline',
          );
        }
      }
      _mockUsers.removeWhere((u) => u.id == userId);
      _mockUsage.remove(userId);
      _broadcastAll();
    }
    await _logAudit(
      action: 'user_deleted',
      entityType: 'user',
      entityId: userId,
      actorId: _sessionUserId ?? 'admin',
      details:
          'Deleted app profile and login aliases; historical reports retained.',
    );
  }

  static const adminCollections = [
    'users',
    'employees',
    'edhi_centers',
    'emergency_requests',
    'emergency_usage',
    'route_demos',
    'driver_links',
    'donations',
    'blood_donors',
    'blood_needs',
    'missing_persons',
    'feedback',
    'chat_messages',
    'notifications',
    'tasks',
    'photo_attachments',
    'phone_claims',
    'login_aliases',
    'audit_events',
  ];

  void _checkAdminCollection(String collection) {
    _requireAdmin();
    if (!adminCollections.contains(collection)) {
      throw ArgumentError('Unknown collection.');
    }
  }

  Map<String, Map<String, dynamic>> _localAdminRecords(String collection) {
    return switch (collection) {
      'users' => {for (final x in _mockUsers) x.id: x.toMap()},
      'employees' => {for (final x in _mockEmployees) x.employeeId: x.toMap()},
      'emergency_requests' => {
        for (final x in _mockRequests) x.requestId: x.toMap(),
      },
      'donations' => {for (final x in _mockDonations) x.donationId: x.toMap()},
      'blood_donors' => {
        for (final x in _mockBloodDonors) x.donorId: x.toMap(),
      },
      'blood_needs' => {for (final x in _mockBloodNeeds) x.id: x.toMap()},
      'edhi_centers' => {for (final x in _mockCenters) x.centerId: x.toMap()},
      'missing_persons' => {
        for (final x in _mockMissingPersons) x.reportId: x.toMap(),
      },
      'feedback' => {for (final x in _mockFeedback) x.feedbackId: x.toMap()},
      'chat_messages' => {
        for (final x in _mockChatMessages) x.messageId: x.toMap(),
      },
      'emergency_usage' => {
        for (final x in _mockUsage.entries)
          x.key: {
            'cancellationCount': x.value.cancellationCount,
            'adminBanned': x.value.adminBanned,
            'windowStartedAt': x.value.windowStartedAt == null
                ? null
                : Timestamp.fromDate(x.value.windowStartedAt!),
            'banStartedAt': x.value.banStartedAt == null
                ? null
                : Timestamp.fromDate(x.value.banStartedAt!),
          },
      },
      _ => {},
    };
  }

  Stream<Map<String, Map<String, dynamic>>> watchAdminRecords(
    String collection,
  ) async* {
    _checkAdminCollection(collection);
    if (isLiveFirebase) {
      // Bound listener cost; use an exact document ID to inspect older records.
      yield* _firestore!
          .collection(collection)
          .orderBy(FieldPath.documentId)
          .limit(200)
          .snapshots()
          .map((snap) => {for (final doc in snap.docs) doc.id: doc.data()});
    } else {
      yield _localAdminRecords(collection);
      yield* _usersController.stream.map((_) => _localAdminRecords(collection));
    }
  }

  Future<Map<String, dynamic>?> getAdminRecord(
    String collection,
    String id,
  ) async {
    _checkAdminCollection(collection);
    return isLiveFirebase
        ? (await _firestore!.collection(collection).doc(id).get()).data()
        : _localAdminRecords(collection)[id];
  }

  static dynamic _encodeDatabaseValue(dynamic value) {
    if (value is Timestamp) {
      return {
        '__type': 'timestamp',
        'value': value.toDate().toUtc().toIso8601String(),
      };
    }
    if (value is GeoPoint) {
      return {
        '__type': 'geopoint',
        'latitude': value.latitude,
        'longitude': value.longitude,
      };
    }
    if (value is Blob) {
      return {'__type': 'bytes', 'value': base64Encode(value.bytes)};
    }
    if (value is DocumentReference) {
      return {'__type': 'reference', 'value': value.path};
    }
    if (value is Map) {
      return value.map(
        (k, v) => MapEntry(k.toString(), _encodeDatabaseValue(v)),
      );
    }
    if (value is List) {
      return value.map(_encodeDatabaseValue).toList();
    }
    return value;
  }

  static String adminRecordJson(Map<String, dynamic> data) =>
      const JsonEncoder.withIndent('  ').convert(_encodeDatabaseValue(data));

  dynamic _decodeDatabaseValue(dynamic value) {
    if (value is Map) {
      if (value['__type'] == 'timestamp') {
        return Timestamp.fromDate(DateTime.parse(value['value'] as String));
      }
      if (value['__type'] == 'geopoint') {
        return GeoPoint(
          (value['latitude'] as num).toDouble(),
          (value['longitude'] as num).toDouble(),
        );
      }
      if (value['__type'] == 'bytes') {
        return Blob(base64Decode(value['value'] as String));
      }
      if (value['__type'] == 'reference') {
        if (!isLiveFirebase) {
          throw ArgumentError('References require Firebase.');
        }
        return _firestore!.doc(value['value'] as String);
      }
      return value.map(
        (k, v) => MapEntry(k.toString(), _decodeDatabaseValue(v)),
      );
    }
    if (value is List) {
      return value.map(_decodeDatabaseValue).toList();
    }
    return value;
  }

  Future<void> saveAdminRecord(
    String collection,
    String id,
    String json, {
    required bool create,
  }) async {
    _checkAdminCollection(collection);
    if (collection == 'audit_events') {
      throw StateError('Audit history is read-only.');
    }
    if (id.trim().isEmpty || id.contains('/')) {
      throw ArgumentError('A valid document ID is required.');
    }
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw ArgumentError('Enter a JSON object.');
    }
    final data = Map<String, dynamic>.from(
      _decodeDatabaseValue(decoded) as Map,
    );
    if (collection == 'users' &&
        id == _sessionUserId &&
        (data['role'] != AppRoles.admin || data['isActive'] != true)) {
      throw StateError('You cannot remove your own administrator access.');
    }
    if (isLiveFirebase) {
      final ref = _firestore!.collection(collection).doc(id);
      await _firestore!.runTransaction((tx) async {
        final current = await tx.get(ref);
        if (current.exists == create) {
          throw StateError(
            create
                ? 'Document ID already exists.'
                : 'Document no longer exists.',
          );
        }
        tx.set(ref, data);
      });
    } else {
      // The editor uses the real database. Avoid pretending unsupported demo writes succeeded.
      throw StateError('Connect Firebase to edit database records.');
    }
    await _logAudit(
      action: create ? 'database_record_added' : 'database_record_edited',
      entityType: collection,
      entityId: id,
      actorId: _sessionUserId ?? 'admin',
      details: 'Administrator database editor.',
    );
  }

  Future<void> deleteAdminRecord(String collection, String id) async {
    _checkAdminCollection(collection);
    if (collection == 'audit_events') {
      throw StateError('Audit history is read-only.');
    }
    if (collection == 'users' && id == _sessionUserId) {
      throw StateError('You cannot delete your own account.');
    }
    if (!isLiveFirebase) {
      throw StateError('Connect Firebase to delete database records.');
    }
    final data = await getAdminRecord(collection, id);
    if (data == null) {
      throw StateError('Document no longer exists.');
    }
    if (collection == 'employees' && data['status'] == 'busy') {
      throw StateError(
        'Complete or cancel the active mission before deleting this unit.',
      );
    }
    if (collection == 'emergency_requests' &&
        !['Completed', 'Cancelled'].contains(data['status'])) {
      await updateRequestStatus(
        id,
        EmergencyStatus.cancelled,
        adminOverride: true,
      );
    }
    await _firestore!.collection(collection).doc(id).delete();
    await _logAudit(
      action: 'database_record_deleted',
      entityType: collection,
      entityId: id,
      actorId: _sessionUserId ?? 'admin',
      details: 'Administrator deleted database record.',
    );
  }

  Stream<List<AppUser>> getUsersStream() async* {
    if (isLiveFirebase) {
      yield* _firestore!
          .collection(AppConstants.usersCollection)
          .snapshots()
          .map(
            (snapshot) =>
                snapshot.docs.map((doc) => AppUser.fromFirestore(doc)).toList(),
          );
    } else {
      yield List.unmodifiable(_mockUsers);
      yield* _usersController.stream;
    }
  }

  Future<void> updateUserStatus(String userId, bool isActive) async {
    _requireAdmin();
    if (userId == _sessionUserId && !isActive) {
      throw StateError('You cannot deactivate your own administrator account.');
    }
    if (isLiveFirebase) {
      await _firestore!
          .collection(AppConstants.usersCollection)
          .doc(userId)
          .update({'isActive': isActive});
    } else {
      final idx = _mockUsers.indexWhere((u) => u.id == userId);
      if (idx != -1) {
        _mockUsers[idx] = _mockUsers[idx].copyWith(isActive: isActive);
        _broadcastAll();
      }
    }
    await _logAudit(
      action: isActive ? 'user_activated' : 'user_suspended',
      entityType: 'user',
      entityId: userId,
      actorId: _sessionUserId ?? 'admin',
      details: 'Account active state set to $isActive',
    );
  }

  Future<void> toggleDriverAvailability(
    String employeeId,
    bool isAvailable,
  ) async {
    await updateEmployeeStatus(
      employeeId,
      isAvailable ? 'available' : 'offline',
    );
  }

  // ================= Missing Persons =================

  Stream<List<MissingPersonReport>> getMissingPersonsStream() async* {
    if (isLiveFirebase) {
      yield* _firestore!
          .collection(AppConstants.missingPersonsCollection)
          .orderBy('reportedAt', descending: true)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => MissingPersonReport.fromFirestore(doc))
                .toList(),
          );
    } else {
      yield List.unmodifiable(_mockMissingPersons);
      yield* _missingPersonsController.stream;
    }
  }

  Future<String> uploadMissingPersonPhoto(
    Uint8List bytes,
    String contentType,
  ) => _uploadPhoto(bytes, contentType, 'missing_persons');

  Future<String> uploadDonationPhoto(Uint8List bytes, String contentType) =>
      _uploadPhoto(bytes, contentType, 'donations');

  Future<String> _uploadPhoto(
    Uint8List bytes,
    String contentType,
    String folder,
  ) async {
    if (!isLiveFirebase) {
      throw StateError('Photo upload requires Firebase.');
    }
    if (bytes.isEmpty ||
        bytes.length > 5 * 1024 * 1024 ||
        !const [
          'image/jpeg',
          'image/png',
          'image/webp',
        ].contains(contentType)) {
      throw ArgumentError('Choose a JPEG, PNG or WebP image under 5 MB.');
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('Please sign in.');
    }
    final image = await PhotoCodec.compress(bytes);
    final ref = _firestore!.collection('photo_attachments').doc();
    await ref.set({
      'userId': uid,
      'kind': folder,
      'contentType': 'image/png',
      'image': Blob(image),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return 'firestore-photo:${ref.id}';
  }

  Future<String> submitMissingPersonReport(MissingPersonReport report) async {
    if (report.lastSeenAt != null &&
        report.lastSeenAt!.isAfter(DateTime.now())) {
      throw ArgumentError('Last seen time cannot be in the future.');
    }
    if (report.personName.trim().isEmpty ||
        report.contactPhone.trim().isEmpty) {
      throw ArgumentError(
        'Missing person name and a contact phone are required.',
      );
    }
    if (report.age < 0 || report.age > 130) {
      throw ArgumentError.value(
        report.age,
        'age',
        'Enter a valid age between 0 and 130.',
      );
    }

    final reportId = _newRecordId('MP');
    final newReport = report.copyWith(
      reportId: reportId,
      reportedAt: DateTime.now(),
    );

    if (isLiveFirebase) {
      await _firestore!
          .collection(AppConstants.missingPersonsCollection)
          .doc(reportId)
          .set(newReport.toMap());
    } else {
      _mockMissingPersons.insert(0, newReport);
      _broadcastAll();
    }
    return reportId;
  }

  Future<void> updateMissingPersonStatus(
    String reportId,
    String newStatus,
  ) async {
    if (!const ['Searching', 'Found', 'Reunited'].contains(newStatus)) {
      throw ArgumentError.value(
        newStatus,
        'newStatus',
        'Unsupported missing person status.',
      );
    }
    if (isLiveFirebase) {
      await _firestore!
          .collection(AppConstants.missingPersonsCollection)
          .doc(reportId)
          .update({'status': newStatus});
    } else {
      final idx = _mockMissingPersons.indexWhere((r) => r.reportId == reportId);
      if (idx != -1) {
        _mockMissingPersons[idx] = _mockMissingPersons[idx].copyWith(
          status: newStatus,
        );
        _broadcastAll();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _gpsPollers.values) {
      timer.cancel();
    }
    _demoTicker?.cancel();
    _demoSub?.cancel();
    _simulationRequestsSub?.cancel();
    for (final subscription in _liveLocationSubscriptions.values) {
      subscription.cancel();
    }
    _liveLocationSubscriptions.clear();
    _empSub?.cancel();
    _centersSub?.cancel();
    _requestsController.close();
    _donationsController.close();
    _donorsController.close();
    _bloodNeedsController.close();
    _chatController.close();
    _feedbackController.close();
    _usersController.close();
    _missingPersonsController.close();
    _employeesController.close();
    _auditController.close();
    super.dispose();
  }
}
