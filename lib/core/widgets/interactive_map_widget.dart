import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_colors.dart';
import '../../services/location_service.dart';

class InteractiveMapWidget extends StatefulWidget {
  final LatLng center;
  final double zoom;
  final List<Marker> markers;
  final List<Polyline> polylines;

  /// Explicit route-to-unit links prevent nearby vehicles from stealing a
  /// route's animated origin on crowded operations maps.
  final Map<Polyline, Key> polylineMarkerKeys;
  final Offset focusOffset;
  final void Function(LatLng)? onTap;
  final bool showControls;
  final double? height;

  const InteractiveMapWidget({
    super.key,
    required this.center,
    this.zoom = 14.0,
    this.markers = const [],
    this.polylines = const [],
    this.polylineMarkerKeys = const {},
    this.focusOffset = Offset.zero,
    this.onTap,
    this.showControls = true,
    this.height,
  });

  @override
  State<InteractiveMapWidget> createState() => _InteractiveMapWidgetState();
}

class _InteractiveMapWidgetState extends State<InteractiveMapWidget>
    with TickerProviderStateMixin {
  late final MapController _mapController;

  // Active smooth marker interpolation tracks keyed by Marker.key
  final Map<Key, _MarkerTrack> _markerTracks = {};

  // Smooth camera panning
  AnimationController? _cameraAnimController;
  bool _userInteracted = false;
  bool _humanitarianTiles = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _syncMarkerTracks(widget.markers);
  }

  @override
  void didUpdateWidget(covariant InteractiveMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMarkerTracks(widget.markers);

    // Compute center delta in meters
    final distMeters = _calculateDistanceInMeters(
      oldWidget.center,
      widget.center,
    );

    // If target changed by more than 75m or zoom changed, this is an explicit camera refocus:
    // auto-recenter and reset _userInteracted so the camera always moves to the requested target!
    if (distMeters > 75.0 ||
        oldWidget.zoom != widget.zoom ||
        oldWidget.focusOffset != widget.focusOffset) {
      _userInteracted = false;
      _animatedMapMove(widget.center, widget.zoom);
    } else if (distMeters >= 25.0) {
      // Vehicle movement: follow only if user is not currently panning manually
      if (!_userInteracted) {
        _animatedMapMove(widget.center, widget.zoom);
      }
    }
  }

  double _calculateDistanceInMeters(LatLng a, LatLng b) {
    const double p = 0.017453292519943295;
    final double val =
        0.5 -
        math.cos((b.latitude - a.latitude) * p) / 2 +
        math.cos(a.latitude * p) *
            math.cos(b.latitude * p) *
            (1 - math.cos((b.longitude - a.longitude) * p)) /
            2;
    return 12742000 * math.asin(math.sqrt(val));
  }

  void _syncMarkerTracks(List<Marker> markers) {
    final activeKeys = <Key>{};

    for (final m in markers) {
      if (m.key != null) {
        activeKeys.add(m.key!);
        if (!_markerTracks.containsKey(m.key)) {
          _markerTracks[m.key!] = _MarkerTrack(
            from: m.point,
            to: m.point,
            vsync: this,
            onTick: () {
              if (mounted) setState(() {});
            },
          );
        } else {
          _markerTracks[m.key!]!.updateTarget(m.point);
        }
      }
    }

    // Clean up tracks for removed markers
    final removedKeys = _markerTracks.keys
        .where((k) => !activeKeys.contains(k))
        .toList();
    for (final k in removedKeys) {
      _markerTracks[k]?.dispose();
      _markerTracks.remove(k);
    }
  }

  void _animatedMapMove(
    LatLng destCenter,
    double destZoom, {
    bool applyFocusOffset = true,
  }) {
    _cameraAnimController?.dispose();
    final controller = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    );
    _cameraAnimController = controller;

    final startCenter = _mapController.camera.center;
    final startZoom = _mapController.camera.zoom;
    final curve = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );

    controller.addListener(() {
      final t = curve.value;
      final lat =
          startCenter.latitude +
          (destCenter.latitude - startCenter.latitude) * t;
      final lng =
          startCenter.longitude +
          (destCenter.longitude - startCenter.longitude) * t;
      final zoom = startZoom + (destZoom - startZoom) * t;
      _mapController.move(
        LatLng(lat, lng),
        zoom,
        offset: applyFocusOffset ? widget.focusOffset * t : Offset.zero,
      );
    });

    controller.forward();
  }

  void _fitOperationalArea() {
    final coordinates = <LatLng>[
      ...widget.markers.map((marker) => marker.point),
      ...widget.polylines.expand((line) => line.points),
    ];
    if (coordinates.isEmpty) {
      _animatedMapMove(widget.center, widget.zoom);
      return;
    }
    _userInteracted = false;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: coordinates,
        padding: const EdgeInsets.fromLTRB(42, 84, 42, 72),
        maxZoom: 16.5,
      ),
    );
  }

  @override
  void dispose() {
    _cameraAnimController?.dispose();
    for (final track in _markerTracks.values) {
      track.dispose();
    }
    _markerTracks.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Generate smoothly interpolated markers with bearing scope
    final renderedMarkers = widget.markers.map((marker) {
      if (marker.key != null && _markerTracks.containsKey(marker.key)) {
        final track = _markerTracks[marker.key]!;
        return Marker(
          key: marker.key,
          point: track.currentPoint,
          width: marker.width,
          height: marker.height,
          alignment: marker.alignment,
          child: MarkerBearingScope(
            bearing: track.currentBearing,
            child: marker.child,
          ),
        );
      }
      return marker;
    }).toList();

    // 2. Real-time 60 FPS polyline tethering: connect polyline start directly to live vehicle coordinate
    final renderedPolylines = widget.polylines.map((poly) {
      final markerKey = widget.polylineMarkerKeys[poly];
      if (markerKey != null) {
        final track = _markerTracks[markerKey];
        return track == null || poly.points.length < 2
            ? poly
            : Polyline(
                points: [track.currentPoint, ...poly.points.sublist(1)],
                strokeWidth: poly.strokeWidth,
                color: poly.color,
                borderStrokeWidth: poly.borderStrokeWidth,
                borderColor: poly.borderColor,
              );
      }
      if (poly.points.length >= 2 && _markerTracks.isNotEmpty) {
        final p0 = poly.points.first;
        for (final track in _markerTracks.values) {
          final cur = track.currentPoint;
          final dLat = (p0.latitude - cur.latitude).abs();
          final dLng = (p0.longitude - cur.longitude).abs();
          // Fast bounding-box check (< ~200m) before tethering
          if (dLat < 0.002 && dLng < 0.002) {
            return Polyline(
              points: [cur, ...poly.points.sublist(1)],
              strokeWidth: poly.strokeWidth,
              color: poly.color,
              borderStrokeWidth: poly.borderStrokeWidth,
              borderColor: poly.borderColor,
            );
          }
        }
      }
      return poly;
    }).toList();

    final mapWidget = Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: widget.zoom,
            minZoom: 3,
            maxZoom: 19,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onTap: widget.onTap != null
                ? (tapPosition, point) => widget.onTap!(point)
                : null,
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture) {
                _userInteracted = true;
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: _humanitarianTiles
                  ? 'https://tile-{s}.openstreetmap.fr/hot/{z}/{x}/{y}.png'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: _humanitarianTiles ? const ['a', 'b', 'c'] : const [],
              userAgentPackageName: 'com.example.edhiconnect_ai',
            ),
            if (renderedPolylines.isNotEmpty)
              RepaintBoundary(
                child: PolylineLayer(
                  polylines: renderedPolylines
                      .where((p) => p.points.length >= 2)
                      .toList(),
                ),
              ),
            if (renderedMarkers.isNotEmpty)
              RepaintBoundary(child: MarkerLayer(markers: renderedMarkers)),
          ],
        ),

        if (widget.showControls)
          Positioned(
            right: 12,
            top: 72,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMapButton(
                  icon: Icons.layers_rounded,
                  tooltip: _humanitarianTiles
                      ? 'Standard street map'
                      : 'Humanitarian response map',
                  onPressed: () {
                    setState(() => _humanitarianTiles = !_humanitarianTiles);
                  },
                ),
                const SizedBox(height: 6),
                _buildMapButton(
                  icon: Icons.fit_screen_rounded,
                  tooltip: 'Fit route and all units',
                  onPressed: _fitOperationalArea,
                ),
                const SizedBox(height: 6),
                _buildMapButton(
                  icon: Icons.add,
                  tooltip: 'Zoom in',
                  onPressed: () {
                    final newZoom = _mapController.camera.zoom + 1;
                    _animatedMapMove(
                      _mapController.camera.center,
                      newZoom,
                      applyFocusOffset: false,
                    );
                  },
                ),
                const SizedBox(height: 6),
                _buildMapButton(
                  icon: Icons.remove,
                  tooltip: 'Zoom out',
                  onPressed: () {
                    final newZoom = _mapController.camera.zoom - 1;
                    _animatedMapMove(
                      _mapController.camera.center,
                      newZoom,
                      applyFocusOffset: false,
                    );
                  },
                ),
                const SizedBox(height: 6),
                _buildMapButton(
                  icon: Icons.my_location,
                  tooltip: 'Follow selected location',
                  iconColor: AppColors.emergencyRed,
                  onPressed: () {
                    _userInteracted = false;
                    _animatedMapMove(widget.center, widget.zoom);
                  },
                ),
              ],
            ),
          ),
        Positioned(
          left: 8,
          bottom: 6,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _humanitarianTiles
                    ? '© OpenStreetMap • HOT'
                    : '© OpenStreetMap contributors',
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.height != null) {
      return SizedBox(
        height: widget.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: mapWidget,
        ),
      );
    }

    return mapWidget;
  }

  Widget _buildMapButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color? iconColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: Semantics(
              button: true,
              label: tooltip,
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Icon(
                  icon,
                  size: 20,
                  color: iconColor ?? AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Provides smooth interpolated heading/bearing to marker children
class MarkerBearingScope extends InheritedWidget {
  final double? bearing;

  const MarkerBearingScope({
    super.key,
    required this.bearing,
    required super.child,
  });

  static double? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MarkerBearingScope>()
        ?.bearing;
  }

  @override
  bool updateShouldNotify(MarkerBearingScope oldWidget) =>
      bearing != oldWidget.bearing;
}

/// Helper track for smooth 60 FPS dead-reckoning marker interpolation with adaptive cadence
class _MarkerTrack {
  LatLng from;
  LatLng to;
  double fromBearing = 0.0;
  double targetBearing = 0.0;
  DateTime? _lastTargetTime;
  late final AnimationController controller;
  late final CurvedAnimation animation;

  _MarkerTrack({
    required this.from,
    required this.to,
    required TickerProvider vsync,
    required VoidCallback onTick,
    Duration duration = const Duration(milliseconds: 1050),
  }) {
    fromBearing = 0.0;
    targetBearing = 0.0;
    controller = AnimationController(duration: duration, vsync: vsync);
    // Linear progression ensures uninterrupted forward momentum across sequential waypoints without stop-and-go stutter
    animation = CurvedAnimation(parent: controller, curve: Curves.linear);
    controller.addListener(onTick);
  }

  LatLng get currentPoint {
    final t = animation.value;
    final lat = from.latitude + (to.latitude - from.latitude) * t;
    final lng = from.longitude + (to.longitude - from.longitude) * t;
    return LatLng(lat, lng);
  }

  double? get currentBearing {
    if (from.latitude == to.latitude && from.longitude == to.longitude) {
      return null;
    }
    // Apply gentle easing to the angular turn so steering rotates naturally through curves
    final angleT = Curves.easeInOutSine.transform(animation.value);
    final diff = (targetBearing - fromBearing + 180) % 360 - 180;
    return (fromBearing + diff * angleT + 360) % 360;
  }

  void updateTarget(LatLng newTarget) {
    final latDiff = (to.latitude - newTarget.latitude).abs();
    final lngDiff = (to.longitude - newTarget.longitude).abs();

    // Ignore sub-millimeter noise
    if (latDiff < 0.000005 && lngDiff < 0.000005) return;

    // Drastic snap (e.g. city change or manual reset)
    if (latDiff > 0.04 || lngDiff > 0.04) {
      from = newTarget;
      to = newTarget;
      controller.stop();
      return;
    }

    final now = DateTime.now();
    final bool isFirstStep = (_lastTargetTime == null);
    if (!isFirstStep) {
      final deltaMs = now.difference(_lastTargetTime!).inMilliseconds;
      if (deltaMs > 300 && deltaMs < 4000) {
        // Adapt duration with a 1.05x safety buffer so motion continues smoothly
        // into the next target without stopping!
        final dynamicDuration = (deltaMs * 1.05).round().clamp(600, 2600);
        controller.duration = Duration(milliseconds: dynamicDuration);
      }
    }
    _lastTargetTime = now;

    // Calculate heading azimuth along shortest-arc
    final currentP = currentPoint;
    final newBearing = LocationService.calculateBearing(currentP, newTarget);
    from = currentP;
    to = newTarget;
    // On the first step, align directly with the movement direction to avoid an artificial 180° spin
    fromBearing = isFirstStep ? newBearing : (currentBearing ?? newBearing);
    targetBearing = newBearing;

    controller.forward(from: 0.0);
  }

  void dispose() {
    controller.dispose();
  }
}

/// Helper builders for standard EdhiConnect markers
class MapMarkerBuilder {
  static const selectedColor = Color(0xFF7C3AED);
  MapMarkerBuilder._();

  static Marker emergencyPin(LatLng point, {String label = 'Emergency'}) {
    return Marker(
      point: point,
      width: 80,
      height: 75,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 80,
          height: 75,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.emergencyRed,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.emergencyRed.withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.emergency,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4),
                  ],
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.emergencyRed,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Marker liveAmbulancePin(
    LatLng point, {
    required String vehicleNumber,
    required String status,
    VoidCallback? onTap,
    bool isAssigned = false,
    bool isSelected = false,
    Key? key,
  }) {
    final markerKey = key ?? ValueKey('live_amb_$vehicleNumber');

    return Marker(
      key: markerKey,
      point: point,
      width: isSelected ? 106 : 92,
      height: isSelected ? 94 : 82,
      child: _LiveAmbulancePinWidget(
        vehicleNumber: vehicleNumber,
        status: status,
        isAssigned: isAssigned,
        isSelected: isSelected,
        onTap: onTap,
      ),
    );
  }

  static Marker ambulancePin(LatLng point, {String vehicle = 'Ambulance'}) {
    return Marker(
      point: point,
      width: 80,
      height: 75,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 80,
          height: 75,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.reliefGreenMedium,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.reliefGreenMedium.withValues(alpha: 0.4),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.directions_car,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4),
                  ],
                ),
                child: Text(
                  vehicle,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.reliefGreenMedium,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Marker edhiCenterPin(LatLng point, {String name = 'Edhi Center'}) {
    return Marker(
      point: point,
      width: 90,
      height: 75,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: 90,
          height: 75,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7),
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 6),
                  ],
                ),
                child: const Icon(
                  Icons.local_hospital,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 4),
                  ],
                ),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveAmbulancePinWidget extends StatelessWidget {
  final String vehicleNumber;
  final String status;
  final bool isAssigned;
  final bool isSelected;
  final VoidCallback? onTap;

  const _LiveAmbulancePinWidget({
    required this.vehicleNumber,
    required this.status,
    this.isAssigned = false,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bearing = MarkerBearingScope.of(context);
    final bool isAvailable = status == 'available';
    final Color mainColor = isSelected
        ? MapMarkerBuilder.selectedColor
        : isAvailable
        ? AppColors.reliefGreenMedium
        : (isAssigned ? const Color(0xFF2563EB) : const Color(0xFFD97706));

    return Semantics(
      label: 'Ambulance $vehicleNumber',
      selected: isSelected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: isSelected ? 106 : 92,
            height: isSelected ? 94 : 82,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(isSelected ? 11 : 7),
                  decoration: BoxDecoration(
                    color: mainColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: isSelected ? 4 : 2.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: mainColor.withValues(alpha: 0.45),
                        blurRadius: 12,
                        spreadRadius: isSelected ? 7 : 3,
                      ),
                    ],
                  ),
                  child: bearing != null
                      ? Transform.rotate(
                          angle: bearing * math.pi / 180.0,
                          child: const Icon(
                            Icons.navigation_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        )
                      : const Icon(
                          Icons.airport_shuttle_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: mainColor.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: mainColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (isSelected)
                        const Icon(
                          Icons.check_circle,
                          size: 11,
                          color: MapMarkerBuilder.selectedColor,
                        ),
                      Flexible(
                        child: Text(
                          vehicleNumber,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
