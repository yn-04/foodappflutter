// lib/models/user_profile.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String email;
  final String firstName;
  final String lastName;
  final String fullName;
  final String phoneNumber;
  final String gender;
  final Timestamp? birthDate; // ค.ศ. เป็น Timestamp
  final double? weight; // กก.
  final double? height; // ซม.
  final String allergies; // สตริงธรรมดา
  final Timestamp? createdAt;
  final bool profileCompleted;

  UserProfile({
    required this.uid,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.phoneNumber,
    required this.gender,
    this.birthDate,
    this.weight,
    this.height,
    required this.allergies,
    this.createdAt,
    required this.profileCompleted,
  });

  factory UserProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return UserProfile(
      uid: doc.id,
      email: (d['email'] ?? '') as String,
      firstName: (d['firstName'] ?? '') as String,
      lastName: (d['lastName'] ?? '') as String,
      fullName: (d['fullName'] ?? '') as String,
      phoneNumber: (d['phoneNumber'] ?? '') as String,
      gender: (d['gender'] ?? '') as String,
      birthDate: d['birthDate'] as Timestamp?,
      weight: d['weight'] == null ? null : (d['weight'] as num).toDouble(),
      height: d['height'] == null ? null : (d['height'] as num).toDouble(),
      allergies: (d['allergies'] ?? '') as String,
      createdAt: d['createdAt'] as Timestamp?,
      profileCompleted: (d['profileCompleted'] ?? false) as bool,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'firstName': firstName,
      'lastName': lastName,
      'fullName': fullName,
      'phoneNumber': phoneNumber,
      'gender': gender,
      'birthDate': birthDate,
      'weight': weight,
      'height': height,
      'allergies': allergies,
      'createdAt': createdAt,
      'profileCompleted': profileCompleted,
    };
  }
}
