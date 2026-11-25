import 'package:cloud_firestore/cloud_firestore.dart';

import 'employee.dart';

/// One "will you take this patient?" offer made to one ambulance driver.
///
/// A linked driver must accept within [DispatchOffer.window]. If they decline
/// or let it time out, the request moves to the next-nearest unit. Missed
/// offers are the driver penalties shown to HQ.
class DispatchOffer {
  /// How long a driver has to acknowledge an automatic assignment.
  static const window = Duration(seconds: 60);

  /// After this many declines/timeouts on one request, HQ gets a red alert.
  static const alertAfterAttempts = 3;

  /// Missed offers in a row before the app takes a driver off duty.
  static const autoOfflineAfterMisses = 2;

  static const pending = 'pending';
  static const accepted = 'accepted';
  static const declined = 'declined';
  static const missed = 'missed';
  static const cancelled = 'cancelled';

  final String offerId;
  final String requestId;
  final String requestUserId;
  final String employeeId;
  final String driverUserId;
  final String driverName;
  final String vehicleNumber;
  final String emergencyType;
  final String priority;
  final String address;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final int attempt;
  final String outcome;
  final DateTime? offeredAt;
  final DateTime? respondedAt;

  const DispatchOffer({
    required this.offerId,
    required this.requestId,
    required this.requestUserId,
    required this.employeeId,
    required this.driverUserId,
    this.driverName = '',
    this.vehicleNumber = '',
    this.emergencyType = '',
    this.priority = '',
    this.address = '',
    this.latitude = 0,
    this.longitude = 0,
    this.distanceKm = 0,
    this.attempt = 1,
    this.outcome = pending,
    this.offeredAt,
    this.respondedAt,
  });

  bool get isPending => outcome == pending;
  DateTime? get expiresAt => offeredAt?.add(window);

  /// Pending and still inside the acknowledgement window.
  bool isLive(DateTime now) {
    final expiry = expiresAt;
    return isPending && expiry != null && now.isBefore(expiry);
  }

  /// Pending but the window has passed: anyone involved may mark it missed.
  bool isExpired(DateTime now, {Duration grace = Duration.zero}) {
    final expiry = expiresAt;
    return isPending && expiry != null && !now.isBefore(expiry.add(grace));
  }

  Duration remaining(DateTime now) {
    final expiry = expiresAt;
    if (expiry == null) return Duration.zero;
    final left = expiry.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// Seconds the driver took to accept or decline; null for missed/pending.
  int? get responseSeconds {
    if (offeredAt == null || respondedAt == null) return null;
    if (outcome != accepted && outcome != declined) return null;
    final seconds = respondedAt!.difference(offeredAt!).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  factory DispatchOffer.fromMap(Map<String, dynamic> map, {String? docId}) {
    return DispatchOffer(
      offerId: docId ?? map['offerId'] as String? ?? '',
      requestId: map['requestId'] as String? ?? '',
      requestUserId: map['requestUserId'] as String? ?? '',
      employeeId: map['employeeId'] as String? ?? '',
      driverUserId: map['driverUserId'] as String? ?? '',
      driverName: map['driverName'] as String? ?? '',
      vehicleNumber: map['vehicleNumber'] as String? ?? '',
      emergencyType: map['emergencyType'] as String? ?? '',
      priority: map['priority'] as String? ?? '',
      address: map['address'] as String? ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
      distanceKm: (map['distanceKm'] as num?)?.toDouble() ?? 0,
      attempt: (map['attempt'] as num?)?.toInt() ?? 1,
      outcome: map['outcome'] as String? ?? pending,
      offeredAt: _date(map['offeredAt']),
      respondedAt: _date(map['respondedAt']),
    );
  }

  factory DispatchOffer.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => DispatchOffer.fromMap(snapshot.data() ?? {}, docId: snapshot.id);

  /// Fields written when the offer is created; offeredAt is set by the caller.
  Map<String, dynamic> toCreateMap() => {
    'requestId': requestId,
    'requestUserId': requestUserId,
    'employeeId': employeeId,
    'driverUserId': driverUserId,
    'driverName': driverName,
    'vehicleNumber': vehicleNumber,
    'emergencyType': emergencyType,
    'priority': priority,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'distanceKm': distanceKm,
    'attempt': attempt,
    'outcome': pending,
    'respondedAt': null,
  };

  DispatchOffer copyWith({String? outcome, DateTime? respondedAt}) =>
      DispatchOffer(
        offerId: offerId,
        requestId: requestId,
        requestUserId: requestUserId,
        employeeId: employeeId,
        driverUserId: driverUserId,
        driverName: driverName,
        vehicleNumber: vehicleNumber,
        emergencyType: emergencyType,
        priority: priority,
        address: address,
        latitude: latitude,
        longitude: longitude,
        distanceKm: distanceKm,
        attempt: attempt,
        outcome: outcome ?? this.outcome,
        offeredAt: offeredAt,
        respondedAt: respondedAt ?? this.respondedAt,
      );
}

/// HQ's per-driver responsiveness summary (the "Driver accountability" table).
class DriverAccountability {
  final Employee unit;
  final int offers;
  final int accepted;
  final int declined;
  final int missed;
  final DateTime? lastAcceptedAt;
  final double? avgResponseSeconds;
  final List<DispatchOffer> history;

  const DriverAccountability({
    required this.unit,
    this.offers = 0,
    this.accepted = 0,
    this.declined = 0,
    this.missed = 0,
    this.lastAcceptedAt,
    this.avgResponseSeconds,
    this.history = const [],
  });

  /// Units without a linked driver account accept automatically.
  bool get autoAccepts => unit.userId.isEmpty;

  double get acceptanceRate => offers == 0 ? 0 : accepted / offers;

  /// Simple traffic-light: red at 3+ penalties, amber at 1-2.
  String get riskLevel => missed >= 3
      ? 'high'
      : missed >= 1
      ? 'watch'
      : 'good';

  static List<DriverAccountability> build(
    Iterable<Employee> units,
    Iterable<DispatchOffer> offers,
  ) {
    final byUnit = <String, List<DispatchOffer>>{};
    for (final offer in offers) {
      byUnit.putIfAbsent(offer.employeeId, () => []).add(offer);
    }
    final rows = <DriverAccountability>[];
    for (final unit in units.where((u) => u.role == 'driver')) {
      final reset = unit.penaltyResetAt;
      final history =
          (byUnit[unit.employeeId] ?? const <DispatchOffer>[])
              .where(
                (o) =>
                    reset == null ||
                    o.offeredAt == null ||
                    !o.offeredAt!.isBefore(reset),
              )
              .where((o) => o.outcome != DispatchOffer.cancelled)
              .toList()
            ..sort(
              (a, b) => (b.offeredAt ?? DateTime(1970)).compareTo(
                a.offeredAt ?? DateTime(1970),
              ),
            );
      final answered = history
          .map((o) => o.responseSeconds)
          .whereType<int>()
          .toList();
      final acceptedOffers = history
          .where((o) => o.outcome == DispatchOffer.accepted)
          .toList();
      rows.add(
        DriverAccountability(
          unit: unit,
          offers: history.where((o) => !o.isPending).length,
          accepted: acceptedOffers.length,
          declined: history
              .where((o) => o.outcome == DispatchOffer.declined)
              .length,
          missed: history
              .where((o) => o.outcome == DispatchOffer.missed)
              .length,
          lastAcceptedAt: acceptedOffers.isEmpty
              ? null
              : acceptedOffers.first.respondedAt,
          avgResponseSeconds: answered.isEmpty
              ? null
              : answered.reduce((a, b) => a + b) / answered.length,
          history: history,
        ),
      );
    }
    rows.sort((a, b) {
      final byMissed = b.missed.compareTo(a.missed);
      return byMissed != 0 ? byMissed : a.unit.name.compareTo(b.unit.name);
    });
    return rows;
  }
}
