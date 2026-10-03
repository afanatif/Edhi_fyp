import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String
  cnic; // Computerized National Identity Card / Citizen Username (e.g. 37405-1234567-1)
  final String role; // 'user', 'admin', 'employee'
  final String address;
  final String profileImage;
  final bool isActive;
  final DateTime? createdAt;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    this.cnic = '',
    this.address = '',
    this.profileImage = '',
    this.isActive = true,
    this.createdAt,
  });

  bool get isAdmin => role == 'admin';
  bool get isEmployee => role == 'employee';
  bool get isUser => role == 'user';

  /// Strips all non-digit characters from raw CNIC string
  static String cleanCnic(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// Validates standard Pakistani 13-digit CNIC
  static bool isValidCnic(String raw) {
    return RegExp(
      r'^(?:[1-7][0-9]{12}|[1-7][0-9]{4}-[0-9]{7}-[0-9])$',
    ).hasMatch(raw.trim());
  }

  static String normalizePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0092')) digits = digits.substring(2);
    if (digits.length == 11 && digits.startsWith('03')) {
      digits = '92${digits.substring(1)}';
    }
    return '+$digits';
  }

  static bool isValidPhone(String raw) =>
      RegExp(r'^\+923[0-9]{9}$').hasMatch(normalizePhone(raw)) &&
      !RegExp(r'[a-zA-Z]').hasMatch(raw);

  /// Formats raw or partial CNIC into standard Pakistani format: 12345-1234567-1
  static String formatCnic(String raw) {
    final digits = cleanCnic(raw);
    if (digits.length == 13) {
      return '${digits.substring(0, 5)}-${digits.substring(5, 12)}-${digits.substring(12, 13)}';
    }
    return raw.trim();
  }

  factory AppUser.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    return AppUser(
      id: docId ?? map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      cnic: map['cnic'] ?? '',
      role: map['role'] ?? 'user',
      address: map['address'] ?? '',
      profileImage: map['profileImage'] ?? '',
      isActive: map['isActive'] ?? true,
      createdAt: parseDate(map['createdAt']),
    );
  }

  factory AppUser.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    return AppUser.fromMap(snapshot.data() ?? {}, docId: snapshot.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'cnic': cnic,
      'role': role,
      'address': address,
      'profileImage': profileImage,
      'isActive': isActive,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  AppUser copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? cnic,
    String? role,
    String? address,
    String? profileImage,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return AppUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      cnic: cnic ?? this.cnic,
      role: role ?? this.role,
      address: address ?? this.address,
      profileImage: profileImage ?? this.profileImage,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
