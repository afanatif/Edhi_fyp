import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/interactive_map_widget.dart';
import '../../../services/firestore_service.dart';
import '../../../services/location_service.dart';
import '../../../core/widgets/simulated_fleet_dialog.dart';
import '../../../services/route_service.dart';
import '../../../models/emergency_request.dart';
import '../../../models/employee.dart';

class AdminDispatchMapView extends StatefulWidget {
  const AdminDispatchMapView({super.key});

  @override
  State<AdminDispatchMapView> createState() => _AdminDispatchMapViewState();
}

class _AdminDispatchMapViewState extends State<AdminDispatchMapView> {
  EmergencyRequest? _selectedRequest;
  Employee? _selectedAmbulance;
  String _activeFilter =
      'all'; // 'all', 'available', 'dispatched', 'emergencies'
  LatLng _mapCenter = LocationService.defaultLocation;
  double _mapZoom = 13.5;
  bool _showQuickList = false;
  bool _demoBusy = false;
  FirestoreService? _service;
  late Stream<List<Employee>> _employeesStream;
  late Stream<List<EmergencyRequest>> _requestsStream;
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<FirestoreService>();
    if (_service != service) {
      _service = service;
      _employeesStream = service.getEmployeesStream();
      _requestsStream = service.getRequestsStream();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _runDemo(
    Employee driver,
    EmergencyRequest request, {
    double? speed,
  }) async {
    if (_demoBusy) return;
    final service = context.read<FirestoreService>();
    setState(() => _demoBusy = true);
    try {
      if (speed != null) {
        await service.setTransitSpeed(driver.employeeId, speed);
      } else if (service.getTransitPlayback(driver.employeeId)?.enabled ==
          true) {
        await service.pauseOrResumeTransit(driver.employeeId);
      } else {
        await service.startAutomaticRoadTransit(
          employeeId: driver.employeeId,
          requestId: request.requestId,
          destination: LatLng(
            request.location.latitude,
            request.location.longitude,
          ),
          callerRole: AppRoles.admin,
          speedFactor: service.simulationSpeed,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update the road journey. Check your connection and retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _demoBusy = false);
    }
  }

  final Map<String, List<LatLng>> _roadPolylines = {};
  final Set<String> _pendingRouteKeys = {};
  final Map<String, LatLng> _routeOrigins = {};
  final Map<String, DateTime> _routeFetchedAt = {};

  void _fetchRoadRouteIfNeeded(String key, LatLng start, LatLng dest) {
    if (_pendingRouteKeys.contains(key)) return;
    final age = DateTime.now().difference(
      _routeFetchedAt[key] ?? DateTime(2000),
    );
    if (age.inSeconds < 15) return;
    if ((_roadPolylines[key]?.isNotEmpty ?? false) &&
        _routeOrigins[key] != null &&
        const Distance().as(LengthUnit.Meter, _routeOrigins[key]!, start) <
            150) {
      return;
    }
    _pendingRouteKeys.add(key);
    _routeFetchedAt[key] = DateTime.now();
    RouteService.getRoadRoute(start, dest)
        .then((result) {
          if (mounted) {
            setState(() {
              _roadPolylines[key] = result.isRealRoadRoute ? result.points : [];
              _routeOrigins[key] = start;
              _pendingRouteKeys.remove(key);
            });
          }
        })
        .catchError((_) {
          _pendingRouteKeys.remove(key);
        });
  }

  void _showIncidentDetails(EmergencyRequest req) {
    final reqLat = req.location.latitude != 0.0
        ? req.location.latitude
        : LocationService.defaultLocation.latitude;
    final reqLng = req.location.longitude != 0.0
        ? req.location.longitude
        : LocationService.defaultLocation.longitude;
    setState(() {
      _selectedRequest = req;
      _selectedAmbulance = null;
      _showQuickList = false;
      _mapCenter = LatLng(reqLat, reqLng);
      _mapZoom = 15.5;
    });
  }

  void _showAmbulanceDetails(Employee driver) {
    setState(() {
      _selectedAmbulance = driver;
      _selectedRequest = null;
      _showQuickList = false;
      _mapCenter = LatLng(driver.currentLat, driver.currentLng);
      _mapZoom = 15.5;
    });
  }

  void _assignDriverToIncident(EmergencyRequest req) {
    final firestore = context.read<FirestoreService>();
    final drivers = firestore.getAvailableDrivers();
    final reqLat = req.location.latitude != 0.0
        ? req.location.latitude
        : LocationService.defaultLocation.latitude;
    final reqLng = req.location.longitude != 0.0
        ? req.location.longitude
        : LocationService.defaultLocation.longitude;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.reliefGreenMedium.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.airport_shuttle_rounded,
                color: AppColors.reliefGreenMedium,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Manual Dispatch: #${req.requestId}',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Emergency: ${req.emergencyType} • ${req.location.address}',
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Select Active Unit from Fleet:',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 8),
              if (drivers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.amber,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No available units right now. All ambulances are busy or en-route.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.brown,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: drivers.length,
                    separatorBuilder: (_, _) => const Divider(height: 8),
                    itemBuilder: (_, idx) {
                      final driver = drivers[idx];
                      final dist = LocationService.calculateDistanceInKm(
                        driver.currentLat,
                        driver.currentLng,
                        reqLat,
                        reqLng,
                      );
                      final eta = LocationService.calculateEtaMinutes(
                        dist,
                        averageSpeedKmH: 45,
                      );

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: AppColors.reliefGreenSoft,
                          child: Text(
                            driver.vehicleNumber.split('-').last,
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              color: AppColors.reliefGreenMedium,
                            ),
                          ),
                        ),
                        title: Text(
                          '${driver.name} (${driver.vehicleNumber})',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          '${driver.vehicleModel} • $dist km away • ~${eta}m ETA',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.reliefGreenMedium,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            minimumSize: const Size(70, 32),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () async {
                            try {
                              await firestore.assignRequest(
                                requestId: req.requestId,
                                employeeId: driver.employeeId,
                                employeeName:
                                    '${driver.name} (${driver.vehicleNumber})',
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                setState(() => _selectedRequest = null);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Unit ${driver.vehicleNumber} dispatched to #${req.requestId}!',
                                    ),
                                    backgroundColor:
                                        AppColors.reliefGreenMedium,
                                  ),
                                );
                              }
                            } catch (error) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      error.toString().replaceFirst(
                                        'Bad state: ',
                                        '',
                                      ),
                                    ),
                                    backgroundColor: AppColors.emergencyRed,
                                  ),
                                );
                              }
                            }
                          },
                          child: Text(
                            'Dispatch',
                            style: GoogleFonts.outfit(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  void _quickAutoDispatch(EmergencyRequest req) async {
    final firestore = context.read<FirestoreService>();
    final result = await firestore.autoDispatchNearestAmbulance(req.requestId);

    if (mounted) {
      if (result != null) {
        setState(() => _selectedRequest = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(
                  Icons.flash_on_rounded,
                  color: Colors.amber,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Auto-dispatched ${result.employee.vehicleNumber} (${result.employee.name}) • ${result.distanceKm} km away • ~${result.etaMinutes} mins ETA!',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.reliefGreenMedium,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      } else {
        final requiresVerification =
            req.fraudRiskLevel == 'High' && !req.isVerified;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              requiresVerification
                  ? 'Verify this high-risk request before dispatching a unit.'
                  : 'No available ambulance right now. Review the fleet or keep the incident queued.',
            ),
            backgroundColor: AppColors.emergencyRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAssignAmbulanceToRequestDialog(
    Employee driver,
    List<EmergencyRequest> pendingRequests,
  ) {
    final firestore = context.read<FirestoreService>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.reliefGreenMedium.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.airport_shuttle_rounded,
                color: AppColors.reliefGreenMedium,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Dispatch ${driver.vehicleNumber} (${driver.name})',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Pending Emergency Incident:',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: pendingRequests.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, idx) {
                    final req = pendingRequests[idx];
                    final reqLat = req.location.latitude != 0.0
                        ? req.location.latitude
                        : LocationService.defaultLocation.latitude;
                    final reqLng = req.location.longitude != 0.0
                        ? req.location.longitude
                        : LocationService.defaultLocation.longitude;
                    final dist = LocationService.calculateDistanceInKm(
                      driver.currentLat,
                      driver.currentLng,
                      reqLat,
                      reqLng,
                    );
                    final eta = LocationService.calculateEtaMinutes(
                      dist,
                      averageSpeedKmH: 45,
                    );

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.emergencyRed.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.warning_amber_rounded,
                              color: AppColors.emergencyRed,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '#${req.requestId}',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    StatusBadge(status: req.status),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${req.emergencyType} • ${req.location.address}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '$dist km away • Estimated ETA: ~$eta mins',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.reliefGreenMedium,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed:
                                req.fraudRiskLevel == 'High' && !req.isVerified
                                ? null
                                : () async {
                                    try {
                                      await firestore.assignRequest(
                                        requestId: req.requestId,
                                        employeeId: driver.employeeId,
                                        employeeName:
                                            '${driver.name} (${driver.vehicleNumber})',
                                      );
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (mounted) {
                                        setState(
                                          () => _selectedAmbulance = null,
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Unit ${driver.vehicleNumber} dispatched to #${req.requestId}!',
                                            ),
                                            backgroundColor:
                                                AppColors.reliefGreenMedium,
                                          ),
                                        );
                                      }
                                    } catch (error) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              error.toString().replaceFirst(
                                                'Bad state: ',
                                                '',
                                              ),
                                            ),
                                            backgroundColor:
                                                AppColors.emergencyRed,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            child: Text(
                              req.fraudRiskLevel == 'High' && !req.isVerified
                                  ? 'Review'
                                  : 'Dispatch',
                              style: GoogleFonts.outfit(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddAmbulanceDialog(BuildContext parentContext) async {
    final added = await showSimulatedFleetDialog(
      parentContext,
      stagingPoint: _mapCenter,
    );
    if (!mounted || added == null || added.isEmpty) return;
    setState(() {
      _mapCenter = LatLng(added.first.currentLat, added.first.currentLng);
      _mapZoom = 14;
      _selectedAmbulance = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.watch<FirestoreService>();

    return StreamBuilder<List<Employee>>(
      stream: _employeesStream,
      builder: (context, empSnapshot) {
        final employees = empSnapshot.data ?? firestore.getAllEmployees();
        if (_selectedAmbulance != null) {
          _selectedAmbulance = employees
              .where((e) => e.employeeId == _selectedAmbulance!.employeeId)
              .firstOrNull;
        }
        final drivers = employees.where((e) => e.role == 'driver').toList();

        return StreamBuilder<List<EmergencyRequest>>(
          stream: _requestsStream,
          builder: (context, reqSnapshot) {
            final requests = reqSnapshot.data ?? [];
            if (_selectedRequest != null) {
              _selectedRequest = requests
                  .where((r) => r.requestId == _selectedRequest!.requestId)
                  .firstOrNull;
            }
            final activeRequests = requests
                .where(
                  (r) =>
                      r.status != EmergencyStatus.completed &&
                      r.status != EmergencyStatus.cancelled,
                )
                .toList();
            final centers = firestore.getEdhiCenters();

            final markers = <Marker>[];
            final polylines = <Polyline>[];
            final polylineMarkerKeys = <Polyline, Key>{};

            // 1. Edhi Center Markers
            for (final c in centers.where((c) => c.hasCoordinates)) {
              markers.add(
                MapMarkerBuilder.edhiCenterPin(
                  LatLng(c.latitude!, c.longitude!),
                  name: c.name,
                ),
              );
            }

            final incidentUnit = drivers
                .where(
                  (e) => e.employeeId == _selectedRequest?.assignedEmployeeId,
                )
                .firstOrNull;
            final incidentUnitJob = incidentUnit == null
                ? null
                : firestore.getCurrentAssignment(incidentUnit, activeRequests);
            // A historical incident must not highlight another patient's unit.
            final selectedUnitId =
                _selectedAmbulance?.employeeId ??
                (incidentUnitJob?.requestId == _selectedRequest?.requestId
                    ? incidentUnit?.employeeId
                    : null);
            final selectedIncidentId =
                _selectedRequest?.requestId ??
                (_selectedAmbulance == null
                    ? null
                    : firestore
                          .getCurrentAssignment(
                            _selectedAmbulance!,
                            activeRequests,
                          )
                          ?.requestId);
            final highlightedMarkers = <Marker>[];
            final highlightedPolylines = <Polyline>[];

            // 2. Ambulance markers and their current assignment only.
            for (final driver in drivers.where((e) => e.hasValidLocation)) {
              final assignedReq = firestore.getCurrentAssignment(
                driver,
                activeRequests,
              );
              final isAssigned = assignedReq != null;
              final isSelected = driver.employeeId == selectedUnitId;
              final isFiltered =
                  !isSelected &&
                  (_activeFilter == 'emergencies' ||
                      (_activeFilter == 'available' &&
                          driver.status != 'available') ||
                      (_activeFilter == 'dispatched' && !isAssigned));

              if (!isFiltered) {
                (isSelected ? highlightedMarkers : markers).add(
                  MapMarkerBuilder.liveAmbulancePin(
                    LatLng(driver.currentLat, driver.currentLng),
                    vehicleNumber: driver.vehicleNumber.split('-').last,
                    status: driver.status,
                    isAssigned: isAssigned,
                    isSelected: isSelected,
                    key: ValueKey('ambulance_${driver.employeeId}'),
                    onTap: () => _showAmbulanceDetails(driver),
                  ),
                );
              }

              // Route Polyline if assigned
              if (!isFiltered && assignedReq != null) {
                if (!assignedReq.location.hasValidCoordinates) continue;
                final reqLat = assignedReq.location.latitude != 0.0
                    ? assignedReq.location.latitude
                    : LocationService.defaultLocation.latitude;
                final reqLng = assignedReq.location.longitude != 0.0
                    ? assignedReq.location.longitude
                    : LocationService.defaultLocation.longitude;

                final startPoint = LatLng(driver.currentLat, driver.currentLng);
                final destPoint = LatLng(reqLat, reqLng);
                final routeKey =
                    '${driver.employeeId}_${assignedReq.requestId}_'
                    '${destPoint.latitude.toStringAsFixed(4)},${destPoint.longitude.toStringAsFixed(4)}';

                final playback = firestore.getTransitPlayback(
                  driver.employeeId,
                );
                final matchesJourney =
                    playback?.requestId == assignedReq.requestId;
                if (!matchesJourney) {
                  _fetchRoadRouteIfNeeded(routeKey, startPoint, destPoint);
                }

                final remainingPoints = !matchesJourney
                    ? null
                    : firestore.getRemainingTransitRoute(driver.employeeId);
                List<LatLng> routePoints;
                if (remainingPoints != null && remainingPoints.isNotEmpty) {
                  routePoints = LocationService.trimRouteAhead(
                    remainingPoints,
                    startPoint,
                  );
                } else if (_roadPolylines.containsKey(routeKey) &&
                    _roadPolylines[routeKey]!.isNotEmpty) {
                  routePoints = LocationService.trimRouteAhead(
                    _roadPolylines[routeKey]!,
                    startPoint,
                  );
                } else {
                  routePoints = []; // No invented road geometry.
                }

                // Road Polyline Casing / Border for street network contrast
                final routeColor = isSelected
                    ? MapMarkerBuilder.selectedColor
                    : const Color(0xFF2563EB);
                final routeOpacity =
                    (selectedUnitId != null || selectedIncidentId != null) &&
                        !isSelected
                    ? 0.35
                    : 1.0;
                final targetPolylines = isSelected
                    ? highlightedPolylines
                    : polylines;
                final casing = Polyline(
                  points: routePoints,
                  strokeWidth: isSelected ? 10 : 6.5,
                  color: isSelected
                      ? Colors.white
                      : const Color(
                          0xFF1E40AF,
                        ).withValues(alpha: 0.35 * routeOpacity),
                );
                targetPolylines.add(casing);
                polylineMarkerKeys[casing] = ValueKey(
                  'ambulance_${driver.employeeId}',
                );

                // High-visibility Road Navigation Route
                final roadLine = Polyline(
                  points: routePoints,
                  strokeWidth: isSelected ? 6 : 4.5,
                  color: routeColor.withValues(alpha: routeOpacity),
                );
                targetPolylines.add(roadLine);
                polylineMarkerKeys[roadLine] = ValueKey(
                  'ambulance_${driver.employeeId}',
                );
              }
            }

            // 3. Active Emergency Markers
            if (_activeFilter != 'available' || selectedIncidentId != null) {
              for (final req in activeRequests.where(
                (r) =>
                    r.location.hasValidCoordinates &&
                    (_activeFilter != 'available' ||
                        r.requestId == selectedIncidentId),
              )) {
                final lat = req.location.latitude != 0.0
                    ? req.location.latitude
                    : LocationService.defaultLocation.latitude;
                final lng = req.location.longitude != 0.0
                    ? req.location.longitude
                    : LocationService.defaultLocation.longitude;

                final isPending = req.status == EmergencyStatus.pending;
                final isSelected = req.requestId == selectedIncidentId;
                final markerColor = isSelected
                    ? MapMarkerBuilder.selectedColor
                    : isPending
                    ? AppColors.emergencyRed
                    : const Color(0xFF2563EB);

                (isSelected ? highlightedMarkers : markers).add(
                  Marker(
                    key: ValueKey('incident_${req.requestId}'),
                    point: LatLng(lat, lng),
                    width: isSelected ? 105 : 85,
                    height: isSelected ? 94 : 80,
                    child: Semantics(
                      label: 'Incident ${req.requestId}',
                      selected: isSelected,
                      button: true,
                      child: GestureDetector(
                        onTap: () => _showIncidentDetails(req),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: EdgeInsets.all(isSelected ? 11 : 7),
                                decoration: BoxDecoration(
                                  color: markerColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: isSelected ? 4 : 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: markerColor.withValues(
                                        alpha: 0.45,
                                      ),
                                      blurRadius: 10,
                                      spreadRadius: isSelected ? 7 : 3,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isPending
                                      ? Icons.emergency_rounded
                                      : Icons.local_hospital_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: markerColor.withValues(
                                      alpha: isSelected ? 0.9 : 0.3,
                                    ),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black12,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '${isSelected ? '✓ ' : ''}${req.emergencyType.split(' ').first}',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: markerColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
            }
            // Paint the focused pair and route last, above the rest of the fleet.
            markers.addAll(highlightedMarkers);
            polylines.addAll(highlightedPolylines);

            return Stack(
              children: [
                InteractiveMapWidget(
                  center: _mapCenter,
                  zoom: _mapZoom,
                  markers: markers,
                  polylines: polylines,
                  polylineMarkerKeys: polylineMarkerKeys,
                  // Keep the selected pin above the bottom detail sheet.
                  focusOffset:
                      _selectedAmbulance != null || _selectedRequest != null
                      ? const Offset(0, -145)
                      : Offset.zero,
                  height: 560,
                ),

                // Top Control & Filter Header Pill
                Positioned(
                  top: 14,
                  left: 14,
                  right: 14,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: AppColors.border),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1A000000),
                            blurRadius: 12,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButton<double>(
                            value: firestore.simulationSpeed,
                            underline: const SizedBox.shrink(),
                            items: [1.0, 3.0, 10.0]
                                .map(
                                  (speed) => DropdownMenuItem(
                                    value: speed,
                                    child: Text(
                                      'New trips: ${speed.toInt()}×',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (speed) {
                              if (speed != null) {
                                firestore.setDefaultSimulationSpeed(speed);
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          _buildFilterChip(
                            'all',
                            'All Fleet (${drivers.length})',
                            Icons.dashboard_rounded,
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            'available',
                            'Available (${drivers.where((d) => d.status == 'available').length})',
                            Icons.check_circle_rounded,
                            activeColor: AppColors.reliefGreenMedium,
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            'dispatched',
                            'Assigned (${drivers.where((d) => d.status == 'busy').length})',
                            Icons.navigation_rounded,
                            activeColor: const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 6),
                          _buildFilterChip(
                            'emergencies',
                            'Incidents (${activeRequests.length})',
                            Icons.warning_amber_rounded,
                            activeColor: AppColors.emergencyRed,
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () => _showAddAmbulanceDialog(context),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.reliefGreenMedium,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.add_circle_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    '+ Add Unit',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Quick Fly-To Selector Popup below top header
                if (_showQuickList) _buildQuickPopup(activeRequests, drivers),

                // Selected Ambulance Floating Telemetry Card
                if (_selectedAmbulance != null)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: _buildAmbulanceDetailsCard(
                      _selectedAmbulance!,
                      activeRequests,
                    ),
                  ),

                // Selected Incident Floating Card
                if (_selectedRequest != null)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: _buildIncidentDetailsCard(
                      _selectedRequest!,
                      firestore,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(
    String key,
    String label,
    IconData icon, {
    Color? activeColor,
  }) {
    final isSelected = _activeFilter == key;
    final color = activeColor ?? AppColors.textPrimary;

    return InkWell(
      onTap: () {
        setState(() {
          if (_activeFilter == key) {
            _showQuickList = !_showQuickList;
          } else {
            _activeFilter = key;
            _showQuickList = true;
          }
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? color : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? color : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              isSelected && _showQuickList
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: isSelected
                  ? color
                  : AppColors.textSecondary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickPopup(
    List<EmergencyRequest> activeRequests,
    List<Employee> drivers,
  ) {
    final bool isEmergencies = _activeFilter == 'emergencies';
    final bool isAvailable = _activeFilter == 'available';
    final bool isDispatched = _activeFilter == 'dispatched';

    final List<Employee> filteredDrivers = isAvailable
        ? drivers.where((d) => d.status == 'available').toList()
        : (isDispatched
              ? drivers.where((d) => d.status != 'available').toList()
              : drivers);

    final title = isEmergencies
        ? 'Active Emergency Incidents (${activeRequests.length})'
        : (isAvailable
              ? 'Available Units on Standby (${filteredDrivers.length})'
              : (isDispatched
                    ? 'En Route Emergency Units (${filteredDrivers.length})'
                    : 'All Deployed Fleet Units (${filteredDrivers.length})'));

    final icon = isEmergencies
        ? Icons.warning_amber_rounded
        : (isAvailable
              ? Icons.check_circle_rounded
              : (isDispatched
                    ? Icons.navigation_rounded
                    : Icons.airport_shuttle_rounded));

    final themeColor = isEmergencies
        ? AppColors.emergencyRed
        : (isAvailable
              ? AppColors.reliefGreenMedium
              : (isDispatched
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF0F172A)));

    return Positioned(
      top: 66,
      left: 14,
      right: 14,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: themeColor.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2B000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: themeColor, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Tap any item below to fly map camera directly to it',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _mapCenter = LocationService.defaultLocation;
                      _mapZoom = 13.5;
                      _selectedRequest = null;
                      _selectedAmbulance = null;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.crop_free_rounded,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Overview',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => setState(() => _showQuickList = false),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (isEmergencies)
              _buildIncidentsCarousel(activeRequests)
            else
              _buildDriversCarousel(filteredDrivers, activeRequests),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentsCarousel(List<EmergencyRequest> requests) {
    if (requests.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.check_circle_outline_rounded,
              color: AppColors.reliefGreenMedium,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              'No active emergency calls right now. All clear!',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 98,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: requests.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, idx) {
          final req = requests[idx];
          final isSelected = _selectedRequest?.requestId == req.requestId;
          final isPending = req.status == EmergencyStatus.pending;
          final isCritical =
              req.priority.toLowerCase().contains('critical') ||
              req.priority == 'P1';

          return InkWell(
            onTap: () => _showIncidentDetails(req),
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 290,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF5F3FF) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? MapMarkerBuilder.selectedColor
                      : (isCritical
                            ? AppColors.emergencyRed.withValues(alpha: 0.4)
                            : AppColors.border),
                  width: isSelected ? 2.0 : 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (isSelected
                                ? MapMarkerBuilder.selectedColor
                                : Colors.black)
                            .withValues(alpha: isSelected ? 0.15 : 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isPending
                              ? AppColors.emergencyRed
                              : const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#${req.requestId}',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: isCritical
                              ? AppColors.emergencyRed.withValues(alpha: 0.12)
                              : Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          req.priority.toUpperCase(),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: isCritical
                                ? AppColors.emergencyRed
                                : Colors.amber.shade900,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (req.fraudRiskLevel == 'High') ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade100,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '⚠️ SUSPECTED FAKE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.red.shade900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      StatusBadge(status: req.status),
                    ],
                  ),
                  Text(
                    '${req.emergencyType} • ${req.location.address}',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.my_location_rounded,
                        size: 12,
                        color: AppColors.emergencyRed,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isSelected
                            ? 'Active Target (Centered)'
                            : 'Tap to Fly to Incident 📍',
                        style: GoogleFonts.outfit(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: isSelected
                              ? AppColors.emergencyRed
                              : const Color(0xFF2563EB),
                        ),
                      ),
                      const Spacer(),
                      if (req.assignedEmployeeName != null)
                        Text(
                          'Unit: ${req.assignedEmployeeName!.split(" ").first}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppColors.reliefGreenMedium,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDriversCarousel(
    List<Employee> drivers,
    List<EmergencyRequest> activeRequests,
  ) {
    if (drivers.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'No ambulance units match the active filter.',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return SizedBox(
      height: 98,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: drivers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, idx) {
          final driver = drivers[idx];
          final isSelected =
              _selectedAmbulance?.employeeId == driver.employeeId;
          final isAvailable = driver.status == 'available';
          final assignedReq = context
              .read<FirestoreService>()
              .getCurrentAssignment(driver, activeRequests);

          return InkWell(
            onTap: () => _showAmbulanceDetails(driver),
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 280,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFF5F3FF) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? MapMarkerBuilder.selectedColor
                      : (isAvailable
                            ? AppColors.reliefGreenMedium.withValues(
                                alpha: 0.35,
                              )
                            : AppColors.border),
                  width: isSelected ? 2.0 : 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (isSelected
                                ? MapMarkerBuilder.selectedColor
                                : Colors.black)
                            .withValues(alpha: isSelected ? 0.15 : 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isAvailable
                              ? AppColors.reliefGreenMedium
                              : const Color(0xFF2563EB),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          driver.vehicleNumber.split('-').last,
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          driver.name,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (isAvailable
                                      ? AppColors.reliefGreenMedium
                                      : const Color(0xFF2563EB))
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isAvailable ? 'AVAILABLE' : 'EN ROUTE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: isAvailable
                                ? AppColors.reliefGreenMedium
                                : const Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    assignedReq != null
                        ? 'Mission: #${assignedReq.requestId} (${assignedReq.emergencyType})'
                        : 'Standby Base • Fuel: ${driver.batteryFuel}%',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.near_me_rounded,
                        size: 12,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isSelected
                            ? 'Active Target (Centered)'
                            : 'Tap to Fly to Unit 📍',
                        style: GoogleFonts.outfit(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: isSelected
                              ? const Color(0xFF2563EB)
                              : AppColors.reliefGreenMedium,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${driver.speedKmh} km/h',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAmbulanceDetailsCard(
    Employee driver,
    List<EmergencyRequest> activeRequests,
  ) {
    final firestore = context.watch<FirestoreService>();
    final isAvailable = driver.status == 'available';
    final assignedReq = firestore.getCurrentAssignment(driver, activeRequests);
    final isTransitOn =
        assignedReq != null && firestore.isTransitActive(driver.employeeId);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.45,
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: MapMarkerBuilder.selectedColor, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          (isAvailable
                                  ? AppColors.reliefGreenMedium
                                  : const Color(0xFF2563EB))
                              .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.airport_shuttle_rounded,
                      color: isAvailable
                          ? AppColors.reliefGreenMedium
                          : const Color(0xFF2563EB),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              driver.vehicleNumber,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isAvailable
                                    ? AppColors.reliefGreenSoft
                                    : const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                isAvailable
                                    ? 'AVAILABLE'
                                    : assignedReq?.status ==
                                          EmergencyStatus.arrived
                                    ? 'ARRIVED'
                                    : 'DISPATCHED',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10,
                                  color: isAvailable
                                      ? AppColors.reliefGreenMedium
                                      : const Color(0xFF1D4ED8),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${driver.vehicleModel} • Driver: ${driver.name}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => setState(() => _selectedAmbulance = null),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Telemetry Row
              Row(
                children: [
                  _buildTelemetryStat(
                    Icons.speed_rounded,
                    'Speed',
                    '${driver.speedKmh} km/h',
                  ),
                  const SizedBox(width: 14),
                  _buildTelemetryStat(
                    Icons.battery_charging_full_rounded,
                    'Fuel',
                    driver.batteryFuel < 0
                        ? 'Not reported'
                        : '${driver.batteryFuel}%',
                  ),
                  const SizedBox(width: 14),
                  _buildTelemetryStat(
                    Icons.phone_rounded,
                    'Contact',
                    driver.phone,
                  ),
                ],
              ),
              Text(
                firestore.simulationSyncError ??
                    'Road-route estimate • not device GPS',
                style: const TextStyle(fontSize: 12),
              ),
              if (driver.status != 'busy')
                TextButton.icon(
                  onPressed: () => showLinkDriverDialog(context, driver),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Link registered driver'),
                ),
              if (assignedReq != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isTransitOn
                        ? AppColors.reliefGreenSoft
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isTransitOn
                          ? AppColors.reliefGreenMedium.withValues(alpha: 0.3)
                          : const Color(0xFFBFDBFE),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isTransitOn
                            ? Icons.directions_car_filled_rounded
                            : Icons.emergency_rounded,
                        size: 16,
                        color: isTransitOn
                            ? AppColors.reliefGreenMedium
                            : const Color(0xFF1D4ED8),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isTransitOn
                              ? 'Road journey ${firestore.getTransitSpeed(driver.employeeId).toInt()}×'
                              : 'Active Mission: #${assignedReq.requestId} (${assignedReq.emergencyType})',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: isTransitOn
                                ? AppColors.reliefGreenMedium
                                : const Color(0xFF1E3A8A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _showIncidentDetails(assignedReq),
                        child: Text(
                          'Inspect',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (firestore.getTransitPlayback(driver.employeeId)
                    case final playback?)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      firestore.isTransitPaused(driver.employeeId)
                          ? 'Journey paused · ${playback.remainingKmAt(DateTime.now()).toStringAsFixed(2)} km remaining'
                          : '${playback.remainingKmAt(DateTime.now()).toStringAsFixed(2)} km remaining · ${(playback.remainingSecondsAt(DateTime.now()) / 60).ceil()} min estimated arrival · ${playback.speedFactor.toInt()}×',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (assignedReq.status == EmergencyStatus.arrived)
                  const Text(
                    'Arrived • waiting for citizen or driver to confirm completion.',
                    style: TextStyle(fontSize: 12),
                  ),
                if (firestore.simulationError(driver.employeeId) != null)
                  Text(
                    firestore.simulationError(driver.employeeId)!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                if (assignedReq.status == EmergencyStatus.arrived)
                  FilledButton.icon(
                    onPressed: _demoBusy
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Complete response?'),
                                content: const Text(
                                  'Confirm assistance is finished. The ambulance will be released and made available for another request.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Back'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Complete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true || !mounted) return;
                            setState(() => _demoBusy = true);
                            try {
                              await firestore.updateRequestStatus(
                                assignedReq.requestId,
                                EmergencyStatus.completed,
                              );
                            } catch (error) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('$error')),
                                );
                              }
                            } finally {
                              if (mounted) setState(() => _demoBusy = false);
                            }
                          },
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Complete response'),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilledButton.icon(
                        onPressed: _demoBusy
                            ? null
                            : () => _runDemo(driver, assignedReq),
                        icon: Icon(
                          firestore.isTransitActive(driver.employeeId)
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                        label: Text(
                          _demoBusy
                              ? 'Updating…'
                              : firestore.isTransitPaused(driver.employeeId)
                              ? 'Resume journey'
                              : firestore.isTransitActive(driver.employeeId)
                              ? 'Pause journey'
                              : 'Retry road route',
                        ),
                      ),
                      if (firestore
                              .getTransitPlayback(driver.employeeId)
                              ?.enabled ==
                          true)
                        ...[1.0, 3.0, 10.0].map(
                          (speed) => ChoiceChip(
                            label: Text('${speed.toInt()}×'),
                            selected:
                                firestore.getTransitSpeed(driver.employeeId) ==
                                speed,
                            onSelected: _demoBusy
                                ? null
                                : (_) => _runDemo(
                                    driver,
                                    assignedReq,
                                    speed: speed,
                                  ),
                          ),
                        ),
                    ],
                  ),
              ] else if (isAvailable) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.reliefGreenMedium,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 15),
                  label: Text(
                    'Dispatch to Emergency Call',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () {
                    final pendingRequests = activeRequests
                        .where((r) => r.status == EmergencyStatus.pending)
                        .toList();
                    if (pendingRequests.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No pending emergency calls waiting for dispatch right now.',
                          ),
                          backgroundColor: AppColors.reliefGreenMedium,
                        ),
                      );
                      return;
                    }
                    _showAssignAmbulanceToRequestDialog(
                      driver,
                      pendingRequests,
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTelemetryStat(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentDetailsCard(
    EmergencyRequest req,
    FirestoreService firestore,
  ) {
    final isPending = req.status == EmergencyStatus.pending;
    final nearest = firestore.findNearestAvailableAmbulance(
      req.location.latitude != 0.0
          ? req.location.latitude
          : LocationService.defaultLocation.latitude,
      req.location.longitude != 0.0
          ? req.location.longitude
          : LocationService.defaultLocation.longitude,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MapMarkerBuilder.selectedColor, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:
                      (isPending
                              ? AppColors.emergencyRed
                              : const Color(0xFF2563EB))
                          .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPending
                      ? Icons.warning_rounded
                      : Icons.local_hospital_rounded,
                  color: isPending
                      ? AppColors.emergencyRed
                      : const Color(0xFF2563EB),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          '#${req.requestId} • ${req.emergencyType}',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        StatusBadge(status: req.status),
                        if (req.fraudRiskLevel == 'High')
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.shade300),
                            ),
                            child: Text(
                              '🚨 HIGH FRAUD RISK',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.red.shade900,
                              ),
                            ),
                          )
                        else if (req.isVerified || req.fraudRiskLevel == 'Low')
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.green.shade300),
                            ),
                            child: Text(
                              '🛡️ VERIFIED',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      req.location.address,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => setState(() => _selectedRequest = null),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            req.description,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: AppColors.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (req.fraudRiskLevel == 'High') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.shield_rounded,
                        color: Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Suspected Fake / Prank Incident (${(req.fraudRiskScore * 100).toInt()}% Risk)',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (req.fraudReason != null &&
                      req.fraudReason!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'AI Triage Flags: ${req.fraudReason}',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: Colors.red.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (req.userPhone.isNotEmpty)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1D4ED8),
                            side: const BorderSide(color: Color(0xFF93C5FD)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.phone_rounded, size: 14),
                          label: Text(
                            'Call ${req.userPhone}',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Calling ${req.userName} (${req.userPhone}) for verification...',
                                ),
                              ),
                            );
                          },
                        ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.green.shade800,
                          side: BorderSide(color: Colors.green.shade500),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(
                          Icons.check_circle_outline_rounded,
                          size: 14,
                        ),
                        label: Text(
                          'Verify & Clear',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: () async {
                          await firestore.verifyEmergencyRequest(req.requestId);
                          setState(() {
                            _selectedRequest = req.copyWith(
                              isVerified: true,
                              fraudRiskLevel: 'Low',
                            );
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Emergency request marked as verified legitimate.',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          visualDensity: VisualDensity.compact,
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.cancel_outlined, size: 14),
                        label: Text(
                          'Reject Prank',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: () async {
                          await firestore.rejectFraudEmergencyRequest(
                            req.requestId,
                          );
                          setState(() {
                            _selectedRequest = null;
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Prank request rejected and archived.',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (req.fraudRiskLevel == 'Medium') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 15,
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Moderate Anomaly (${(req.fraudRiskScore * 100).toInt()}%): ${req.fraudReason ?? "Low detail"}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await firestore.verifyEmergencyRequest(req.requestId);
                      setState(() {
                        _selectedRequest = req.copyWith(
                          isVerified: true,
                          fraudRiskLevel: 'Low',
                        );
                      });
                    },
                    child: Text(
                      'Verify',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isPending) ...[
            Row(
              children: [
                if (nearest != null)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.reliefGreenMedium,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.flash_on_rounded, size: 18),
                      label: Text(
                        '⚡ Auto-Dispatch Nearest (${nearest.employee.vehicleNumber} • ${nearest.distanceKm} km)',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => _quickAutoDispatch(req),
                    ),
                  )
                else
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'No unit within standard radius.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.brown,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _assignDriverToIncident(req),
                  child: Text(
                    'Manual Pick',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.reliefGreenMedium,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Assigned to: ${req.assignedEmployeeName ?? "Fleet Unit"}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.reliefGreenMedium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
