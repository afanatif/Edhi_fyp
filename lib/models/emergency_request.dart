import 'package:cloud_firestore/cloud_firestore.dart';

class RequestLocation {
  final double latitude;
  final double longitude;
  final String address;
  bool get hasValidCoordinates =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180 &&
      (latitude != 0 || longitude != 0);

  const RequestLocation({
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.address = '',
  });

  factory RequestLocation.fromMap(Map<String, dynamic> map) {
    return RequestLocation(
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      address: map['address'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {'latitude': latitude, 'longitude': longitude, 'address': address};
  }
}

class EmergencyRequest {
  final String requestId;
  final String userId;
  final String userName;
  final String userPhone;
  final String emergencyType;
  final RequestLocation location;
  final String description;
  final String
  status; // 'Pending', 'Approved', 'Assigned', 'InProgress', 'Completed', 'Cancelled'
  final String priority; // 'Critical P1', 'Urgent P2', 'Standard P3'
  final bool isDuplicate;
  final String? duplicateOfRequestId;
  final String? assignedEmployeeId;
  final String? assignedEmployeeName;
  final double fraudRiskScore; // 0.0 (Legitimate) to 1.0 (High Risk / Fraud)
  final String fraudRiskLevel; // 'Low', 'Medium', 'High'
  final String? fraudReason;
  final bool isVerified;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const EmergencyRequest({
    required this.requestId,
    required this.userId,
    this.userName = '',
    this.userPhone = '',
    required this.emergencyType,
    required this.location,
    required this.description,
    this.status = 'Pending',
    this.priority = 'Standard P3',
    this.isDuplicate = false,
    this.duplicateOfRequestId,
    this.assignedEmployeeId,
    this.assignedEmployeeName,
    this.fraudRiskScore = 0.0,
    this.fraudRiskLevel = 'Low',
    this.fraudReason,
    this.isVerified = false,
    this.createdAt,
    this.updatedAt,
  });

  factory EmergencyRequest.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    RequestLocation parseLocation(dynamic val) {
      if (val is Map<String, dynamic>) {
        return RequestLocation.fromMap(val);
      }
      if (val is String) {
        return RequestLocation(address: val);
      }
      return const RequestLocation();
    }

    return EmergencyRequest(
      requestId: docId ?? map['requestId'] ?? '',
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userPhone: map['userPhone'] ?? '',
      emergencyType: map['emergencyType'] ?? 'Medical Emergency',
      location: parseLocation(map['location']),
      description: map['description'] ?? '',
      status: map['status'] ?? 'Pending',
      priority: map['priority'] ?? 'Standard P3',
      isDuplicate: map['isDuplicate'] ?? false,
      duplicateOfRequestId: map['duplicateOfRequestId'],
      assignedEmployeeId: map['assignedEmployeeId'],
      assignedEmployeeName: map['assignedEmployeeName'],
      fraudRiskScore: (map['fraudRiskScore'] as num?)?.toDouble() ?? 0.0,
      fraudRiskLevel: map['fraudRiskLevel'] ?? 'Low',
      fraudReason: map['fraudReason'],
      isVerified: map['isVerified'] ?? false,
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
    );
  }

  factory EmergencyRequest.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return EmergencyRequest.fromMap(snapshot.data() ?? {}, docId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'emergencyType': emergencyType,
      'location': location.toMap(),
      'description': description,
      'status': status,
      'priority': priority,
      'isDuplicate': isDuplicate,
      'duplicateOfRequestId': duplicateOfRequestId,
      'assignedEmployeeId': assignedEmployeeId,
      'assignedEmployeeName': assignedEmployeeName,
      'fraudRiskScore': fraudRiskScore,
      'fraudRiskLevel': fraudRiskLevel,
      'fraudReason': fraudReason,
      'isVerified': isVerified,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  EmergencyRequest copyWith({
    String? requestId,
    String? userId,
    String? userName,
    String? userPhone,
    String? emergencyType,
    RequestLocation? location,
    String? description,
    String? status,
    String? priority,
    bool? isDuplicate,
    String? duplicateOfRequestId,
    String? assignedEmployeeId,
    String? assignedEmployeeName,
    double? fraudRiskScore,
    String? fraudRiskLevel,
    String? fraudReason,
    bool? isVerified,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmergencyRequest(
      requestId: requestId ?? this.requestId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      emergencyType: emergencyType ?? this.emergencyType,
      location: location ?? this.location,
      description: description ?? this.description,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      isDuplicate: isDuplicate ?? this.isDuplicate,
      duplicateOfRequestId: duplicateOfRequestId ?? this.duplicateOfRequestId,
      assignedEmployeeId: assignedEmployeeId ?? this.assignedEmployeeId,
      assignedEmployeeName: assignedEmployeeName ?? this.assignedEmployeeName,
      fraudRiskScore: fraudRiskScore ?? this.fraudRiskScore,
      fraudRiskLevel: fraudRiskLevel ?? this.fraudRiskLevel,
      fraudReason: fraudReason ?? this.fraudReason,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
