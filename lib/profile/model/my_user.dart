// lib/profile/my_user.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class MyUser {
  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber;
  final String gender;
  final double height;
  final double weight;
  final String allergies;
  final String fullName;
  final DateTime birthDate;
  final DateTime createdAt;
  final bool profileCompleted;

  // NEW: optional username (เก็บไว้ใช้เป็น @handle/แสดงผลสั้นๆ)
  final String? username;

  MyUser({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phoneNumber,
    required this.gender,
    required this.height,
    required this.weight,
    required this.allergies,
    required this.fullName,
    required this.birthDate,
    required this.createdAt,
    required this.profileCompleted,
    this.username,
  });

  // แสดงชื่อสำหรับ UI (เอาไว้ใช้ใน header)
  String displayNamePref({String? fallbackEmail}) {
    if (firstName.trim().isNotEmpty) return firstName.trim();
    if (fullName.trim().isNotEmpty) return fullName.trim();
    if ((username ?? '').trim().isNotEmpty) return username!.trim();
    if (fallbackEmail != null && fallbackEmail.contains('@')) {
      return fallbackEmail.split('@').first;
    }
    return 'ผู้ใช้';
  }

  // sanitize ชื่อให้เป็น username
  static String toUsername(String source) {
    final s = source.trim().toLowerCase();
    final only = s.replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    return only.isEmpty ? 'user' : only;
  }

  factory MyUser.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});
    // ป้องกัน null timestamp
    final Timestamp? birthTs = data['birthDate'];
    final Timestamp? createdTs = data['createdAt'];

    return MyUser(
      firstName: (data['firstName'] ?? '') as String,
      lastName: (data['lastName'] ?? '') as String,
      email: (data['email'] ?? '') as String,
      phoneNumber: (data['phoneNumber'] ?? '') as String,
      gender: (data['gender'] ?? '') as String,
      height: (data['height'] ?? 0).toDouble(),
      weight: (data['weight'] ?? 0).toDouble(),
      allergies: (data['allergies'] ?? '') as String,
      fullName: (data['fullName'] ?? '') as String,
      birthDate: birthTs != null ? birthTs.toDate() : DateTime(2000, 1, 1),
      createdAt: createdTs != null ? createdTs.toDate() : DateTime.now(),
      profileCompleted: (data['profileCompleted'] ?? false) as bool,
      username: data['username'] as String?, // NEW
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phoneNumber': phoneNumber,
      'gender': gender,
      'height': height,
      'weight': weight,
      'allergies': allergies,
      'fullName': fullName,
      'birthDate': Timestamp.fromDate(birthDate),
      'createdAt': Timestamp.fromDate(createdAt),
      'profileCompleted': profileCompleted,
      if (username != null) 'username': username, // NEW
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
    String? firstName,
    String? lastName,
    String? email,
    String? phoneNumber,
    String? gender,
    double? height,
    double? weight,
    String? allergies,
    String? fullName,
    DateTime? birthDate,
    DateTime? createdAt,
    bool? profileCompleted,
    String? username, // NEW
  }) {
    return MyUser(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      gender: gender ?? this.gender,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      allergies: allergies ?? this.allergies,
      fullName: fullName ?? this.fullName,
      birthDate: birthDate ?? this.birthDate,
      createdAt: createdAt ?? this.createdAt,
      profileCompleted: profileCompleted ?? this.profileCompleted,
      username: username ?? this.username,
    );
  }
}
