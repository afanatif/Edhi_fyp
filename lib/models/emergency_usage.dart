import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import 'emergency_request.dart';

/// Mirrors the server-enforced policy. Server timestamps are authoritative.
class EmergencyUsage {
  static const cancellationWindow = Duration(seconds: 60);
  static const countingWindow = Duration(hours: 24);
  static const banDuration = Duration(hours: 24);
  final int cancellationCount;
  final DateTime? windowStartedAt;
  final DateTime? banStartedAt;
  final bool adminBanned;
  const EmergencyUsage({
    this.cancellationCount = 0,
    this.windowStartedAt,
    this.banStartedAt,
    this.adminBanned = false,
  });

  factory EmergencyUsage.fromMap(Map<String, dynamic> map) {
    DateTime? date(dynamic value) => value is Timestamp
        ? value.toDate()
        : value is DateTime
        ? value
        : null;
    return EmergencyUsage(
      cancellationCount: (map['cancellationCount'] as num?)?.toInt() ?? 0,
      windowStartedAt: date(map['windowStartedAt']),
      banStartedAt: date(map['banStartedAt']),
      adminBanned: map['adminBanned'] == true,
    );
  }
  DateTime? get bannedUntil => banStartedAt?.add(banDuration);
  bool isBanned(DateTime now) =>
      adminBanned || (bannedUntil != null && now.isBefore(bannedUntil!));
  bool startsNewWindow(DateTime now) =>
      windowStartedAt == null ||
      !now.isBefore(windowStartedAt!.add(countingWindow));
  int countAt(DateTime now) => startsNewWindow(now) ? 0 : cancellationCount;
  EmergencyUsage afterCancellation(DateTime now) {
    if (isBanned(now)) {
      throw StateError(
        'Emergency requests are temporarily blocked. Call Edhi 115 for urgent assistance.',
      );
    }
    final count = countAt(now) + 1;
    return EmergencyUsage(
      cancellationCount: count,
      windowStartedAt: startsNewWindow(now) ? now : windowStartedAt,
      banStartedAt: count >= 3 ? now : null,
    );
  }

  static Duration remaining(EmergencyRequest request, DateTime now) {
    if (request.createdAt == null) return Duration.zero;
    final duration = request.createdAt!.add(cancellationWindow).difference(now);
    return duration.isNegative ? Duration.zero : duration;
  }

  static bool canCancel(EmergencyRequest request, DateTime now) =>
      const [
        EmergencyStatus.pending,
        EmergencyStatus.approved,
        EmergencyStatus.assigned,
        EmergencyStatus.inProgress,
        EmergencyStatus.arrived,
      ].contains(request.status) &&
      request.createdAt != null &&
      !now.isBefore(request.createdAt!) &&
      remaining(request, now) > Duration.zero;
}
