import 'package:latlong2/latlong.dart';

class HospitalMatch {
  final String name;
  final String capability;
  final String phone;
  final LatLng location;
  final double distanceKm;

  const HospitalMatch({
    required this.name,
    required this.capability,
    required this.phone,
    required this.location,
    required this.distanceKm,
  });
}

class ResponsePlan {
  final List<String> requiredEquipment;
  final List<HospitalMatch> hospitals;
  final String clinicalNote;

  const ResponsePlan({
    required this.requiredEquipment,
    required this.hospitals,
    required this.clinicalNote,
  });
}
