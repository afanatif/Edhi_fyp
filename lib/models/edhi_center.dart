import 'package:cloud_firestore/cloud_firestore.dart';

class EdhiCenter {
  final String centerId;
  final String name;
  final String address;
  final String contact;
  final String city;
  final int ambulanceCount;
  final List<String> services;
  final double? latitude;
  final double? longitude;
  final String? sourceUrl;
  final String? verifiedOn;
  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      latitude!.isFinite &&
      longitude!.isFinite &&
      latitude!.abs() <= 90 &&
      longitude!.abs() <= 180 &&
      (latitude != 0 || longitude != 0);

  const EdhiCenter({
    required this.centerId,
    required this.name,
    required this.address,
    required this.contact,
    this.city = '',
    this.ambulanceCount = 0,
    this.services = const ['Ambulance', 'Emergency Aid', 'Donation Center'],
    this.latitude,
    this.longitude,
    this.sourceUrl,
    this.verifiedOn,
  });

  factory EdhiCenter.fromMap(Map<String, dynamic> map, {String? docId}) {
    return EdhiCenter(
      centerId: docId ?? map['centerId'] ?? '',
      name: map['name'] ?? '',
      address: map['address'] ?? '',
      contact: map['contact'] ?? '',
      city: map['city'] ?? '',
      ambulanceCount: (map['ambulanceCount'] as num?)?.toInt() ?? 0,
      services: List<String>.from(
        map['services'] ?? ['Ambulance', 'Emergency Aid'],
      ),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      sourceUrl: map['sourceUrl'] as String?,
      verifiedOn: map['verifiedOn'] as String?,
    );
  }

  factory EdhiCenter.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return EdhiCenter.fromMap(snapshot.data() ?? {}, docId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'centerId': centerId,
      'name': name,
      'address': address,
      'contact': contact,
      'city': city,
      'ambulanceCount': ambulanceCount,
      'services': services,
      'latitude': latitude,
      'longitude': longitude,
      'sourceUrl': sourceUrl,
      'verifiedOn': verifiedOn,
    };
  }
}
