import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String messageId;
  final String threadId;
  final String sender; // 'user', 'bot', 'admin'
  final String message;
  final DateTime? timestamp;

  const ChatMessage({
    required this.messageId,
    required this.threadId,
    required this.sender,
    required this.message,
    this.timestamp,
  });

  bool get isUser => sender == 'user';

  factory ChatMessage.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return ChatMessage(
      messageId: docId ?? map['messageId'] ?? '',
      threadId: map['threadId'] ?? '',
      sender: map['sender'] ?? 'user',
      message: map['message'] ?? '',
      timestamp: parseDate(map['timestamp']),
    );
  }

  factory ChatMessage.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return ChatMessage.fromMap(snapshot.data() ?? {}, docId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'messageId': messageId,
      'threadId': threadId,
      'sender': sender,
      'message': message,
      'timestamp': timestamp != null
          ? Timestamp.fromDate(timestamp!)
          : FieldValue.serverTimestamp(),
    };
  }
}

class ChatThread {
  final String threadId;
  final String userId;
  final String lastMessage;
  final DateTime? lastUpdated;

  const ChatThread({
    required this.threadId,
    required this.userId,
    required this.lastMessage,
    this.lastUpdated,
  });

  factory ChatThread.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return ChatThread(
      threadId: docId ?? map['threadId'] ?? '',
      userId: map['userId'] ?? '',
      lastMessage: map['lastMessage'] ?? '',
      lastUpdated: parseDate(map['lastUpdated']),
    );
  }

  factory ChatThread.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return ChatThread.fromMap(snapshot.data() ?? {}, docId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'threadId': threadId,
      'userId': userId,
      'lastMessage': lastMessage,
      'lastUpdated': lastUpdated != null
          ? Timestamp.fromDate(lastUpdated!)
          : FieldValue.serverTimestamp(),
    };
  }
}
