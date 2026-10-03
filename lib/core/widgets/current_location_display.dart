import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../../models/emergency_request.dart';
import '../../services/location_service.dart';
import '../theme/app_colors.dart';

class CurrentLocationDisplay extends StatefulWidget {
  final ValueChanged<RequestLocation?>? onChanged;
  final Stream<LatLng> Function()? positionStream;
  final Future<String> Function(double, double)? addressLookup;

  const CurrentLocationDisplay({
    super.key,
    this.onChanged,
    this.positionStream,
    this.addressLookup,
  });

  @override
  State<CurrentLocationDisplay> createState() => _CurrentLocationDisplayState();
}

class _CurrentLocationDisplayState extends State<CurrentLocationDisplay>
    with WidgetsBindingObserver {
  StreamSubscription<LatLng>? _subscription;
  int _generation = 0;
  LatLng? _position;
  LatLng? _addressPosition;
  String? _address;
  DateTime? _lastLookup;
  String _label = 'Finding your location…';
  bool _locating = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _generation++;
      _subscription?.cancel();
      _subscription = null;
    }
  }

  void _refresh() {
    final generation = ++_generation;
    _subscription?.cancel();
    _lastLookup = null;
    _locating = true;
    _label = _address ?? 'Finding your location…';
    if (mounted) setState(() {});
    try {
      _subscription =
          (widget.positionStream?.call() ??
                  LocationService.watchCurrentLocation())
              .listen(
                (point) => _updatePosition(point, generation),
                onError: (Object error) {
                  if (!mounted || generation != _generation) return;
                  _generation++;
                  _subscription?.cancel();
                  _subscription = null;
                  setState(() {
                    _locating = false;
                    _label = 'Location unavailable';
                    _position = null;
                    _address = null;
                    _addressPosition = null;
                  });
                  widget.onChanged?.call(null);
                },
                onDone: () {
                  if (!mounted || generation != _generation || !_locating) {
                    return;
                  }
                  setState(() {
                    _locating = false;
                    _label = 'Location unavailable';
                  });
                },
              );
    } catch (_) {
      _locating = false;
      _label = 'Location unavailable';
    }
  }

  Future<void> _updatePosition(LatLng point, int generation) async {
    if (!mounted || generation != _generation) return;
    if (!RequestLocation(
      latitude: point.latitude,
      longitude: point.longitude,
    ).hasValidCoordinates) {
      return;
    }
    final coordinates =
        '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
    final nearAddress =
        _addressPosition != null &&
        LocationService.calculateDistanceInKm(
              point.latitude,
              point.longitude,
              _addressPosition!.latitude,
              _addressPosition!.longitude,
            ) <
            0.05;
    setState(() {
      _position = point;
      _locating = false;
      _label = nearAddress && _address != null ? _address! : coordinates;
    });
    widget.onChanged?.call(
      RequestLocation(
        latitude: point.latitude,
        longitude: point.longitude,
        address: _label,
      ),
    );
    if (_lastLookup != null &&
        DateTime.now().difference(_lastLookup!) < const Duration(seconds: 30)) {
      return;
    }
    _lastLookup = DateTime.now();
    try {
      final address =
          await (widget.addressLookup ??
              LocationService.getAddressFromCoordinates)(
            point.latitude,
            point.longitude,
          );
      if (!mounted ||
          generation != _generation ||
          _position != point ||
          address.isEmpty) {
        return;
      }
      setState(() {
        _address = address;
        _addressPosition = point;
        _label = address;
      });
      widget.onChanged?.call(
        RequestLocation(
          latitude: point.latitude,
          longitude: point.longitude,
          address: address,
        ),
      );
    } catch (
      _
    ) {} // The coordinates remain available when the address service is offline.
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Tooltip(
          message: _label,
          child: Text(
            _label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: 'Refresh current location',
        onPressed: _locating ? null : _refresh,
        padding: const EdgeInsets.all(3),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        visualDensity: VisualDensity.compact,
        icon: _locating
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            : const Icon(
                Icons.my_location_rounded,
                size: 16,
                color: AppColors.reliefGreenMedium,
              ),
      ),
    ],
  );
}
