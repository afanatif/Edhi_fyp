import 'package:cloud_firestore/cloud_firestore.dart';

class BloodDonor {
  final String donorId;
  final String userId;
  final String userName;
  final String userPhone;
  final String bloodGroup; // 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
  final bool availability;
  final String city;
  final DateTime? createdAt;

  const BloodDonor({
    required this.donorId,
    required this.userId,
    this.userName = '',
    this.userPhone = '',
    required this.bloodGroup,
    this.availability = true,
    this.city = '',
    this.createdAt,
  });

  factory BloodDonor.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return BloodDonor(
      donorId: docId ?? map['donorId'] ?? '',
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userPhone: map['userPhone'] ?? '',
      bloodGroup: map['bloodGroup'] ?? 'O+',
      availability: map['availability'] ?? true,
      city: map['city'] ?? '',
      createdAt: parseDate(map['createdAt']),
    );
  }

  factory BloodDonor.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return BloodDonor.fromMap(snapshot.data() ?? {}, docId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'donorId': donorId,
      'userId': userId,
      'userName': userName,
      'userPhone': userPhone,
      'bloodGroup': bloodGroup,
      'availability': availability,
      'city': city,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  BloodDonor copyWith({
    String? donorId,
    String? userId,
    String? userName,
    String? userPhone,
    String? bloodGroup,
    bool? availability,
    String? city,
    DateTime? createdAt,
  }) {
    return BloodDonor(
      donorId: donorId ?? this.donorId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userPhone: userPhone ?? this.userPhone,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      availability: availability ?? this.availability,
      city: city ?? this.city,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
