import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/location_service.dart';
import '../constants/pakistan_cities.dart';
import '../theme/app_colors.dart';

/// Result of a GPS city lookup.
class DetectedCity {
  final String city;

  /// 'gps' when GPS matched a listed city, otherwise 'default'.
  final String source;
  const DetectedCity(this.city, this.source);
}

/// Works out the user's city from GPS; falls back to [PakistanCities.defaultCity].
Future<DetectedCity> detectCityFromGps() async {
  try {
    final point = await LocationService.getCurrentLocation(
      allowFallback: false,
    );
    final nearest = PakistanCities.nearest(point.latitude, point.longitude);
    if (nearest != null) return DetectedCity(nearest, 'gps');
    final address = await LocationService.getAddressFromCoordinates(
      point.latitude,
      point.longitude,
    );
    final named = PakistanCities.normalize(address);
    if (named.isNotEmpty) return DetectedCity(named, 'gps');
  } catch (_) {
    // GPS off or denied: use the default city.
  }
  return const DetectedCity(PakistanCities.defaultCity, 'default');
}

/// Bottom sheet listing Pakistani cities. Returns the chosen name, or null.
Future<String?> showCityPicker(
  BuildContext context, {
  required String current,
  bool allowAll = true,
  bool allowGps = true,
  String title = 'Choose a city',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _CityPickerSheet(
      current: current,
      allowAll: allowAll,
      allowGps: allowGps,
      title: title,
    ),
  );
}

class _CityPickerSheet extends StatefulWidget {
  final String current;
  final bool allowAll;
  final bool allowGps;
  final String title;
  const _CityPickerSheet({
    required this.current,
    required this.allowAll,
    required this.allowGps,
    required this.title,
  });

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  String _query = '';
  bool _locating = false;

  Future<void> _useGps() async {
    setState(() => _locating = true);
    final found = await detectCityFromGps();
    if (!mounted) return;
    setState(() => _locating = false);
    if (found.source == 'gps') {
      Navigator.pop(context, found.city);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not read your location. Turn on GPS or pick a city from the list.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final cities = PakistanCities.cities
        .where(
          (c) =>
              q.isEmpty ||
              c.name.toLowerCase().contains(q) ||
              c.province.toLowerCase().contains(q) ||
              c.aliases.any((a) => a.contains(q)),
        )
        .toList();
    final height = MediaQuery.sizeOf(context).height * 0.75;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                autofocus: false,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search city or province',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 8),
              if (widget.allowGps)
                ListTile(
                  leading: _locating
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Icon(
                          Icons.my_location_rounded,
                          color: AppColors.statusApproved,
                        ),
                  title: const Text('Use my current location'),
                  subtitle: const Text('Detect my city with GPS'),
                  onTap: _locating ? null : _useGps,
                ),
              if (widget.allowAll)
                _option(
                  PakistanCities.all,
                  'Show every city',
                  Icons.public_rounded,
                ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: cities.length,
                  itemBuilder: (_, i) => _option(
                    cities[i].name,
                    cities[i].province,
                    Icons.location_city_rounded,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(String name, String subtitle, IconData icon) {
    final selected = name == widget.current;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? AppColors.emergencyRed : AppColors.textSecondary,
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: selected
          ? const Icon(Icons.check_circle, color: AppColors.emergencyRed)
          : null,
      onTap: () => Navigator.pop(context, name),
    );
  }
}

/// Compact "📍 Lahore ▾" chip that opens [showCityPicker].
class CityFilterChip extends StatelessWidget {
  final String city;
  final ValueChanged<String> onChanged;
  final bool allowAll;
  final String? countLabel;
  const CityFilterChip({
    super.key,
    required this.city,
    required this.onChanged,
    this.allowAll = true,
    this.countLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.emergencyRed.withValues(alpha: 0.08),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () async {
          final picked = await showCityPicker(
            context,
            current: city,
            allowAll: allowAll,
          );
          if (picked != null) onChanged(picked);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.place_rounded,
                size: 18,
                color: AppColors.emergencyRed,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  countLabel == null ? city : '$city · $countLabel',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.emergencyRedDark,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_drop_down_rounded,
                color: AppColors.emergencyRedDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal "Lahore 12 · Karachi 8" counters; tapping one selects it.
class CityCountStrip extends StatelessWidget {
  final List<MapEntry<String, int>> counts;
  final String selected;
  final ValueChanged<String> onSelected;
  const CityCountStrip({
    super.key,
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) return const SizedBox.shrink();
    final total = counts.fold<int>(0, (sum, e) => sum + e.value);
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(PakistanCities.all, total),
          for (final entry in counts) _chip(entry.key, entry.value),
        ],
      ),
    );
  }

  Widget _chip(String city, int count) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text('$city  $count'),
      selected: selected == city,
      onSelected: (_) => onSelected(city),
      selectedColor: AppColors.emergencyRed.withValues(alpha: 0.14),
      labelStyle: TextStyle(
        fontWeight: selected == city ? FontWeight.w800 : FontWeight.w500,
      ),
    ),
  );
}
