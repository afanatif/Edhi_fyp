import 'package:cloud_firestore/cloud_firestore.dart';

class FieldTask {
  final String taskId;
  final String requestId;
  final String employeeId;
  final String status; // 'Assigned', 'EnRoute', 'Arrived', 'Completed'
  final String notes;
  final DateTime? updatedAt;

  const FieldTask({
    required this.taskId,
    required this.requestId,
    required this.employeeId,
    this.status = 'Assigned',
    this.notes = '',
    this.updatedAt,
  });

  factory FieldTask.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return FieldTask(
      taskId: docId ?? map['taskId'] ?? '',
      requestId: map['requestId'] ?? '',
      employeeId: map['employeeId'] ?? '',
      status: map['status'] ?? 'Assigned',
      notes: map['notes'] ?? '',
      updatedAt: parseDate(map['updatedAt']),
    );
  }

  factory FieldTask.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return FieldTask.fromMap(snapshot.data() ?? {}, docId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'taskId': taskId,
      'requestId': requestId,
      'employeeId': employeeId,
      'status': status,
      'notes': notes,
      'updatedAt': updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  FieldTask copyWith({
    String? taskId,
    String? requestId,
    String? employeeId,
    String? status,
    String? notes,
    DateTime? updatedAt,
  }) {
    return FieldTask(
      taskId: taskId ?? this.taskId,
      requestId: requestId ?? this.requestId,
      employeeId: employeeId ?? this.employeeId,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
