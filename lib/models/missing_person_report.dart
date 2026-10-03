import 'package:cloud_firestore/cloud_firestore.dart';

class MissingPersonReport {
  final String reportId;
  final String personName;
  final int age;
  final String gender;
  final String lastSeenLocation;
  final String description;
  final String contactName;
  final String contactPhone;
  final String status; // 'Searching', 'Found', 'Reunited'
  final DateTime reportedAt;
  final String photoUrl;
  final DateTime? lastSeenAt;
  final String userId;

  const MissingPersonReport({
    required this.reportId,
    required this.personName,
    required this.age,
    required this.gender,
    required this.lastSeenLocation,
    required this.description,
    required this.contactName,
    required this.contactPhone,
    this.status = 'Searching',
    required this.reportedAt,
    this.photoUrl = '',
    this.lastSeenAt,
    this.userId = '',
  });

  bool get isSearching => status == 'Searching';
  bool get isFound => status == 'Found';
  bool get isReunited => status == 'Reunited';

  factory MissingPersonReport.fromMap(
    Map<String, dynamic> map, {
    String? docId,
  }) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return DateTime.now();
    }

    return MissingPersonReport(
      reportId: docId ?? map['reportId'] ?? '',
      personName: map['personName'] ?? 'Unknown Person',
      age: (map['age'] as num?)?.toInt() ?? 0,
      gender: map['gender'] ?? 'Not specified',
      lastSeenLocation: map['lastSeenLocation'] ?? '',
      description: map['description'] ?? '',
      contactName: map['contactName'] ?? '',
      contactPhone: map['contactPhone'] ?? '',
      status: map['status'] ?? 'Searching',
      reportedAt: parseDate(map['reportedAt']),
      photoUrl: map['photoUrl'] ?? '',
      lastSeenAt: map['lastSeenAt'] == null
          ? null
          : parseDate(map['lastSeenAt']),
      userId: map['userId'] ?? '',
    );
  }

  factory MissingPersonReport.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return MissingPersonReport.fromMap(
      snapshot.data() ?? {},
      docId: snapshot.id,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'reportId': reportId,
      'personName': personName,
      'age': age,
      'gender': gender,
      'lastSeenLocation': lastSeenLocation,
      'description': description,
      'contactName': contactName,
      'contactPhone': contactPhone,
      'status': status,
      'reportedAt': Timestamp.fromDate(reportedAt),
      'photoUrl': photoUrl,
      'lastSeenAt': lastSeenAt == null ? null : Timestamp.fromDate(lastSeenAt!),
      'userId': userId,
    };
  }

  MissingPersonReport copyWith({
    String? reportId,
    String? personName,
    int? age,
    String? gender,
    String? lastSeenLocation,
    String? description,
    String? contactName,
    String? contactPhone,
    String? status,
    DateTime? reportedAt,
    String? photoUrl,
    DateTime? lastSeenAt,
    String? userId,
  }) {
    return MissingPersonReport(
      reportId: reportId ?? this.reportId,
      personName: personName ?? this.personName,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      lastSeenLocation: lastSeenLocation ?? this.lastSeenLocation,
      description: description ?? this.description,
      contactName: contactName ?? this.contactName,
      contactPhone: contactPhone ?? this.contactPhone,
      status: status ?? this.status,
      reportedAt: reportedAt ?? this.reportedAt,
      photoUrl: photoUrl ?? this.photoUrl,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      userId: userId ?? this.userId,
    );
  }
}
