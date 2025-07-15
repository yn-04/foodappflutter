// models/my_user.dart (Updated with phone number)
import 'package:cloud_firestore/cloud_firestore.dart';

class MyUser {
  final String firstName;
  final String lastName;
  final String email;
  final String phoneNumber; // เพิ่มฟิลด์เบอร์โทร
  final String gender;
  final double height;
  final double weight;
  final String allergies;
  final String fullName;
  final DateTime birthDate;
  final DateTime createdAt;
  final bool profileCompleted;

  MyUser({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phoneNumber, // เพิ่ม required phoneNumber
    required this.gender,
    required this.height,
    required this.weight,
    required this.allergies,
    required this.fullName,
    required this.birthDate,
    required this.createdAt,
    required this.profileCompleted,
  });

  // Getter สำหรับชื่อเต็ม
  String get generatedFullName => '$firstName $lastName';

  // สร้าง MyUser จาก Firebase Document
  factory MyUser.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

    return MyUser(
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      email: data['email'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '', // เพิ่ม phoneNumber
      gender: data['gender'] ?? '',
      height: (data['height'] ?? 0).toDouble(),
      weight: (data['weight'] ?? 0).toDouble(),
      allergies: data['allergies'] ?? '',
      fullName: data['fullName'] ?? '',
      birthDate: (data['birthDate'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      profileCompleted: data['profileCompleted'] ?? false,
    );
  }

  // แปลงเป็น Map สำหรับส่งไปยัง Firebase
  Map<String, dynamic> toFirestore() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phoneNumber': phoneNumber, // เพิ่ม phoneNumber
      'gender': gender,
      'height': height,
      'weight': weight,
      'allergies': allergies,
      'fullName': fullName,
      'birthDate': Timestamp.fromDate(birthDate),
      'createdAt': Timestamp.fromDate(createdAt),
      'profileCompleted': profileCompleted,
    };
  }

  // คำนวณอายุจากวันเกิด
  int get age {
    DateTime now = DateTime.now();
    int age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  // คำนวณ BMI
  double get bmi {
    if (height == 0 || weight == 0) return 0;
    double heightInMeters = height / 100;
    return weight / (heightInMeters * heightInMeters);
  }

  // หมวดหมู่ BMI
  String get bmiCategory {
    double bmiValue = bmi;
    if (bmiValue < 18.5) return 'น้ำหนักน้อย';
    if (bmiValue < 25) return 'ปกติ';
    if (bmiValue < 30) return 'น้ำหนักเกิน';
    return 'อ้วน';
  }

  // Helper method สำหรับ format เบอร์โทร
  String get formattedPhoneNumber {
    if (phoneNumber.isEmpty) return '';

    // ลบอักขระที่ไม่ใช่ตัวเลข
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

    // Format เบอร์โทรไทย
    if (cleaned.length == 10 && cleaned.startsWith('0')) {
      return '${cleaned.substring(0, 3)}-${cleaned.substring(3, 6)}-${cleaned.substring(6)}';
    } else if (cleaned.length == 9 && !cleaned.startsWith('0')) {
      return '0${cleaned.substring(0, 2)}-${cleaned.substring(2, 5)}-${cleaned.substring(5)}';
    }

    return phoneNumber; // Return original if can't format
  }

  // Validation สำหรับเบอร์โทร
  bool get isValidPhoneNumber {
    if (phoneNumber.isEmpty) return true; // อนุญาตให้ว่างได้

    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');

    // เบอร์โทรไทย: 10 หลัก เริ่มด้วย 0 หรือ 9 หลัก ไม่เริ่มด้วย 0
    return (cleaned.length == 10 && cleaned.startsWith('0')) ||
        (cleaned.length == 9 && !cleaned.startsWith('0'));
  }

  @override
  String toString() {
    return 'MyUser{fullName: $fullName, email: $email, phone: $phoneNumber, age: $age}';
  }

  // Helper method สำหรับสร้าง copy ของ object พร้อมการเปลี่ยนแปลงบางฟิลด์
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
    );
  }
}
