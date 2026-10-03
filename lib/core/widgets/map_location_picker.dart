import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_colors.dart';
import 'interactive_map_widget.dart';

Future<LatLng?> showParkingLocationPicker(
  BuildContext context, {
  required LatLng mapCenter,
  LatLng? selectedPoint,
}) => showModalBottomSheet<LatLng>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _ParkingLocationPicker(
    mapCenter: mapCenter,
    selectedPoint: selectedPoint,
  ),
);

class _ParkingLocationPicker extends StatefulWidget {
  final LatLng mapCenter;
  final LatLng? selectedPoint;
  const _ParkingLocationPicker({required this.mapCenter, this.selectedPoint});

  @override
  State<_ParkingLocationPicker> createState() => _ParkingLocationPickerState();
}

class _ParkingLocationPickerState extends State<_ParkingLocationPicker> {
  LatLng? _point;

  @override
  void initState() {
    super.initState();
    _point = widget.selectedPoint;
  }

  void _dropPin(LatLng point) {
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 85 ||
        point.longitude.abs() > 180 ||
        (point.latitude == 0 && point.longitude == 0)) {
      return;
    }
    setState(() => _point = point);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      height: MediaQuery.sizeOf(context).height * .88,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Choose ambulance parking spot',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel map selection',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Move or zoom the map, then tap the exact parking spot to drop a pin.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: InteractiveMapWidget(
              center: widget.selectedPoint ?? widget.mapCenter,
              zoom: 15,
              onTap: _dropPin,
              markers: [
                if (_point != null)
                  Marker(
                    key: const ValueKey('selected-parking-pin'),
                    point: _point!,
                    width: 48,
                    height: 48,
                    alignment: Alignment.topCenter,
                    child: Semantics(
                      label: 'Selected ambulance parking spot',
                      child: const Icon(
                        Icons.location_pin,
                        size: 48,
                        color: AppColors.emergencyRed,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _point == null
                      ? 'Tap the map to select a parking spot.'
                      : 'Parking pin selected. Tap another spot to move it.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _point == null
                      ? null
                      : () => Navigator.pop(context, _point),
                  icon: const Icon(Icons.check),
                  label: const Text('Use this parking spot'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
