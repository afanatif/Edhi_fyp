import 'package:cloud_firestore/cloud_firestore.dart';

class AuditEvent {
  final String id;
  final String action;
  final String entityType;
  final String entityId;
  final String actorId;
  final String details;
  final DateTime createdAt;

  const AuditEvent({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.actorId,
    required this.details,
    required this.createdAt,
  });

  factory AuditEvent.fromMap(Map<String, dynamic> map, {String? docId}) {
    final rawDate = map['createdAt'];
    return AuditEvent(
      id: docId ?? map['id']?.toString() ?? '',
      action: map['action']?.toString() ?? 'updated',
      entityType: map['entityType']?.toString() ?? 'system',
      entityId: map['entityId']?.toString() ?? '',
      actorId: map['actorId']?.toString() ?? 'system',
      details: map['details']?.toString() ?? '',
      createdAt: rawDate is Timestamp
          ? rawDate.toDate()
          : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'action': action,
    'entityType': entityType,
    'entityId': entityId,
    'actorId': actorId,
    'details': details,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}
