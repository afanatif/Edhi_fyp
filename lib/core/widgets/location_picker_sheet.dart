import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/interactive_map_widget.dart';
import '../../services/location_service.dart';
import '../../services/firestore_service.dart';
import '../../models/emergency_request.dart';

class LocationPickerSheet extends StatefulWidget {
  final RequestLocation initialLocation;

  const LocationPickerSheet({super.key, required this.initialLocation});

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  late LatLng _selectedPoint;
  late TextEditingController _addressController;
  bool _isLocating = false;
  bool _isGpsLocked = false;
  bool _pinConfirmed = false;
  String _statusMessage = 'Detecting GPS coordinates...';
  Timer? _geocodeDebounce;

  @override
  void initState() {
    super.initState();
    final hasCustomInitial =
        widget.initialLocation.latitude != 0.0 &&
        widget.initialLocation.longitude != 0.0;
    _pinConfirmed = hasCustomInitial;

    final lat = hasCustomInitial
        ? widget.initialLocation.latitude
        : LocationService.defaultLocation.latitude;
    final lng = hasCustomInitial
        ? widget.initialLocation.longitude
        : LocationService.defaultLocation.longitude;

    _selectedPoint = LatLng(lat, lng);
    _addressController = TextEditingController(
      text: widget.initialLocation.address.isNotEmpty
          ? widget.initialLocation.address
          : LocationService.defaultAddress,
    );

    // Automatically trigger GPS detection on sheet launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _detectLiveGps(isAuto: true);
    });
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _addressController.dispose();
    super.dispose();
  }

  /// Automatically or manually fetches live GPS coordinates with graceful fallbacks
  void _detectLiveGps({bool isAuto = false}) async {
    if (!mounted) return;
    setState(() {
      _isLocating = true;
      _statusMessage = 'Locking GPS satellite position...';
    });

    try {
      final coords = await LocationService.getCurrentLocation(
        allowFallback: false,
      );
      if (!mounted) return;

      setState(() {
        _selectedPoint = coords;
        _isLocating = false;
        _isGpsLocked = true;
        _pinConfirmed = true;
        _statusMessage = 'GPS fix received. Check the pin before confirming.';
      });

      _reverseGeocode(coords);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLocating = false;
        _isGpsLocked = false;
        _statusMessage = 'GPS unavailable. Tap anywhere on map to set pin.';
      });
    }
  }

  void _onMapTap(LatLng point) {
    setState(() {
      _selectedPoint = point;
      _pinConfirmed = true;
      _isGpsLocked = false;
      _statusMessage =
          'Target Pin Set (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})';
    });

    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 350), () {
      _reverseGeocode(point);
    });
  }

  void _reverseGeocode(LatLng point) async {
    try {
      final place = await LocationService.getAddressFromCoordinates(
        point.latitude,
        point.longitude,
      );
      if (mounted && place.isNotEmpty) {
        setState(() {
          _addressController.text = place;
        });
      }
    } catch (_) {
      // Retain existing text or coordinates fallback
      if (mounted && _addressController.text.isEmpty) {
        _addressController.text =
            'Location (${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)})';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestore = context.watch<FirestoreService>();
    final allEmployees = firestore.getAllEmployees();

    // Extract all drivers with active location coordinates
    final activeDrivers = allEmployees
        .where(
          (e) =>
              e.role == 'driver' &&
              e.hasValidLocation &&
              (FirestoreService.simulatedFleetEnabled ||
                  !firestore.isLiveFirebase ||
                  e.hasFreshGps(DateTime.now())),
        )
        .toList();

    // Calculate nearest available ambulance relative to the user's selected pinpoint
    final nearest = firestore.findNearestAvailableAmbulance(
      _selectedPoint.latitude,
      _selectedPoint.longitude,
    );

    // Build map markers
    final markers = <Marker>[
      // 1. User emergency pinpoint marker
      MapMarkerBuilder.emergencyPin(_selectedPoint, label: 'SOS Target'),
    ];

    // 2. Add all nearby drivers with interactive telemetry badges
    for (final driver in activeDrivers) {
      final bool isNearest =
          nearest != null && nearest.employee.employeeId == driver.employeeId;
      final distKm = LocationService.calculateDistanceInKm(
        driver.currentLat,
        driver.currentLng,
        _selectedPoint.latitude,
        _selectedPoint.longitude,
      );

      final isAvailable = driver.status == 'available';

      markers.add(
        Marker(
          key: ValueKey('picker_driver_${driver.employeeId}'),
          point: LatLng(driver.currentLat, driver.currentLng),
          width: 105,
          height: 80,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isNearest)
                  Container(
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAB308),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.flash_on,
                          size: 10,
                          color: Colors.black87,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'NEAREST UNIT',
                          style: GoogleFonts.outfit(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isNearest
                        ? AppColors.reliefGreenMedium
                        : (isAvailable
                              ? const Color(0xFF059669)
                              : const Color(0xFF64748B)),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isNearest ? const Color(0xFFEAB308) : Colors.white,
                      width: isNearest ? 3.0 : 2.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isNearest
                                    ? AppColors.reliefGreenMedium
                                    : Colors.black)
                                .withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.airport_shuttle_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: isNearest
                          ? AppColors.reliefGreenMedium
                          : Colors.black12,
                      width: 1,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 4),
                    ],
                  ),
                  child: Text(
                    '${driver.vehicleNumber} • ${distKm.toStringAsFixed(1)}km',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: isNearest
                          ? AppColors.reliefGreenMedium
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.only(
              left: 20,
              right: 12,
              top: 16,
              bottom: 10,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Pinpoint Emergency Location',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_isGpsLocked)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.reliefGreenMedium.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.gps_fixed,
                                    size: 12,
                                    color: AppColors.reliefGreenMedium,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'GPS LOCKED',
                                    style: GoogleFonts.inter(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.reliefGreenMedium,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      Text(
                        _statusMessage,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Interactive Map Area
          Expanded(
            child: Stack(
              children: [
                InteractiveMapWidget(
                  center: _selectedPoint,
                  zoom: 15.0,
                  onTap: _onMapTap,
                  markers: markers,
                ),

                // Top Floating Nearest Ambulance Telemetry HUD
                Positioned(
                  top: 12,
                  left: 14,
                  right: 14,
                  child: nearest != null
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.reliefGreenMedium,
                              width: 1.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.reliefGreenMedium.withValues(
                                    alpha: 0.12,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.flash_on_rounded,
                                  color: AppColors.reliefGreenMedium,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Nearest Standby Unit:',
                                          style: GoogleFonts.inter(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.reliefGreenMedium,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            'AUTO-ALLOCATE',
                                            style: GoogleFonts.outfit(
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${nearest.employee.name} (${nearest.employee.vehicleNumber})',
                                      style: GoogleFonts.outfit(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '${nearest.distanceKm.toStringAsFixed(1)} km from your pin • ETA ~${nearest.etaMinutes} mins',
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.reliefGreenMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50.withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.amber.shade300,
                              width: 1.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Colors.amber.shade900,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'All fleet units currently engaged. Request will be priority-assigned by Central Dispatch.',
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),

                // Floating Re-detect Live GPS Action Button
                Positioned(
                  bottom: 14,
                  left: 14,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 4,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      minimumSize: Size.zero,
                    ),
                    onPressed: _isLocating
                        ? null
                        : () => _detectLiveGps(isAuto: false),
                    icon: _isLocating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.emergencyRed,
                            ),
                          )
                        : Icon(
                            _isGpsLocked
                                ? Icons.gps_fixed_rounded
                                : Icons.my_location_rounded,
                            size: 16,
                            color: AppColors.emergencyRed,
                          ),
                    label: Text(
                      _isLocating
                          ? 'Acquiring...'
                          : (_isGpsLocked
                                ? 'Re-center GPS'
                                : 'Detect Live GPS'),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Address input & confirmation bar
          Container(
            padding: const EdgeInsets.all(18),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomTextField(
                    label: 'Street / Landmark Address',
                    controller: _addressController,
                    hint: 'e.g. Mandian Chowk, Abbottabad',
                    prefixIcon: Icons.location_on_rounded,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Coordinates: ${_selectedPoint.latitude.toStringAsFixed(5)}, ${_selectedPoint.longitude.toStringAsFixed(5)}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (nearest != null)
                        Text(
                          'Unit: ${nearest.employee.vehicleNumber} (ETA ~${nearest.etaMinutes}m)',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.reliefGreenMedium,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  CustomButton(
                    text: 'Confirm Patient Location 📍',
                    backgroundColor: AppColors.reliefGreenMedium,
                    onPressed: () {
                      if (!_pinConfirmed || _isLocating) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Wait for GPS or tap the map to select the patient location.',
                            ),
                          ),
                        );
                        return;
                      }
                      final updatedLocation = RequestLocation(
                        latitude: _selectedPoint.latitude,
                        longitude: _selectedPoint.longitude,
                        address: _addressController.text.trim().isNotEmpty
                            ? _addressController.text.trim()
                            : 'Location (${_selectedPoint.latitude.toStringAsFixed(4)}, ${_selectedPoint.longitude.toStringAsFixed(4)})',
                      );
                      Navigator.pop(context, updatedLocation);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
