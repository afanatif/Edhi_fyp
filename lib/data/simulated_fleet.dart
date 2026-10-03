import 'dart:math';
import 'package:latlong2/latlong.dart';
import '../models/edhi_center.dart';

/// Approximate CITY staging points for simulation, not verified office pins.
class SimulatedFleet {
  static LatLng stagingPoint(EdhiCenter? center, LatLng fallback) {
    if (center?.hasCoordinates == true) {
      return LatLng(center!.latitude!, center.longitude!);
    }
    return switch (center?.city.toLowerCase()) {
      'karachi' => const LatLng(24.8508, 66.9980),
      'lahore' => const LatLng(31.5060, 74.2870),
      'islamabad' => const LatLng(33.7020, 73.0800),
      'quetta' => const LatLng(30.1830, 67.0030),
      'faisalabad' => const LatLng(31.4180, 73.0790),
      _ => fallback,
    };
  }

  static LatLng nearbyPoint(LatLng origin, Random random) {
    final radius = 100 + random.nextDouble() * 450;
    final angle = random.nextDouble() * 2 * pi;
    return LatLng(
      origin.latitude + radius * cos(angle) / 111320,
      origin.longitude +
          radius * sin(angle) / (111320 * cos(origin.latitude * pi / 180)),
    );
  }

  static const names = [
    'Ali',
    'Ahmed',
    'Bilal',
    'Hamza',
    'Hassan',
    'Usman',
    'Zain',
    'Saad',
    'Danish',
    'Imran',
  ];
}
