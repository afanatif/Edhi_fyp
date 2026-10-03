import 'package:cloud_firestore/cloud_firestore.dart';

class Employee {
  final String employeeId;
  final String userId;
  final String name;
  final String phone;
  final String role; // 'driver', 'staff'
  final String status; // 'available', 'busy', 'offline'
  final String activeRequestId;
  final String vehicleNumber;
  final String? assignedCenterId;
  final double currentLat;
  final double currentLng;
  final String vehicleModel;
  final int batteryFuel;
  final int speedKmh;
  final String? transitRunnerSession;
  final int? transitLastHeartbeat;
  final DateTime? locationUpdatedAt;
  final bool isDemo;
  final bool isSimulated;
  bool get hasValidLocation =>
      currentLat.isFinite &&
      currentLng.isFinite &&
      currentLat.abs() <= 90 &&
      currentLng.abs() <= 180 &&
      (currentLat != 0 || currentLng != 0);
  bool hasFreshGps(DateTime now) {
    final timestamp =
        locationUpdatedAt ??
        (transitLastHeartbeat == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(transitLastHeartbeat!));
    return !isSimulated &&
        !isDemo &&
        hasValidLocation &&
        timestamp != null &&
        now.difference(timestamp).inSeconds >= -10 &&
        now.difference(timestamp).inSeconds < 90;
  }

  const Employee({
    required this.employeeId,
    required this.userId,
    required this.name,
    required this.phone,
    this.role = 'driver',
    this.status = 'available',
    this.activeRequestId = '',
    this.vehicleNumber = '',
    this.assignedCenterId,
    this.currentLat = 0,
    this.currentLng = 0,
    this.vehicleModel = 'Ambulance',
    this.batteryFuel = -1,
    this.speedKmh = 0,
    this.transitRunnerSession,
    this.transitLastHeartbeat,
    this.locationUpdatedAt,
    this.isDemo = false,
    this.isSimulated = true,
  });

  factory Employee.fromMap(Map<String, dynamic> map, {String? docId}) {
    return Employee(
      employeeId: docId ?? map['employeeId'] ?? '',
      userId: map['userId'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      role: map['role'] ?? 'driver',
      status: map['status'] ?? 'available',
      activeRequestId: map['activeRequestId'] as String? ?? '',
      vehicleNumber: map['vehicleNumber'] ?? '',
      assignedCenterId: map['assignedCenterId'],
      currentLat: (map['currentLat'] as num?)?.toDouble() ?? 0,
      currentLng: (map['currentLng'] as num?)?.toDouble() ?? 0,
      vehicleModel: map['vehicleModel'] ?? 'Ambulance',
      batteryFuel: (map['batteryFuel'] as num?)?.toInt() ?? -1,
      speedKmh: (map['speedKmh'] as num?)?.toInt() ?? 0,
      transitRunnerSession: map['transitRunnerSession'] as String?,
      transitLastHeartbeat: (map['transitLastHeartbeat'] as num?)?.toInt(),
      locationUpdatedAt: (map['locationUpdatedAt'] as Timestamp?)?.toDate(),
      isSimulated: map['isSimulated'] as bool? ?? true,
    );
  }

  factory Employee.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return Employee.fromMap(snapshot.data() ?? {}, docId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'employeeId': employeeId,
      'userId': userId,
      'name': name,
      'phone': phone,
      'role': role,
      'status': status,
      'activeRequestId': activeRequestId,
      'vehicleNumber': vehicleNumber,
      'assignedCenterId': assignedCenterId,
      'currentLat': currentLat,
      'currentLng': currentLng,
      'vehicleModel': vehicleModel,
      'batteryFuel': batteryFuel,
      'speedKmh': speedKmh,
      'isSimulated': isSimulated,
      'transitRunnerSession': transitRunnerSession,
      'transitLastHeartbeat': transitLastHeartbeat,
      'locationUpdatedAt': locationUpdatedAt == null
          ? null
          : Timestamp.fromDate(locationUpdatedAt!),
    };
  }

  Employee copyWith({
    String? employeeId,
    String? userId,
    String? name,
    String? phone,
    String? role,
    String? status,
    String? activeRequestId,
    String? vehicleNumber,
    String? assignedCenterId,
    double? currentLat,
    double? currentLng,
    String? vehicleModel,
    int? batteryFuel,
    int? speedKmh,
    String? transitRunnerSession,
    int? transitLastHeartbeat,
    bool clearTransitState = false,
    DateTime? locationUpdatedAt,
    bool? isDemo,
    bool? isSimulated,
  }) {
    return Employee(
      employeeId: employeeId ?? this.employeeId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      status: status ?? this.status,
      activeRequestId: activeRequestId ?? this.activeRequestId,
      vehicleNumber: vehicleNumber ?? this.vehicleNumber,
      assignedCenterId: assignedCenterId ?? this.assignedCenterId,
      currentLat: currentLat ?? this.currentLat,
      currentLng: currentLng ?? this.currentLng,
      vehicleModel: vehicleModel ?? this.vehicleModel,
      batteryFuel: batteryFuel ?? this.batteryFuel,
      speedKmh: speedKmh ?? this.speedKmh,
      locationUpdatedAt: locationUpdatedAt ?? this.locationUpdatedAt,
      isDemo: isDemo ?? this.isDemo,
      isSimulated: isSimulated ?? this.isSimulated,
      transitRunnerSession: clearTransitState
          ? null
          : transitRunnerSession ?? this.transitRunnerSession,
      transitLastHeartbeat: clearTransitState
          ? null
          : transitLastHeartbeat ?? this.transitLastHeartbeat,
    );
  }
}
