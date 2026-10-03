import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

class LocationService {
  LocationService._();

  // Default campus / city coordinates: Abbottabad, Pakistan (COMSATS / Edhi Mandian)
  static const LatLng defaultLocation = LatLng(34.1986, 73.2312);
  static const String defaultAddress =
      'Mandian, Main Mansehra Road, Abbottabad';

  /// Calculate great-circle distance between two points in kilometers using Haversine formula
  static double calculateDistanceInKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double p = 0.017453292519943295; // Math.PI / 180
    final double a =
        0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a)); // 2 * R; R = 6371 km
  }

  /// Estimate arrival time in minutes based on distance and average response speed (45 km/h)
  static int calculateEtaMinutes(
    double distanceKm, {
    double averageSpeedKmH = 45.0,
  }) {
    if (distanceKm <= 0.2) return 2;
    final minutes = ((distanceKm / averageSpeedKmH) * 60).round();
    return minutes < 2 ? 2 : minutes;
  }

  /// Calculates the initial forward azimuth/bearing (in degrees, 0..360) between two coordinates
  static double calculateBearing(LatLng start, LatLng dest) {
    if (start.latitude == dest.latitude && start.longitude == dest.longitude) {
      return 0.0;
    }
    const double degToRad = math.pi / 180.0;
    const double radToDeg = 180.0 / math.pi;

    final dLon = (dest.longitude - start.longitude) * degToRad;
    final lat1 = start.latitude * degToRad;
    final lat2 = dest.latitude * degToRad;

    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final radians = math.atan2(y, x);
    return (radians * radToDeg + 360.0) % 360.0;
  }

  /// Trims a road-following route so it smoothly starts right at the current vehicle position
  /// and continues along the forward route path to the destination without gaps or jumps.
  static List<LatLng> trimRouteAhead(
    List<LatLng> fullRoute,
    LatLng currentPosition,
  ) {
    if (fullRoute.isEmpty) return [currentPosition];
    if (fullRoute.length == 1) return fullRoute;

    int closestIdx = 0;
    double minDistance = double.infinity;

    for (int i = 0; i < fullRoute.length; i++) {
      final dist = calculateDistanceInKm(
        currentPosition.latitude,
        currentPosition.longitude,
        fullRoute[i].latitude,
        fullRoute[i].longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        closestIdx = i;
      }
    }

    if (closestIdx >= fullRoute.length - 1) {
      return [currentPosition, fullRoute.last];
    }

    return [currentPosition, ...fullRoute.sublist(closestIdx + 1)];
  }

  /// Request permission and fetch current GPS/Browser location
  static Future<LatLng> getCurrentLocation({bool allowFallback = true}) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!allowFallback) throw StateError('Location services are disabled.');
        debugPrint(
          'Location services are disabled; using default coordinates.',
        );
        return defaultLocation;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!allowFallback) throw StateError('Location permission denied.');
          debugPrint('Location permission denied; using default coordinates.');
          return defaultLocation;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!allowFallback) {
          throw StateError('Location permission permanently denied.');
        }
        debugPrint(
          'Location permissions permanently denied; using default coordinates.',
        );
        return defaultLocation;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      if (!allowFallback) rethrow;
      debugPrint('Error getting GPS coordinates: $e; falling back to default.');
      return defaultLocation;
    }
  }

  /// A battery-conscious live position feed for an on-duty ambulance.
  static Stream<LatLng> watchCurrentLocation() async* {
    final initial = await getCurrentLocation(allowFallback: false);
    yield initial;

    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).map((position) => LatLng(position.latitude, position.longitude));
  }

  /// Reverse geocode coordinates to real place name via OpenStreetMap Nominatim
  static Future<String> getAddressFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$latitude&lon=$longitude&zoom=18&addressdetails=1',
      );
      final response = await http
          .get(url, headers: {'User-Agent': 'EdhiConnectAI/1.0'})
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data['display_name'] != null) {
          final displayName = data['display_name'] as String;
          final parts = displayName.split(',');
          if (parts.length > 3) {
            return parts.take(3).map((p) => p.trim()).join(', ');
          }
          return displayName;
        }
      }
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
    }

    // Coordinates fallback if offline or request timeout
    return 'Location (${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)})';
  }

  /// Launch turn-by-turn driving directions in Google Maps
  static Future<bool> openGoogleMapsNavigation(
    double latitude,
    double longitude,
  ) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=driving',
    );

    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        return await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Error launching Google Maps URL: $e');
      return false;
    }
  }

  static Future<bool> callEdhiHelpline() async {
    final uri = Uri.parse('tel:115');
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('Could not launch Edhi helpline: $error');
      return false;
    }
  }
}
