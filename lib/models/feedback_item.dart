import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackItem {
  final String feedbackId;
  final String userId;
  final String userName;
  final String comments;
  final int rating; // 1 to 5
  final DateTime? createdAt;

  const FeedbackItem({
    required this.feedbackId,
    required this.userId,
    this.userName = '',
    required this.comments,
    required this.rating,
    this.createdAt,
  });

  factory FeedbackItem.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return FeedbackItem(
      feedbackId: docId ?? map['feedbackId'] ?? '',
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      comments: map['comments'] ?? '',
      rating: (map['rating'] as num?)?.toInt() ?? 5,
      createdAt: parseDate(map['createdAt']),
    );
  }

  factory FeedbackItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return FeedbackItem.fromMap(snapshot.data() ?? {}, docId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'feedbackId': feedbackId,
      'userId': userId,
      'userName': userName,
      'comments': comments,
      'rating': rating,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }
}
