part of 'firestore_service.dart';

/// Driver acknowledgement: offer → accept / decline / 60-second timeout.
///
/// Any open app moves the job on ("option A"): HQ handles every request, a
/// citizen's app handles its own request, and a driver's app can time out its
/// own missed offer. Firestore rules check the server clock, so nobody can
/// skip a driver early or accept late.
extension DispatchOfferEngine on FirestoreService {
  // ---------------------------------------------------------------- reads

  List<DispatchOffer> get dispatchOffers {
    final list = (isLiveFirebase ? _liveOffers.values : _mockOffers).toList()
      ..sort(
        (a, b) => (b.offeredAt ?? DateTime(1970)).compareTo(
          a.offeredAt ?? DateTime(1970),
        ),
      );
    return List.unmodifiable(list);
  }

  Stream<List<DispatchOffer>> getDispatchOffersStream() async* {
    yield dispatchOffers;
    yield* _offersController.stream;
  }

  /// The live offer ringing on this driver's phone, if any.
  DispatchOffer? pendingOfferForDriver(String driverUserId) {
    final now = _now();
    return dispatchOffers
        .where((o) => o.driverUserId == driverUserId && o.isLive(now))
        .firstOrNull;
  }

  /// The offer currently waiting on a driver for this request, if any.
  DispatchOffer? currentOfferForRequest(EmergencyRequest request) {
    if (!request.hasOffer) return null;
    return dispatchOffers
        .where((o) => o.offerId == request.offerId)
        .firstOrNull;
  }

  List<DriverAccountability> driverAccountability() =>
      DriverAccountability.build(getAllEmployees(), dispatchOffers);

  void _broadcastOffers() {
    if (_disposed || _offersController.isClosed) return;
    _offersController.add(dispatchOffers);
    _notifyOfferListeners();
  }

  // ------------------------------------------------------------ candidates

  /// Available units nearest-first that this request has not already skipped.
  List<Employee> offerCandidates(
    EmergencyRequest request, {
    bool linkedOnly = false,
  }) {
    final now = _now();
    final destination = LatLng(
      request.location.latitude,
      request.location.longitude,
    );
    final blocked = {
      for (final o in dispatchOffers)
        if (o.isLive(now) && o.requestId != request.requestId) o.employeeId,
    };
    final list =
        getAvailableDrivers()
            .where(
              (e) =>
                  e.hasValidLocation &&
                  !request.skippedEmployeeIds.contains(e.employeeId) &&
                  !blocked.contains(e.employeeId) &&
                  !(e.hasLiveOffer(now) &&
                      e.pendingOfferRequestId != request.requestId) &&
                  (!linkedOnly || e.needsAcknowledgement),
            )
            .toList()
          ..sort(
            (a, b) =>
                const Distance()(
                  LatLng(a.currentLat, a.currentLng),
                  destination,
                ).compareTo(
                  const Distance()(
                    LatLng(b.currentLat, b.currentLng),
                    destination,
                  ),
                ),
          );
    return list;
  }

  bool _offerIsLive(EmergencyRequest request) {
    if (!request.hasOffer || request.offerAt == null) return false;
    return _now().isBefore(request.offerAt!.add(DispatchOffer.window));
  }

  // ---------------------------------------------------------------- offer

  /// Offers [request] to [unit]. Units with no driver account accept at once.
  Future<NearestAmbulanceResult> dispatchToUnit(
    String requestId,
    Employee unit,
  ) async {
    final request = await _loadRequest(requestId);
    if (request == null) {
      throw StateError('Emergency request $requestId no longer exists.');
    }
    final distance = const Distance().as(
      LengthUnit.Kilometer,
      LatLng(unit.currentLat, unit.currentLng),
      LatLng(request.location.latitude, request.location.longitude),
    );
    final eta = LocationService.calculateEtaMinutes(
      distance,
      averageSpeedKmH: 45,
    );
    if (!unit.needsAcknowledgement) {
      await assignRequest(
        requestId: requestId,
        employeeId: unit.employeeId,
        employeeName: '${unit.name} (${unit.vehicleNumber})',
      );
      return NearestAmbulanceResult(
        employee: unit,
        distanceKm: distance,
        etaMinutes: eta,
      );
    }
    await _createOffer(request, unit, distance);
    return NearestAmbulanceResult(
      employee: unit,
      distanceKm: distance,
      etaMinutes: eta,
      awaitingAcknowledgement: true,
    );
  }

  Future<EmergencyRequest?> _loadRequest(String requestId) async {
    if (isLiveFirebase) {
      final doc = await _firestore!
          .collection(AppConstants.requestsCollection)
          .doc(requestId)
          .get();
      return doc.exists && doc.data() != null
          ? EmergencyRequest.fromFirestore(doc)
          : null;
    }
    return _mockRequests.where((r) => r.requestId == requestId).firstOrNull;
  }

  void _validateOfferable(EmergencyRequest request, Employee unit) {
    if (!const [
      EmergencyStatus.pending,
      EmergencyStatus.approved,
    ].contains(request.status)) {
      throw StateError('This request is no longer waiting for an ambulance.');
    }
    if (request.fraudRiskLevel == 'High' && !request.isVerified) {
      throw StateError('Verify this high-risk request before dispatch.');
    }
    if (!request.location.hasValidCoordinates) {
      throw StateError('Confirm the patient location before dispatch.');
    }
    if (_offerIsLive(request)) {
      throw StateError('A driver is already being asked to take this job.');
    }
    if (unit.role != 'driver' || unit.status != 'available') {
      throw StateError('${unit.name} is not available right now.');
    }
    if (unit.hasLiveOffer(_now()) &&
        unit.pendingOfferRequestId != request.requestId) {
      throw StateError('${unit.name} is answering another emergency.');
    }
  }

  Future<void> _createOffer(
    EmergencyRequest request,
    Employee unit,
    double distanceKm,
  ) async {
    _validateOfferable(request, unit);
    final skipped = request.skippedEmployeeIds;
    final draft = DispatchOffer(
      offerId: '',
      requestId: request.requestId,
      requestUserId: request.userId,
      employeeId: unit.employeeId,
      driverUserId: unit.userId,
      driverName: unit.name,
      vehicleNumber: unit.vehicleNumber,
      emergencyType: request.emergencyType,
      priority: request.priority,
      address: request.location.address,
      latitude: request.location.latitude,
      longitude: request.location.longitude,
      distanceKm: double.parse(distanceKm.toStringAsFixed(2)),
      attempt: request.offerAttempts + 1,
    );
    if (isLiveFirebase) {
      final db = _firestore!;
      final requestRef = db
          .collection(AppConstants.requestsCollection)
          .doc(request.requestId);
      final unitRef = db
          .collection(AppConstants.employeesCollection)
          .doc(unit.employeeId);
      final offerRef = db.collection(FirestoreService.offersCollection).doc();
      await db.runTransaction((tx) async {
        final latest = await tx.get(requestRef);
        final latestUnit = await tx.get(unitRef);
        if (!latest.exists || !latestUnit.exists) {
          throw StateError('Request or ambulance no longer exists.');
        }
        final current = EmergencyRequest.fromFirestore(latest);
        final currentUnit = Employee.fromFirestore(latestUnit);
        _validateOfferable(current, currentUnit);
        if (current.skippedEmployeeIds.contains(unit.employeeId)) {
          throw StateError('${unit.name} already passed on this job.');
        }
        tx.update(requestRef, {
          'offerId': offerRef.id,
          'offerEmployeeId': unit.employeeId,
          'offerAt': FieldValue.serverTimestamp(),
          'offerAttempts': current.offerAttempts + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(unitRef, {
          'pendingOfferRequestId': request.requestId,
          'pendingOfferAt': FieldValue.serverTimestamp(),
        });
        tx.set(offerRef, {
          ...draft.toCreateMap(),
          'offeredAt': FieldValue.serverTimestamp(),
        });
      });
      // Shown at once; the listener replaces it with the server timestamp.
      _liveOffers[offerRef.id] = DispatchOffer.fromMap({
        ...draft.toCreateMap(),
        'offeredAt': _now(),
      }, docId: offerRef.id);
    } else {
      final index = _mockRequests.indexWhere(
        (r) => r.requestId == request.requestId,
      );
      final unitIndex = _mockEmployees.indexWhere(
        (e) => e.employeeId == unit.employeeId,
      );
      if (index < 0 || unitIndex < 0) {
        throw StateError('Request or ambulance no longer exists.');
      }
      final now = _now();
      final offerId = _newRecordId('OFR');
      _mockRequests[index] = _mockRequests[index].copyWith(
        offerId: offerId,
        offerEmployeeId: unit.employeeId,
        offerAt: now,
        offerAttempts: _mockRequests[index].offerAttempts + 1,
        skippedEmployeeIds: skipped,
        updatedAt: now,
      );
      _mockEmployees[unitIndex] = _mockEmployees[unitIndex].copyWith(
        pendingOfferRequestId: request.requestId,
        pendingOfferAt: now,
      );
      _mockOffers.add(
        DispatchOffer.fromMap({
          ...draft.toCreateMap(),
          'offeredAt': now,
        }, docId: offerId),
      );
      _broadcastAll();
    }
    _broadcastOffers();
    _notificationService?.sendNotification(
      userId: unit.userId,
      title: 'Emergency offer · accept within 60 s',
      message:
          '${request.emergencyType} at ${request.location.address} (${distanceKm.toStringAsFixed(1)} km). Open the driver app to accept.',
      type: 'emergency',
    );
    await _logAudit(
      action: 'offer_sent',
      entityType: 'emergency',
      entityId: request.requestId,
      actorId: _sessionUserId ?? 'dispatcher',
      details:
          'Offered to ${unit.name} (${unit.vehicleNumber}), attempt ${draft.attempt}',
    );
  }

  // --------------------------------------------------------------- accept

  /// The offered driver takes the job: the trip starts immediately.
  Future<void> acceptDispatchOffer(String offerId) async {
    final offer = dispatchOffers.where((o) => o.offerId == offerId).firstOrNull;
    if (offer == null) {
      throw StateError('This offer is no longer available.');
    }
    if (!offer.isLive(_now())) {
      throw StateError(
        'The 60-second window has passed and the job moved to another ambulance.',
      );
    }
    final request = await _loadRequest(offer.requestId);
    final unit = getAllEmployees()
        .where((e) => e.employeeId == offer.employeeId)
        .firstOrNull;
    if (request == null || unit == null) {
      throw StateError('Request or ambulance no longer exists.');
    }
    if (request.offerId != offerId) {
      throw StateError('This job was reassigned or cancelled.');
    }
    final simulationSpeed = _simulationSpeed;
    final route = automaticSimulation
        ? await _loadSimulationRoute(
            LatLng(unit.currentLat, unit.currentLng),
            LatLng(request.location.latitude, request.location.longitude),
          )
        : null;
    final points = route == null
        ? <LatLng>[]
        : _boundedRoutePoints(route.points);
    final duration = route == null
        ? 1.0
        : (route.travelSeconds / simulationSpeed).clamp(1.0, 86400.0);
    final employeeName = '${unit.name} (${unit.vehicleNumber})';
    final nextStatus = automaticSimulation
        ? EmergencyStatus.inProgress
        : EmergencyStatus.assigned;

    if (isLiveFirebase) {
      final db = _firestore!;
      final requestRef = db
          .collection(AppConstants.requestsCollection)
          .doc(offer.requestId);
      final unitRef = db
          .collection(AppConstants.employeesCollection)
          .doc(offer.employeeId);
      final offerRef = db
          .collection(FirestoreService.offersCollection)
          .doc(offerId);
      await db.runTransaction((tx) async {
        final latest = EmergencyRequest.fromFirestore(await tx.get(requestRef));
        final latestUnit = await tx.get(unitRef);
        final latestOffer = await tx.get(offerRef);
        if (latest.offerId != offerId ||
            latestOffer.data()?['outcome'] != DispatchOffer.pending ||
            !const [
              EmergencyStatus.pending,
              EmergencyStatus.approved,
            ].contains(latest.status)) {
          throw StateError('This job was reassigned or cancelled.');
        }
        if (latestUnit.data()?['status'] != 'available') {
          throw StateError('Your ambulance is not marked available.');
        }
        tx.update(requestRef, {
          'status': nextStatus,
          'assignedEmployeeId': offer.employeeId,
          'assignedEmployeeName': employeeName,
          'assignedDriverUserId': latestUnit.data()?['userId'],
          'offerId': null,
          'offerEmployeeId': null,
          'offerAt': null,
          'acceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(unitRef, {
          'status': 'busy',
          'activeRequestId': offer.requestId,
          'pendingOfferRequestId': '',
          'pendingOfferAt': null,
          'missedStreak': 0,
        });
        tx.update(offerRef, {
          'outcome': DispatchOffer.accepted,
          'respondedAt': FieldValue.serverTimestamp(),
        });
        tx.set(db.collection('route_demos').doc(offer.employeeId), {
          'requestId': offer.requestId,
          'userId': latest.userId,
          'driverUserId': latestUnit.data()?['userId'],
          'enabled': automaticSimulation,
          'points': points
              .map((p) => {'lat': p.latitude, 'lng': p.longitude})
              .toList(),
          'startedAt': FieldValue.serverTimestamp(),
          'durationSeconds': duration,
          'speedFactor': simulationSpeed,
          'pausedAt': null,
          'stoppedAt': null,
          'simulation': true,
        });
      });
      _liveOffers[offerId] = offer.copyWith(
        outcome: DispatchOffer.accepted,
        respondedAt: _now(),
      );
    } else {
      final index = _mockRequests.indexWhere(
        (r) => r.requestId == offer.requestId,
      );
      final unitIndex = _mockEmployees.indexWhere(
        (e) => e.employeeId == offer.employeeId,
      );
      final offerIndex = _mockOffers.indexWhere((o) => o.offerId == offerId);
      if (index < 0 || unitIndex < 0 || offerIndex < 0) {
        throw StateError('Request or ambulance no longer exists.');
      }
      final now = _now();
      _mockRequests[index] = _mockRequests[index].copyWith(
        status: nextStatus,
        assignedEmployeeId: offer.employeeId,
        assignedEmployeeName: employeeName,
        clearOffer: true,
        acceptedAt: now,
        updatedAt: now,
      );
      _mockEmployees[unitIndex] = _mockEmployees[unitIndex].copyWith(
        status: 'busy',
        activeRequestId: offer.requestId,
        clearOffer: true,
        missedStreak: 0,
      );
      _mockOffers[offerIndex] = offer.copyWith(
        outcome: DispatchOffer.accepted,
        respondedAt: now,
      );
      if (automaticSimulation) {
        _routeDemos[offer.employeeId] = RoutePlayback(
          requestId: offer.requestId,
          points: points,
          startedAt: now,
          durationSeconds: duration,
          speedFactor: simulationSpeed,
        );
        _ensureDemoTicker();
      }
      _broadcastAll();
    }
    _broadcastOffers();
    _notificationService?.sendNotification(
      userId: request.userId,
      title: 'Driver accepted · ambulance on the way',
      message:
          '${unit.name} (${unit.vehicleNumber}) accepted your emergency and is heading to you now.',
      type: 'emergency',
    );
    await _logAudit(
      action: 'offer_accepted',
      entityType: 'emergency',
      entityId: offer.requestId,
      actorId: offer.employeeId,
      details:
          '$employeeName accepted in ${offer.offeredAt == null ? '?' : _now().difference(offer.offeredAt!).inSeconds} s',
    );
  }

  // ------------------------------------------------- decline / missed

  /// The driver says no: the job moves on at once, recorded as "Declined".
  Future<void> declineDispatchOffer(String offerId) async {
    final offer = dispatchOffers.where((o) => o.offerId == offerId).firstOrNull;
    if (offer == null || !offer.isPending) {
      throw StateError('This offer is no longer available.');
    }
    await _releaseOffer(offer, DispatchOffer.declined);
  }

  /// Closes an offer and passes the request on (declined/missed), or marks it
  /// cancelled when the request itself is no longer waiting.
  Future<void> _releaseOffer(DispatchOffer offer, String outcome) async {
    var wentOffline = false;
    final isDriver = _sessionRole == AppRoles.employee;
    final isAdmin = !isLiveFirebase || _sessionRole == AppRoles.admin;
    if (isLiveFirebase) {
      final db = _firestore!;
      final requestRef = db
          .collection(AppConstants.requestsCollection)
          .doc(offer.requestId);
      final offerRef = db
          .collection(FirestoreService.offersCollection)
          .doc(offer.offerId);
      final unitRef = db
          .collection(AppConstants.employeesCollection)
          .doc(offer.employeeId);
      var finalOutcome = outcome;
      await db.runTransaction((tx) async {
        wentOffline = false;
        final latestOffer = await tx.get(offerRef);
        if (latestOffer.data()?['outcome'] != DispatchOffer.pending) {
          return;
        }
        final latestDoc = await tx.get(requestRef);
        final unitDoc = await tx.get(unitRef);
        final latest = latestDoc.exists
            ? EmergencyRequest.fromFirestore(latestDoc)
            : null;
        final stillCurrent =
            latest != null &&
            latest.offerId == offer.offerId &&
            const [
              EmergencyStatus.pending,
              EmergencyStatus.approved,
            ].contains(latest.status);
        if (latest != null &&
            latest.offerId == offer.offerId &&
            !stillCurrent) {
          finalOutcome = DispatchOffer.cancelled;
        }
        if (stillCurrent) {
          final skipped = [
            ...latest.skippedEmployeeIds,
            if (!latest.skippedEmployeeIds.contains(offer.employeeId))
              offer.employeeId,
          ];
          tx.update(requestRef, {
            'offerId': null,
            'offerEmployeeId': null,
            'offerAt': null,
            'skippedEmployeeIds': skipped,
            'dispatchAlert':
                latest.dispatchAlert ||
                latest.offerAttempts >= DispatchOffer.alertAfterAttempts,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        tx.update(offerRef, {
          'outcome': finalOutcome,
          'respondedAt': FieldValue.serverTimestamp(),
        });
        final ownOrHq =
            isAdmin || (isDriver && offer.driverUserId == _sessionUserId);
        final unitUpdate = <String, dynamic>{
          if (ownOrHq) 'pendingOfferRequestId': '',
          if (ownOrHq) 'pendingOfferAt': null,
        };
        final unit = unitDoc.exists ? Employee.fromFirestore(unitDoc) : null;
        if (unit != null && finalOutcome == DispatchOffer.missed) {
          // Count the miss; the second in a row takes the unit off duty.
          final streak = unit.missedStreak + 1;
          unitUpdate['missedStreak'] = streak;
          unitUpdate['lastMissedOfferId'] = offer.offerId;
          if (streak >= DispatchOffer.autoOfflineAfterMisses &&
              unit.status == 'available') {
            unitUpdate['status'] = 'offline';
            unitUpdate['autoOfflineAt'] = FieldValue.serverTimestamp();
            wentOffline = true;
          }
        } else if (unit != null &&
            finalOutcome == DispatchOffer.declined &&
            ownOrHq) {
          unitUpdate['missedStreak'] = 0; // Answering shows they are active.
        }
        if (unit != null && unitUpdate.isNotEmpty) {
          tx.update(unitRef, unitUpdate);
        }
      });
      _liveOffers[offer.offerId] = offer.copyWith(
        outcome: finalOutcome,
        respondedAt: _now(),
      );
      outcome = finalOutcome;
    } else {
      final offerIndex = _mockOffers.indexWhere(
        (o) => o.offerId == offer.offerId,
      );
      if (offerIndex < 0 || !_mockOffers[offerIndex].isPending) return;
      final index = _mockRequests.indexWhere(
        (r) => r.requestId == offer.requestId,
      );
      final latest = index < 0 ? null : _mockRequests[index];
      final stillCurrent =
          latest != null &&
          latest.offerId == offer.offerId &&
          const [
            EmergencyStatus.pending,
            EmergencyStatus.approved,
          ].contains(latest.status);
      if (latest != null && latest.offerId == offer.offerId && !stillCurrent) {
        outcome = DispatchOffer.cancelled;
      }
      if (stillCurrent) {
        _mockRequests[index] = latest.copyWith(
          clearOffer: true,
          skippedEmployeeIds: [
            ...latest.skippedEmployeeIds,
            if (!latest.skippedEmployeeIds.contains(offer.employeeId))
              offer.employeeId,
          ],
          dispatchAlert:
              latest.dispatchAlert ||
              latest.offerAttempts >= DispatchOffer.alertAfterAttempts,
          updatedAt: _now(),
        );
      }
      final unitIndex = _mockEmployees.indexWhere(
        (e) => e.employeeId == offer.employeeId,
      );
      if (unitIndex >= 0) {
        var unit = _mockEmployees[unitIndex];
        if (unit.pendingOfferRequestId == offer.requestId) {
          unit = unit.copyWith(clearOffer: true);
        }
        if (outcome == DispatchOffer.missed) {
          final streak = unit.missedStreak + 1;
          unit = unit.copyWith(missedStreak: streak);
          if (streak >= DispatchOffer.autoOfflineAfterMisses &&
              unit.status == 'available') {
            unit = unit.copyWith(status: 'offline', autoOfflineAt: _now());
            wentOffline = true;
          }
        } else if (outcome == DispatchOffer.declined) {
          unit = unit.copyWith(missedStreak: 0);
        }
        _mockEmployees[unitIndex] = unit;
      }
      _mockOffers[offerIndex] = offer.copyWith(
        outcome: outcome,
        respondedAt: _now(),
      );
      _broadcastAll();
    }
    _broadcastOffers();
    if (outcome == DispatchOffer.missed) {
      _notificationService?.sendNotification(
        userId: offer.driverUserId,
        title: 'Missed emergency · penalty recorded',
        message:
            'You did not answer the ${offer.emergencyType} offer within 60 seconds. It was passed to the next ambulance.',
        type: 'emergency',
      );
    }
    if (wentOffline) {
      _notificationService?.sendNotification(
        userId: offer.driverUserId,
        title: 'You were taken off duty',
        message:
            'You missed ${DispatchOffer.autoOfflineAfterMisses} emergencies in a row, so new emergencies go to other ambulances. Switch "Available for dispatch" back on when you are ready.',
        type: 'emergency',
      );
      await _logAudit(
        action: 'driver_auto_offline',
        entityType: 'ambulance',
        entityId: offer.employeeId,
        actorId: _sessionUserId ?? 'dispatcher',
        details:
            '${offer.driverName} (${offer.vehicleNumber}) set off duty after ${DispatchOffer.autoOfflineAfterMisses} missed offers in a row',
      );
    }
    await _logAudit(
      action: 'offer_$outcome',
      entityType: 'emergency',
      entityId: offer.requestId,
      actorId: outcome == DispatchOffer.declined
          ? offer.employeeId
          : (_sessionUserId ?? 'dispatcher'),
      details: '${offer.driverName} (${offer.vehicleNumber}): $outcome',
    );
  }

  /// When a request is cancelled or completed, close its waiting offer.
  Future<void> _closeOffersFor(String requestId) async {
    for (final offer in dispatchOffers.where(
      (o) => o.requestId == requestId && o.isPending,
    )) {
      try {
        await _releaseOffer(offer, DispatchOffer.cancelled);
      } catch (error) {
        debugPrint('Offer close: $error');
      }
    }
  }

  /// Every round of offers was refused: start again from the nearest unit and
  /// raise the HQ alert.
  Future<void> _restartOfferRound(EmergencyRequest request) async {
    if (isLiveFirebase) {
      await _firestore!
          .collection(AppConstants.requestsCollection)
          .doc(request.requestId)
          .update({
            'skippedEmployeeIds': <String>[],
            'dispatchAlert': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } else {
      final index = _mockRequests.indexWhere(
        (r) => r.requestId == request.requestId,
      );
      if (index < 0) return;
      _mockRequests[index] = _mockRequests[index].copyWith(
        skippedEmployeeIds: const [],
        dispatchAlert: true,
        updatedAt: _now(),
      );
      _broadcastAll();
    }
  }

  // ------------------------------------------------------------ the loop

  /// Runs every second from whichever portal is open.
  Future<void> advanceDispatchOffers() async {
    if (_disposed || _offerLoopBusy) return;
    _offerLoopBusy = true;
    try {
      final now = _now();
      final role = _sessionRole;
      // 1) Time out expired offers (2 s grace for clock skew).
      for (final offer in dispatchOffers.where(
        (o) => o.isExpired(now, grace: const Duration(seconds: 2)),
      )) {
        final mine =
            !isLiveFirebase ||
            role == AppRoles.admin ||
            offer.requestUserId == _sessionUserId ||
            offer.driverUserId == _sessionUserId;
        if (!mine) continue;
        if (_offerRetryAt[offer.offerId]?.isAfter(now) == true) continue;
        try {
          await _releaseOffer(offer, DispatchOffer.missed);
          _offerRetryAt.remove(offer.offerId);
        } catch (error) {
          _offerRetryAt[offer.offerId] = now.add(const Duration(seconds: 5));
          debugPrint('Offer timeout retry: $error');
        }
      }
      // 2) A citizen's app keeps its own request moving when HQ is offline.
      if (isLiveFirebase && role == AppRoles.user && automaticSimulation) {
        for (final request in _ownOpenRequests.values.toList()) {
          if (!const [
                EmergencyStatus.pending,
                EmergencyStatus.approved,
              ].contains(request.status) ||
              (request.fraudRiskLevel == 'High' && !request.isVerified) ||
              _offerIsLive(request) ||
              request.hasOffer ||
              _autoDispatchRetryAt[request.requestId]?.isAfter(now) == true) {
            continue;
          }
          _autoDispatchRetryAt[request.requestId] = now.add(
            const Duration(seconds: 4),
          );
          try {
            await autoDispatchNearestAmbulance(request.requestId);
          } catch (error) {
            debugPrint('Citizen-side dispatch retry: $error');
          }
        }
      }
    } finally {
      _offerLoopBusy = false;
    }
  }

  /// HQ clears a driver's penalty count (history is kept for audit).
  Future<void> resetDriverPenalties(String employeeId) async {
    if (isLiveFirebase) {
      if (_sessionRole != AppRoles.admin) {
        throw StateError('Only HQ can reset penalties.');
      }
      await _firestore!
          .collection(AppConstants.employeesCollection)
          .doc(employeeId)
          .update({'penaltyResetAt': FieldValue.serverTimestamp()});
    } else {
      final index = _mockEmployees.indexWhere(
        (e) => e.employeeId == employeeId,
      );
      if (index < 0) throw StateError('Ambulance no longer exists.');
      _mockEmployees[index] = _mockEmployees[index].copyWith(
        penaltyResetAt: _now(),
      );
      _broadcastAll();
    }
    _broadcastOffers();
    await _logAudit(
      action: 'penalties_reset',
      entityType: 'employee',
      entityId: employeeId,
      actorId: _sessionUserId ?? 'admin',
      details: 'Driver penalty count reset by HQ',
    );
  }
}
