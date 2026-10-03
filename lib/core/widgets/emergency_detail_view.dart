import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/emergency_request.dart';
import '../../models/emergency_usage.dart';
import '../../models/employee.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/route_service.dart';
import '../constants/app_constants.dart';
import '../theme/app_colors.dart';
import 'contact_actions.dart';
import 'dispatch_progress.dart';
import 'interactive_map_widget.dart';
import 'responsive_shell.dart';
import 'status_badge.dart';

class EmergencyDetailView extends StatefulWidget {
  final String requestId;
  final bool driverMode;
  const EmergencyDetailView({
    super.key,
    required this.requestId,
    this.driverMode = false,
  });
  @override
  State<EmergencyDetailView> createState() => _EmergencyDetailViewState();
}

class _EmergencyDetailViewState extends State<EmergencyDetailView> {
  bool _updating = false;
  FirestoreService? _service;
  String? _gpsEmployeeId;
  late Stream<EmergencyRequest?> _requestStream;
  late Stream<List<Employee>> _employeeStream;
  Stream<EmergencyUsage>? _usageStream;
  String? _usageUserId;
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<FirestoreService>();
    if (_service != service) {
      _service = service;
      _requestStream = service.getRequestStream(widget.requestId);
      _employeeStream = service.getEmployeesStream();
    }
    final uid = context.read<AuthService>().currentUser?.id;
    if (uid != null && uid != _usageUserId) {
      _usageUserId = uid;
      _usageStream = service.watchEmergencyUsage(uid);
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    // GPS belongs to the on-duty session, not this route's lifetime.
    super.dispose();
  }

  Future<void> _changeStatus(String status) async {
    if (_updating) return;
    final profile = context.read<AuthService>().currentUser;
    final citizenCompletion =
        status == EmergencyStatus.completed &&
        !widget.driverMode &&
        profile?.isAdmin == false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          status == EmergencyStatus.cancelled
              ? 'Cancel this request?'
              : citizenCompletion
              ? 'Confirm help received?'
              : 'Confirm status update?',
        ),
        content: Text(
          status == EmergencyStatus.arrived
              ? 'Confirm you have reached the patient.'
              : status == EmergencyStatus.completed
              ? citizenCompletion
                    ? 'Only confirm after you have received assistance and no longer need this ambulance. The job will close and the driver will become available for another request.'
                    : 'Confirm the response is complete and the ambulance can return to available.'
              : status == EmergencyStatus.cancelled
              ? 'The ambulance will be released. This counts as one cancellation. Three cancellations within 24 hours block new ambulance requests for 24 hours. You can still call Edhi 115.'
              : 'Start travelling to the patient?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _updating = true);
    try {
      EmergencyUsage? usage;
      bool completedNow = true;
      final user = context.read<AuthService>().currentUser;
      if (status == EmergencyStatus.cancelled &&
          user != null &&
          !user.isAdmin) {
        usage = await _service!.cancelEmergencyRequest(
          widget.requestId,
          user.id,
        );
      } else if (citizenCompletion && user != null) {
        completedNow = await _service!.completeCitizenResponse(
          widget.requestId,
          user.id,
        );
      } else if (status == EmergencyStatus.completed &&
          user?.isEmployee == true) {
        completedNow = await _service!.completeDriverResponse(
          widget.requestId,
          user!.id,
        );
      } else {
        await _service!.updateRequestStatus(widget.requestId, status);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              usage?.isBanned(DateTime.now()) == true
                  ? 'Third cancellation: ambulance requests blocked for 24 hours. For urgent help call 115.'
                  : status == EmergencyStatus.completed
                  ? completedNow
                        ? 'Response completed. The ambulance is available again.'
                        : 'This response was already completed.'
                  : 'Dispatch status updated.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Widget _card(Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
  @override
  Widget build(BuildContext context) {
    final service = context.watch<FirestoreService>();
    final user = context.watch<AuthService>().currentUser;
    return ResponsiveShell(
      appBar: AppBar(
        title: Text(
          widget.driverMode ? 'Assigned emergency' : 'Track emergency',
        ),
      ),
      child: StreamBuilder<EmergencyUsage>(
        stream: _usageStream,
        builder: (context, usageSnapshot) => StreamBuilder<EmergencyRequest?>(
          stream: _requestStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Unable to load this request. Check your connection or access.',
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final request = snapshot.data;
            if (request == null) {
              return const Center(child: Text('Request not found.'));
            }
            if (user == null) {
              return const Center(child: Text('Please sign in.'));
            }
            if (!widget.driverMode &&
                !user.isAdmin &&
                request.userId != user.id) {
              return const Center(child: Text('This is not your request.'));
            }
            return StreamBuilder<List<Employee>>(
              stream: _employeeStream,
              builder: (context, employeeSnapshot) {
                final driver =
                    (employeeSnapshot.data ?? service.getAllEmployees())
                        .where(
                          (e) => e.employeeId == request.assignedEmployeeId,
                        )
                        .firstOrNull;
                if (widget.driverMode &&
                    !user.isAdmin &&
                    (driver == null || driver.userId != user.id)) {
                  return Center(
                    child: Text(
                      employeeSnapshot.connectionState ==
                              ConnectionState.waiting
                          ? 'Loading assignment…'
                          : 'This job is not assigned to you.',
                    ),
                  );
                }
                final terminal =
                    request.status == EmergencyStatus.cancelled ||
                    request.status == EmergencyStatus.completed;
                if (!FirestoreService.simulatedFleetEnabled &&
                    widget.driverMode &&
                    driver != null &&
                    driver.userId == user.id &&
                    !terminal &&
                    _gpsEmployeeId == null) {
                  _gpsEmployeeId = driver.employeeId;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && service.isLiveFirebase) {
                      service.startLiveDriverLocation(driver.employeeId);
                    }
                  });
                }
                final next = switch (request.status) {
                  EmergencyStatus.assigned => (
                    EmergencyStatus.inProgress,
                    'Start journey',
                  ),
                  EmergencyStatus.inProgress => (
                    EmergencyStatus.arrived,
                    'I have arrived',
                  ),
                  EmergencyStatus.arrived => (
                    EmergencyStatus.completed,
                    'Complete response',
                  ),
                  _ => null,
                };
                final validLocation = request.location.hasValidCoordinates;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (!widget.driverMode &&
                        !user.isAdmin &&
                        request.userId == user.id &&
                        request.status == EmergencyStatus.arrived)
                      _card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Has your assistance finished?',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'You can confirm help received even if the driver has not closed the job. This frees the ambulance for the next request.',
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _updating
                                  ? null
                                  : () => _changeStatus(
                                      EmergencyStatus.completed,
                                    ),
                              icon: const Icon(Icons.task_alt),
                              label: Text(
                                _updating
                                    ? 'Updating…'
                                    : 'Confirm help received',
                              ),
                            ),
                          ],
                        ),
                      ),
                    _card(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              StatusBadge(status: request.status),
                              PriorityBadge(priority: request.priority),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            request.emergencyType,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Request #${request.requestId}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(request.description),
                          const SizedBox(height: 10),
                          Text(
                            'Patient: ${request.userName.isEmpty ? 'Not provided' : request.userName}',
                          ),
                          if (widget.driverMode && request.userPhone.isNotEmpty)
                            TextButton.icon(
                              onPressed: () =>
                                  openDialer(context, request.userPhone),
                              icon: const Icon(Icons.call_outlined),
                              label: const Text('Call patient'),
                            ),
                        ],
                      ),
                    ),
                    if ((widget.driverMode || user.isAdmin) &&
                        next != null &&
                        (!FirestoreService.simulatedFleetEnabled ||
                            request.status == EmergencyStatus.arrived))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: FilledButton.icon(
                          onPressed: _updating
                              ? null
                              : () => _changeStatus(next.$1),
                          icon: const Icon(Icons.arrow_forward),
                          label: Text(_updating ? 'Updating…' : next.$2),
                        ),
                      ),
                    if (widget.driverMode &&
                        driver != null &&
                        service.driverLocationError(driver.employeeId) != null)
                      _card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              service.driverLocationError(driver.employeeId)!,
                            ),
                            TextButton(
                              onPressed: () => service.startLiveDriverLocation(
                                driver.employeeId,
                              ),
                              child: const Text('Retry GPS'),
                            ),
                          ],
                        ),
                      ),
                    _card(DispatchProgress(status: request.status)),
                    if (!terminal)
                      _card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Patient location',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              request.location.address.isEmpty
                                  ? 'Address not provided'
                                  : request.location.address,
                            ),
                            const SizedBox(height: 12),
                            if (validLocation)
                              _RequestMap(request: request, driver: driver)
                            else
                              const Text(
                                'Coordinates unavailable. Call the patient or dispatch to confirm the location.',
                              ),
                            if (validLocation && widget.driverMode)
                              OutlinedButton.icon(
                                icon: const Icon(Icons.directions),
                                label: const Text('Open navigation'),
                                onPressed: () async {
                                  final ok =
                                      await LocationService.openGoogleMapsNavigation(
                                        request.location.latitude,
                                        request.location.longitude,
                                      );
                                  if (!ok && context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Could not open navigation.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    _card(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Assigned ambulance',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            request.assignedEmployeeName ??
                                'Waiting for dispatch to assign an available unit.',
                          ),
                          if (driver != null) ...[
                            Text(driver.vehicleNumber),
                            Text(
                              _gpsMessage(driver),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (!widget.driverMode && driver.phone.isNotEmpty)
                              TextButton.icon(
                                onPressed: () =>
                                    openDialer(context, driver.phone),
                                icon: const Icon(Icons.call_outlined),
                                label: const Text('Call driver'),
                              ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.driverMode)
                      _card(
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('Preparation checklist'),
                          subtitle: const Text(
                            'Suggested equipment; confirm with dispatch.',
                          ),
                          children: service
                              .buildResponsePlan(request)
                              .requiredEquipment
                              .map(
                                (item) => ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.medical_services_outlined,
                                  ),
                                  title: Text(item),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    if (!widget.driverMode && request.userId == user.id)
                      _cancellationCard(
                        request,
                        usageSnapshot.data ?? const EmergencyUsage(),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _cancellationCard(EmergencyRequest request, EmergencyUsage usage) {
    final now = DateTime.now();
    final remaining = EmergencyUsage.remaining(request, now);
    final seconds = (remaining.inMicroseconds / Duration.microsecondsPerSecond)
        .ceil();
    final canCancel =
        EmergencyUsage.canCancel(request, now) && !usage.isBanned(now);
    final terminal =
        request.status == EmergencyStatus.cancelled ||
        request.status == EmergencyStatus.completed;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            usage.isBanned(now)
                ? 'Ambulance requests blocked until ${usage.bannedUntil!.toLocal()}. Call 115 for urgent assistance.'
                : '${usage.countAt(now)}/3 cancellations in the current 24-hour window. Three cancellations cause a 24-hour request block.',
          ),
          if (!terminal) ...[
            const SizedBox(height: 8),
            const Text(
              'Cancel within 1 minute of submitting, even if a driver is assigned or on the way. Assignment does not reset the timer.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _updating || !canCancel
                  ? null
                  : () => _changeStatus(EmergencyStatus.cancelled),
              icon: const Icon(Icons.cancel_outlined),
              label: Text(
                canCancel
                    ? 'Cancel request • ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')} left'
                    : 'Cancellation window closed',
              ),
            ),
            if (!canCancel)
              const Text(
                'Contact Operations if plans change. For an urgent emergency, call Edhi 115.',
              ),
          ],
          TextButton.icon(
            onPressed: () => openDialer(context, '115'),
            icon: const Icon(Icons.call),
            label: const Text('Call Edhi 115'),
          ),
        ],
      ),
    );
  }

  String _gpsMessage(Employee driver) {
    if (FirestoreService.simulatedFleetEnabled) {
      return 'Road-route position • not device GPS.';
    }
    final heartbeat = driver.transitLastHeartbeat;
    if (heartbeat == null) return 'GPS update not yet received.';
    final age = DateTime.now().millisecondsSinceEpoch - heartbeat;
    return driver.hasFreshGps(DateTime.now())
        ? 'GPS updated within the last minute.'
        : 'GPS is stale; last update ${(age / 60000).floor()} min ago.';
  }
}

class _RequestMap extends StatefulWidget {
  final EmergencyRequest request;
  final Employee? driver;
  const _RequestMap({required this.request, this.driver});
  @override
  State<_RequestMap> createState() => _RequestMapState();
}

class _RequestMapState extends State<_RequestMap> {
  RoadRouteResult? _route;
  LatLng? _routeStart;
  bool _fetching = false;
  DateTime? _lastFetch;
  LatLng get destination => LatLng(
    widget.request.location.latitude,
    widget.request.location.longitude,
  );
  LatLng? get start =>
      widget.driver == null ||
          (!widget.driver!.isDemo &&
              widget.driver!.transitLastHeartbeat == null &&
              widget.driver!.locationUpdatedAt == null) ||
          !widget.driver!.hasValidLocation
      ? null
      : LatLng(widget.driver!.currentLat, widget.driver!.currentLng);
  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant _RequestMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final point = start;
    if (point != null &&
        (_routeStart == null ||
            const Distance().as(LengthUnit.Meter, _routeStart!, point) > 150)) {
      _fetch();
    }
  }

  Future<void> _fetch() async {
    if (FirestoreService.simulatedFleetEnabled) return;
    final point = start;
    if (_fetching || point == null) return;
    if (_lastFetch != null &&
        DateTime.now().difference(_lastFetch!).inSeconds < 10) {
      return;
    }
    _fetching = true;
    _lastFetch = DateTime.now();
    try {
      final route = await RouteService.getRoadRoute(point, destination);
      if (mounted) {
        setState(() {
          _route = route;
          _routeStart = point;
        });
      }
    } catch (_) {
    } finally {
      _fetching = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final point = start;
    final playback = widget.driver == null
        ? null
        : context.read<FirestoreService>().getTransitPlayback(
            widget.driver!.employeeId,
          );
    final savedPoints = playback?.remainingPointsAt(DateTime.now());
    final center = point == null
        ? destination
        : LatLng(
            (point.latitude + destination.latitude) / 2,
            (point.longitude + destination.longitude) / 2,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InteractiveMapWidget(
            height: 260,
            center: center,
            zoom: 13,
            markers: [
              MapMarkerBuilder.emergencyPin(destination, label: 'Patient'),
              if (point != null)
                MapMarkerBuilder.liveAmbulancePin(
                  point,
                  vehicleNumber: widget.driver!.vehicleNumber,
                  status: widget.driver!.status,
                  isAssigned: true,
                  key: ValueKey(widget.driver!.employeeId),
                ),
            ],
            polylines: savedPoints != null && savedPoints.length >= 2
                ? [
                    Polyline(
                      points: savedPoints,
                      color: AppColors.reliefGreenMedium,
                      strokeWidth: 4,
                    ),
                  ]
                : _route == null || !_route!.isRealRoadRoute
                ? []
                : [
                    Polyline(
                      points: LocationService.trimRouteAhead(
                        _route!.points,
                        point ?? _route!.points.first,
                      ),
                      color: AppColors.reliefGreenMedium,
                      strokeWidth: 4,
                    ),
                  ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          playback != null
              ? playback.pausedAt != null && playback.enabled
                    ? 'Journey paused · ${playback.remainingKmAt(DateTime.now()).toStringAsFixed(2)} km remaining'
                    : '${playback.remainingKmAt(DateTime.now()).toStringAsFixed(2)} km remaining · ${(playback.remainingSecondsAt(DateTime.now()) / 60).ceil()} min estimated arrival · ${playback.speedFactor.toInt()}× (not live traffic)'
              : _route == null
              ? 'Finding an available ambulance. Your request stays queued if all units are busy.'
              : !_route!.isRealRoadRoute
              ? 'Road route unavailable. Open navigation for directions.'
              : 'Approx. ${_route!.distanceKm.toStringAsFixed(1)} km • ${_route!.etaMinutes} min from last route update; not live traffic.',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
