// lib/profile/my_user.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MyUser {
  final String displayName;
  final String email;
  final String phoneNumber;
  final String gender;
  final double height;
  final double weight;
  final String allergies;
  final DateTime birthDate;
  final DateTime createdAt;
  final bool profileCompleted;

  MyUser({
    required this.displayName,
    required this.email,
    required this.phoneNumber,
    required this.gender,
    required this.height,
    required this.weight,
    required this.allergies,
    required this.birthDate,
    required this.createdAt,
    required this.profileCompleted,
  });

  // แสดงชื่อสำหรับ UI (เอาไว้ใช้ใน header)
  String displayNamePref({String? fallbackEmail}) {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (fallbackEmail != null && fallbackEmail.contains('@')) {
      return fallbackEmail.split('@').first;
    }
    return 'ผู้ใช้';
  }

  factory MyUser.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});

    double _readDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String)
        return double.tryParse(value.replaceAll(',', '.')) ?? 0;
      return 0;
    }

    Timestamp? _readTimestamp(dynamic value) {
      if (value is Timestamp) return value;
      if (value is DateTime) return Timestamp.fromDate(value);
      return null;
    }

    String _readString(dynamic value) {
      if (value == null) return '';
      if (value is String) return value;
      return value.toString();
    }

    String _resolveAllergies(dynamic value) {
      if (value is String) return value;
      if (value is Iterable) {
        return value.whereType<String>().join(', ');
      }
      return '';
    }

    bool _readBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) return value.toLowerCase() == 'true';
      return false;
    }

    final Timestamp? birthTs = _readTimestamp(data['birthDate']);
    final Timestamp? createdTs = _readTimestamp(data['createdAt']);
    final String resolvedDisplay = _readString(data['displayName']).trim();

    return MyUser(
      displayName: resolvedDisplay,
      email: _readString(data['email']),
      phoneNumber: _readString(data['phoneNumber']),
      gender: _readString(data['gender']),
      height: _readDouble(data['height']),
      weight: _readDouble(data['weight']),
      allergies: _resolveAllergies(data['allergies']),
      birthDate: birthTs != null ? birthTs.toDate() : DateTime(2000, 1, 1),
      createdAt: createdTs != null ? createdTs.toDate() : DateTime.now(),
      profileCompleted: _readBool(data['profileCompleted']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'email': email,
      'phoneNumber': phoneNumber,
      'gender': gender,
      'height': height,
      'weight': weight,
      'allergies': allergies,
      'birthDate': Timestamp.fromDate(birthDate),
      'createdAt': Timestamp.fromDate(createdAt),
      'profileCompleted': profileCompleted,
    };
  }

  // เดิมคงไว้ทั้งหมด…
  int get age {
    /* ...เหมือนเดิม... */
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  double get bmi {
    if (height == 0 || weight == 0) return 0;
    final m = height / 100;
    return weight / (m * m);
  }

  String get bmiCategory {
    final v = bmi;
    if (v < 18.5) return 'น้ำหนักน้อย';
    if (v < 25) return 'ปกติ';
    if (v < 30) return 'น้ำหนักเกิน';
    return 'อ้วน';
  }

  String get formattedPhoneNumber {
    /* ...เหมือนเดิม... */
    if (phoneNumber.isEmpty) return '';
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.length == 10 && cleaned.startsWith('0')) {
      return '${cleaned.substring(0, 3)}-${cleaned.substring(3, 6)}-${cleaned.substring(6)}';
    } else if (cleaned.length == 9 && !cleaned.startsWith('0')) {
      return '0${cleaned.substring(0, 2)}-${cleaned.substring(2, 5)}-${cleaned.substring(5)}';
    }
    return phoneNumber;
  }

  bool get isValidPhoneNumber {
    /* ...เหมือนเดิม... */
    if (phoneNumber.isEmpty) return true;
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    return (cleaned.length == 10 && cleaned.startsWith('0')) ||
        (cleaned.length == 9 && !cleaned.startsWith('0'));
  }

  MyUser copyWith({
    String? displayName,
    String? email,
    String? phoneNumber,
    String? gender,
    double? height,
    double? weight,
    String? allergies,
    DateTime? birthDate,
    DateTime? createdAt,
    bool? profileCompleted,
  }) {
    return MyUser(
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      gender: gender ?? this.gender,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      allergies: allergies ?? this.allergies,
      birthDate: birthDate ?? this.birthDate,
      createdAt: createdAt ?? this.createdAt,
      profileCompleted: profileCompleted ?? this.profileCompleted,
    );
  }
}
