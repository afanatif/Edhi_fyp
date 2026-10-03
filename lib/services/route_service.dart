import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'location_service.dart';

class RoadRouteResult {
  final List<LatLng> points;
  final double distanceKm;
  final int etaMinutes;
  final bool isRealRoadRoute;
  final double? durationSeconds;
  double get travelSeconds => durationSeconds ?? etaMinutes * 60.0;

  const RoadRouteResult({
    required this.points,
    required this.distanceKm,
    required this.etaMinutes,
    this.isRealRoadRoute = true,
    this.durationSeconds,
  });
}

class RouteService {
  RouteService._();

  static final Map<String, RoadRouteResult> _routeCache = {};

  /// Position generated vehicles on a drivable road, never in a random building.
  static Future<LatLng> snapToRoad(LatLng point) async {
    if (!point.latitude.isFinite ||
        !point.longitude.isFinite ||
        point.latitude.abs() > 90 ||
        point.longitude.abs() > 180 ||
        (point.latitude == 0 && point.longitude == 0)) {
      throw ArgumentError('Choose a valid staging point.');
    }
    final response = await http
        .get(
          Uri.parse(
            'https://router.project-osrm.org/nearest/v1/driving/${point.longitude},${point.latitude}?number=1',
          ),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final waypoints = data['waypoints'] as List?;
      if (data['code'] == 'Ok' && waypoints != null && waypoints.isNotEmpty) {
        final waypoint = waypoints.first as Map<String, dynamic>;
        if ((waypoint['distance'] as num).toDouble() > 1500) {
          throw StateError(
            'No drivable road within 1.5 km. Choose a different staging point.',
          );
        }
        final coordinates = waypoint['location'] as List;
        return LatLng(
          (coordinates[1] as num).toDouble(),
          (coordinates[0] as num).toDouble(),
        );
      }
    }
    throw StateError(
      'Road positioning unavailable. Nothing was added; retry when connected.',
    );
  }

  /// Fetches the real road-following route from OSRM (Open Source Routing Machine)
  /// If offline or timed out, gracefully falls back to an interpolated road-grid corridor.
  static Future<RoadRouteResult> getRoadRoute(
    LatLng start,
    LatLng destination,
  ) async {
    // Generate cache key rounded to 4 decimals (~11 meters resolution)
    final cacheKey =
        '${start.latitude.toStringAsFixed(4)},${start.longitude.toStringAsFixed(4)}->'
        '${destination.latitude.toStringAsFixed(4)},${destination.longitude.toStringAsFixed(4)}';

    if (_routeCache.containsKey(cacheKey)) {
      return _routeCache[cacheKey]!;
    }

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;

        if (routes != null && routes.isNotEmpty) {
          final primaryRoute = routes.first as Map<String, dynamic>;
          final distanceMeters =
              (primaryRoute['distance'] as num?)?.toDouble() ?? 0.0;
          final durationSec =
              (primaryRoute['duration'] as num?)?.toDouble() ?? 0.0;

          final geometry = primaryRoute['geometry'] as Map<String, dynamic>?;
          final coords = geometry?['coordinates'] as List?;

          if (coords != null && coords.length >= 2) {
            final List<LatLng> roadPoints = coords.map((pair) {
              final list = pair as List;
              return LatLng(
                (list[1] as num).toDouble(),
                (list[0] as num).toDouble(),
              );
            }).toList();

            // Densify road points to uniform ~22-meter micro-steps for silky-smooth momentum
            final smoothPoints = densifyRoute(
              roadPoints,
              maxDistanceMeters: 22.0,
            );

            final distKm = double.parse(
              (distanceMeters / 1000.0).toStringAsFixed(1),
            );
            // Routing estimate only; do not invent a siren/traffic advantage.
            final adjustedDurationMinutes = (durationSec / 60.0).ceil();
            final etaMin = adjustedDurationMinutes < 1
                ? 1
                : adjustedDurationMinutes;

            final result = RoadRouteResult(
              points: smoothPoints,
              distanceKm: distKm > 0 ? distKm : 0.5,
              etaMinutes: etaMin,
              isRealRoadRoute: true,
              durationSeconds: durationSec,
            );

            if (_routeCache.length >= 128) {
              _routeCache.remove(_routeCache.keys.first);
            }
            _routeCache[cacheKey] = result;
            return result;
          }
        }
      }
    } catch (e) {
      debugPrint('OSRM routing fetch fallback: $e');
    }

    // Fallback: Generate realistic road-grid waypoints with road circuity factor
    final fallbackResult = generateCorridorRoute(start, destination);
    // Never cache routing failures: the next attempt can recover connectivity.
    return fallbackResult;
  }

  /// Densifies a list of waypoints so that no two consecutive points are further apart
  /// than [maxDistanceMeters]. This ensures constant-velocity smooth transit simulation
  /// and rich polyline curves without abrupt velocity spikes.
  static List<LatLng> densifyRoute(
    List<LatLng> points, {
    double maxDistanceMeters = 16.0,
  }) {
    if (points.length < 2) return points;

    final List<LatLng> densified = [];
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      densified.add(p1);

      final distMeters =
          LocationService.calculateDistanceInKm(
            p1.latitude,
            p1.longitude,
            p2.latitude,
            p2.longitude,
          ) *
          1000.0;

      if (distMeters > maxDistanceMeters) {
        final segments = (distMeters / maxDistanceMeters).ceil();
        for (int s = 1; s < segments; s++) {
          final t = s / segments;
          final lat = p1.latitude + (p2.latitude - p1.latitude) * t;
          final lng = p1.longitude + (p2.longitude - p1.longitude) * t;
          densified.add(LatLng(lat, lng));
        }
      }
    }
    densified.add(points.last);
    return densified;
  }

  /// Synthesizes realistic street turns along the terrain corridor when offline
  static RoadRouteResult generateCorridorRoute(
    LatLng start,
    LatLng destination,
  ) {
    final straightDist = LocationService.calculateDistanceInKm(
      start.latitude,
      start.longitude,
      destination.latitude,
      destination.longitude,
    );

    // Urban/Mountain road network circuity factor (Abbottabad topology ~1.30x)
    final roadDist = double.parse((straightDist * 1.30).toStringAsFixed(1));
    final eta = LocationService.calculateEtaMinutes(
      roadDist,
      averageSpeedKmH: 42.0,
    );

    // Multi-segment street turn waypoints along the road axis
    final List<LatLng> points = [start];

    final double latDiff = destination.latitude - start.latitude;
    final double lngDiff = destination.longitude - start.longitude;

    // Mid-segment street bends
    points.add(
      LatLng(start.latitude + latDiff * 0.35, start.longitude + lngDiff * 0.15),
    );
    points.add(
      LatLng(start.latitude + latDiff * 0.50, start.longitude + lngDiff * 0.60),
    );
    points.add(
      LatLng(start.latitude + latDiff * 0.80, start.longitude + lngDiff * 0.75),
    );
    points.add(destination);

    final smoothPoints = densifyRoute(points, maxDistanceMeters: 22.0);

    return RoadRouteResult(
      points: smoothPoints,
      distanceKm: roadDist > 0 ? roadDist : 0.5,
      etaMinutes: eta,
      isRealRoadRoute: false,
    );
  }

  static void clearCache() {
    _routeCache.clear();
  }
}
