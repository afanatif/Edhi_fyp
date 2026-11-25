import 'dart:math' as math;

/// A city users can pick, with an approximate centre for GPS matching.
class PakCity {
  final String name;
  final String province;
  final double lat;
  final double lng;
  final List<String> aliases;
  const PakCity(
    this.name,
    this.province,
    this.lat,
    this.lng, [
    this.aliases = const [],
  ]);
}

/// Fixed list so "Lahore", "lahore" and "LHR" all group as one city.
class PakistanCities {
  PakistanCities._();

  /// The app's default map location and the blood form's historic default.
  static const defaultCity = 'Abbottabad';

  /// Filter value meaning "show every city".
  static const all = 'All cities';

  /// Label for records saved before cities existed.
  static const notSet = 'City not set';

  static const List<PakCity> cities = [
    PakCity('Abbottabad', 'Khyber Pakhtunkhwa', 34.1688, 73.2215, ['atd']),
    PakCity('Bahawalpur', 'Punjab', 29.3956, 71.6836, ['bwp']),
    PakCity('Chiniot', 'Punjab', 31.7200, 72.9789),
    PakCity('Dera Ghazi Khan', 'Punjab', 30.0561, 70.6348, [
      'dg khan',
      'd.g. khan',
    ]),
    PakCity('Dera Ismail Khan', 'Khyber Pakhtunkhwa', 31.8314, 70.9019, [
      'di khan',
      'd.i. khan',
    ]),
    PakCity('Faisalabad', 'Punjab', 31.4504, 73.1350, ['fsd', 'lyallpur']),
    PakCity('Gilgit', 'Gilgit-Baltistan', 35.9208, 74.3144),
    PakCity('Gujranwala', 'Punjab', 32.1877, 74.1945, ['grw']),
    PakCity('Gujrat', 'Punjab', 32.5731, 74.1005),
    PakCity('Haripur', 'Khyber Pakhtunkhwa', 33.9946, 72.9106),
    PakCity('Hyderabad', 'Sindh', 25.3960, 68.3578, ['hyd']),
    PakCity('Islamabad', 'Islamabad Capital Territory', 33.6844, 73.0479, [
      'isb',
      'isl',
    ]),
    PakCity('Jhang', 'Punjab', 31.2781, 72.3317),
    PakCity('Jhelum', 'Punjab', 32.9425, 73.7257),
    PakCity('Karachi', 'Sindh', 24.8607, 67.0011, ['khi']),
    PakCity('Kasur', 'Punjab', 31.1187, 74.4507),
    PakCity('Kohat', 'Khyber Pakhtunkhwa', 33.5869, 71.4429),
    PakCity('Lahore', 'Punjab', 31.5204, 74.3587, ['lhr']),
    PakCity('Larkana', 'Sindh', 27.5570, 68.2264),
    PakCity('Mansehra', 'Khyber Pakhtunkhwa', 34.3302, 73.1968),
    PakCity('Mardan', 'Khyber Pakhtunkhwa', 34.1986, 72.0404),
    PakCity('Mirpur', 'Azad Kashmir', 33.1484, 73.7518),
    PakCity('Multan', 'Punjab', 30.1575, 71.5249, ['mux']),
    PakCity('Muzaffarabad', 'Azad Kashmir', 34.3700, 73.4711),
    PakCity('Nawabshah', 'Sindh', 26.2442, 68.4100, ['shaheed benazirabad']),
    PakCity('Okara', 'Punjab', 30.8138, 73.4534),
    PakCity('Peshawar', 'Khyber Pakhtunkhwa', 34.0151, 71.5249, ['pew']),
    PakCity('Quetta', 'Balochistan', 30.1798, 66.9750, ['uet']),
    PakCity('Rahim Yar Khan', 'Punjab', 28.4202, 70.2952, ['ryk']),
    PakCity('Rawalpindi', 'Punjab', 33.5651, 73.0169, ['pindi', 'rwp']),
    PakCity('Sahiwal', 'Punjab', 30.6682, 73.1114),
    PakCity('Sargodha', 'Punjab', 32.0836, 72.6711),
    PakCity('Sheikhupura', 'Punjab', 31.7167, 73.9850),
    PakCity('Sialkot', 'Punjab', 32.4945, 74.5229, ['skt']),
    PakCity('Sukkur', 'Sindh', 27.7052, 68.8574),
    PakCity('Swat', 'Khyber Pakhtunkhwa', 34.7717, 72.3600, ['mingora']),
    PakCity('Turbat', 'Balochistan', 26.0023, 63.0440),
    PakCity('Wah Cantt', 'Punjab', 33.7715, 72.7511, ['wah']),
  ];

  static List<String> get names =>
      cities.map((c) => c.name).toList(growable: false);

  static PakCity? byName(String name) {
    final key = name.trim().toLowerCase();
    for (final city in cities) {
      if (city.name.toLowerCase() == key) return city;
    }
    return null;
  }

  /// Maps free text ("lahore ", "LHR", "Lahore Cantt") onto the list, or ''.
  static String normalize(String? raw) {
    final text = (raw ?? '').trim().toLowerCase();
    if (text.isEmpty) return '';
    for (final city in cities) {
      if (city.name.toLowerCase() == text || city.aliases.contains(text)) {
        return city.name;
      }
    }
    // "Lahore Cantt", "Karachi, Sindh", "G-9, Islamabad"
    final words = text
        .split(RegExp(r'[^a-z.]+'))
        .where((w) => w.isNotEmpty)
        .toSet();
    for (final city in cities) {
      final name = city.name.toLowerCase();
      if (text.contains(name) || city.aliases.any(words.contains)) {
        return city.name;
      }
    }
    return '';
  }

  /// Display label for a stored city value.
  static String label(String? stored) {
    final city = normalize(stored);
    return city.isEmpty ? notSet : city;
  }

  /// Nearest listed city within [maxKm] of a GPS point, or null.
  static String? nearest(double lat, double lng, {double maxKm = 60}) {
    if (!lat.isFinite || !lng.isFinite || (lat == 0 && lng == 0)) {
      return null;
    }
    PakCity? best;
    var bestKm = double.infinity;
    for (final city in cities) {
      final km = _km(lat, lng, city.lat, city.lng);
      if (km < bestKm) {
        bestKm = km;
        best = city;
      }
    }
    return best != null && bestKm <= maxKm ? best.name : null;
  }

  /// Nearest city for a point, else a city named in [address], else ''.
  static String fromLocation(double lat, double lng, {String address = ''}) =>
      nearest(lat, lng) ?? normalize(address);

  /// Groups counts by city label ("Lahore 12 · Karachi 8"), biggest first.
  static List<MapEntry<String, int>> countBy<T>(
    Iterable<T> items,
    String Function(T) cityOf,
  ) {
    final counts = <String, int>{};
    for (final item in items) {
      final key = label(cityOf(item));
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return entries;
  }

  /// True when [stored] belongs under filter [selected].
  static bool matches(String? stored, String selected) {
    if (selected == all) return true;
    return label(stored) == selected;
  }

  static double _km(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
