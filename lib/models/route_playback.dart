import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';

/// Shared, timestamp-based simulated journey. No device GPS is used.
class RoutePlayback {
  final String requestId;
  final List<LatLng> points;
  final DateTime startedAt;
  final double durationSeconds;
  final double speedFactor;
  final bool enabled;
  final DateTime? pausedAt;
  final DateTime? stoppedAt;
  late final List<double> _distances = _measure();
  RoutePlayback({
    required this.requestId,
    required this.points,
    required this.startedAt,
    required this.durationSeconds,
    this.speedFactor = 1,
    this.enabled = true,
    this.pausedAt,
    this.stoppedAt,
  });
  factory RoutePlayback.fromMap(Map<String, dynamic> map) => RoutePlayback(
    requestId: map['requestId'] as String? ?? '',
    points: (map['points'] as List? ?? [])
        .map(
          (p) => LatLng(
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          ),
        )
        .toList(),
    startedAt: (map['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    durationSeconds: (map['durationSeconds'] as num?)?.toDouble() ?? 1,
    speedFactor: (map['speedFactor'] as num?)?.toDouble() ?? 1,
    enabled: map['enabled'] == true,
    pausedAt: (map['pausedAt'] as Timestamp?)?.toDate(),
    stoppedAt: (map['stoppedAt'] as Timestamp?)?.toDate(),
  );
  List<double> _measure() {
    final result = <double>[0];
    for (var i = 1; i < points.length; i++) {
      result.add(
        result.last +
            const Distance().as(LengthUnit.Meter, points[i - 1], points[i]),
      );
    }
    return result;
  }

  DateTime _effectiveTime(DateTime now) {
    if (pausedAt == null) return stoppedAt ?? now;
    if (stoppedAt == null) return pausedAt!;
    return pausedAt!.isBefore(stoppedAt!) ? pausedAt! : stoppedAt!;
  }

  double progressAt(DateTime now) => durationSeconds <= 0
      ? 1
      : (_effectiveTime(now).difference(startedAt).inMilliseconds /
                (durationSeconds * 1000))
            .clamp(0.0, 1.0);
  bool movingAt(DateTime now) =>
      enabled && pausedAt == null && points.length > 1 && progressAt(now) < 1;
  double get distanceMeters => points.isEmpty ? 0 : _distances.last;
  double remainingSecondsAt(DateTime now) =>
      durationSeconds * (1 - progressAt(now));
  double remainingKmAt(DateTime now) =>
      distanceMeters / 1000 * (1 - progressAt(now));
  int get estimatedSpeedKmh => points.length < 2 || durationSeconds <= 0
      ? 0
      : (_distances.last / (durationSeconds * speedFactor) * 3.6).round();
  LatLng? positionAt(DateTime now) {
    if ((!enabled && stoppedAt == null) || points.isEmpty) return null;
    final target = _distances.last * progressAt(now);
    for (var i = 1; i < points.length; i++) {
      if (target <= _distances[i]) {
        final segment = _distances[i] - _distances[i - 1];
        final ratio = segment == 0
            ? 1.0
            : (target - _distances[i - 1]) / segment;
        return LatLng(
          points[i - 1].latitude +
              (points[i].latitude - points[i - 1].latitude) * ratio,
          points[i - 1].longitude +
              (points[i].longitude - points[i - 1].longitude) * ratio,
        );
      }
    }
    return points.last;
  }

  List<LatLng> remainingPointsAt(DateTime now) {
    final position = positionAt(now);
    if (position == null) return [];
    final target = distanceMeters * progressAt(now);
    final next = _distances.indexWhere((distance) => distance > target);
    return next < 0 ? [position] : [position, ...points.sublist(next)];
  }

  RoutePlayback retimed(DateTime now, double factor, {bool pause = false}) {
    if (![1.0, 3.0, 10.0].contains(factor)) {
      throw ArgumentError('Playback speed must be 1×, 3× or 10×.');
    }
    return RoutePlayback(
      requestId: requestId,
      points: remainingPointsAt(now),
      startedAt: now,
      durationSeconds: remainingSecondsAt(now) * speedFactor / factor,
      speedFactor: factor,
      pausedAt: pause ? now : null,
    );
  }
}
