import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationItem {
  final String notificationId;
  final String userId;
  final String title;
  final String message;
  final String type; // 'emergency', 'donation', 'blood', 'system'
  final bool isRead;
  final DateTime? createdAt;

  const NotificationItem({
    required this.notificationId,
    required this.userId,
    required this.title,
    required this.message,
    this.type = 'general',
    this.isRead = false,
    this.createdAt,
  });

  factory NotificationItem.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return NotificationItem(
      notificationId: docId ?? map['notificationId'] ?? '',
      userId: map['userId'] ?? '',
      title: map['title'] ?? '',
      message: map['message'] ?? '',
      type: map['type'] ?? 'general',
      isRead: map['isRead'] ?? false,
      createdAt: parseDate(map['createdAt']),
    );
  }

  factory NotificationItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return NotificationItem.fromMap(snapshot.data() ?? {}, docId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'notificationId': notificationId,
      'userId': userId,
      'title': title,
      'message': message,
      'type': type,
      'isRead': isRead,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }
}
