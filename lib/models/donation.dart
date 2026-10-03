import 'package:cloud_firestore/cloud_firestore.dart';

class Donation {
  final String donationId;
  final String userId;
  final String userName;
  final double amount;
  final String donationType; // 'monetary', 'ration', 'clothing'
  final String status; // 'Pending', 'Verified', 'Completed'
  final String notes;
  final String campaign;
  final String photoUrl;
  final String paymentMethod;
  final String transactionReference;
  final String paymentStatus;
  final DateTime? createdAt;

  const Donation({
    required this.donationId,
    required this.userId,
    this.userName = '',
    required this.amount,
    required this.donationType,
    this.status = 'Pending',
    this.notes = '',
    this.campaign = '',
    this.photoUrl = '',
    this.paymentMethod = '',
    this.transactionReference = '',
    this.paymentStatus = 'NotApplicable',
    this.createdAt,
  });

  factory Donation.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return Donation(
      donationId: docId ?? map['donationId'] ?? '',
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      donationType: map['donationType'] ?? 'monetary',
      status: map['status'] ?? 'Pending',
      notes: map['notes'] ?? '',
      campaign: map['campaign'] ?? '',
      photoUrl: map['photoUrl'] ?? '',
      paymentMethod: map['paymentMethod'] ?? '',
      transactionReference: map['transactionReference'] ?? '',
      paymentStatus: map['paymentStatus'] ?? 'NotApplicable',
      createdAt: parseDate(map['createdAt']),
    );
  }

  factory Donation.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return Donation.fromMap(snapshot.data() ?? {}, docId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'donationId': donationId,
      'userId': userId,
      'userName': userName,
      'amount': amount,
      'donationType': donationType,
      'status': status,
      'notes': notes,
      'campaign': campaign,
      'photoUrl': photoUrl,
      'paymentMethod': paymentMethod,
      'transactionReference': transactionReference,
      'paymentStatus': paymentStatus,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  Donation copyWith({
    String? donationId,
    String? userId,
    String? userName,
    double? amount,
    String? donationType,
    String? status,
    String? notes,
    String? campaign,
    String? photoUrl,
    String? paymentMethod,
    String? transactionReference,
    String? paymentStatus,
    DateTime? createdAt,
  }) {
    return Donation(
      donationId: donationId ?? this.donationId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      amount: amount ?? this.amount,
      donationType: donationType ?? this.donationType,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      campaign: campaign ?? this.campaign,
      photoUrl: photoUrl ?? this.photoUrl,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      transactionReference: transactionReference ?? this.transactionReference,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
