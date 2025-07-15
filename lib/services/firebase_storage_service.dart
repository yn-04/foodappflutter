// firebase_storage_service.dart - บริการจัดการ Firebase Storage
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// บริการสำหรับจัดการ Firebase Storage และ User Profile
class FirebaseStorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ตรวจสอบการเชื่อมต่อ Firebase Storage
  static Future<bool> checkConnection() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('DEBUG: User not authenticated');
        return false;
      }

      print('DEBUG: Storage bucket: ${_storage.bucket}');
      print('DEBUG: User authenticated: ${user.uid}');

      return true;
    } catch (e) {
      print('DEBUG: Storage connection check failed: $e');
      return false;
    }
  }

  /// ทดสอบการอัปโหลดไฟล์ง่ายๆ
  static Future<void> testConnection() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ User not logged in');
        return;
      }

      print('=== TESTING STORAGE CONNECTION ===');
      print('✅ User authenticated: ${user.uid}');
      print('✅ User email: ${user.email}');

      print('✅ Storage instance created');
      print('✅ Storage bucket: ${_storage.bucket}');

      // ทดสอบสร้าง reference
      final testRef = _storage.ref().child(
        'test_${DateTime.now().millisecondsSinceEpoch}.txt',
      );
      print('✅ Reference created: ${testRef.fullPath}');

      // ทดสอบอัปโหลดข้อความ
      final testData = 'Hello Firebase Storage!';
      await testRef.putString(testData);
      print('✅ String upload successful');

      // ทดสอบดาวน์โหลด URL
      final downloadURL = await testRef.getDownloadURL();
      print('✅ Download URL: $downloadURL');

      // ลบไฟล์ทดสอบ
      await testRef.delete();
      print('✅ Test file deleted');

      print('🎉 Storage connection test PASSED!');
    } catch (e) {
      print('❌ Storage connection test FAILED: $e');
      rethrow;
    }
  }

  /// อัปโหลดรูปภาพโปรไฟล์
  static Future<String> uploadProfileImage({
    required File imageFile,
    required String userId,
  }) async {
    try {
      // ตรวจสอบการ Login
      final user = _auth.currentUser;
      if (user == null) {
        throw StorageException('ผู้ใช้ไม่ได้ล็อกอิน');
      }

      // ตรวจสอบไฟล์
      if (!imageFile.existsSync()) {
        throw StorageException('ไม่พบไฟล์รูปภาพ');
      }

      final fileSize = imageFile.lengthSync();
      print('DEBUG: Starting image upload...');
      print('DEBUG: User UID: ${user.uid}');
      print('DEBUG: File size: $fileSize bytes');

      // ตรวจสอบขนาดไฟล์ (5MB = 5 * 1024 * 1024 bytes)
      if (fileSize > 5 * 1024 * 1024) {
        throw StorageException('ไฟล์ใหญ่เกินไป (เกิน 5MB)');
      }

      // สร้างชื่อไฟล์ที่ unique
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'profile_${userId}_$timestamp.jpg';

      // สร้าง Storage Reference
      final storageRef = _storage
          .ref()
          .child('users')
          .child(userId)
          .child(fileName);

      print('DEBUG: Upload path: ${storageRef.fullPath}');

      // ลบไฟล์เก่าถ้ามี (ไม่บังคับ)
      await _deleteOldProfileImages(userId);

      // อัปโหลดไฟล์
      print('DEBUG: Starting upload...');
      final uploadTask = await storageRef.putFile(
        imageFile,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'uploaded_by': userId,
            'uploaded_at': DateTime.now().toIso8601String(),
            'file_size': fileSize.toString(),
            'upload_type': 'profile_image',
          },
        ),
      );

      // ดึง Download URL
      final downloadURL = await uploadTask.ref.getDownloadURL();
      print('DEBUG: Upload successful, URL: $downloadURL');

      return downloadURL;
    } on FirebaseException catch (e) {
      print('Firebase Storage Error: ${e.code} - ${e.message}');
      throw StorageException(_getFirebaseErrorMessage(e));
    } catch (e) {
      print('General Upload Error: $e');
      throw StorageException('ไม่สามารถอัปโหลดรูปภาพได้: $e');
    }
  }

  /// ลบรูปภาพโปรไฟล์เก่า
  static Future<void> _deleteOldProfileImages(String userId) async {
    try {
      final userRef = _storage.ref().child('users').child(userId);
      final listResult = await userRef.listAll();

      for (final item in listResult.items) {
        if (item.name.startsWith('profile_')) {
          await item.delete();
          print('DEBUG: Deleted old file: ${item.name}');
        }
      }
    } catch (e) {
      print('DEBUG: Could not delete old files (this is normal): $e');
      // ไม่ throw error เพราะไม่สำคัญมาก
    }
  }

  /// อัปเดตโปรไฟล์ผู้ใช้ (Auth + Firestore)
  static Future<void> updateUserProfile({
    required String displayName,
    String? photoURL,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw ProfileException('ไม่พบผู้ใช้');
      }

      print('DEBUG: Updating user profile...');

      // อัปเดต Firebase Auth Profile
      await user.updateDisplayName(displayName);
      if (photoURL != null) {
        await user.updatePhotoURL(photoURL);
      }

      // บันทึกข้อมูลใน Firestore
      await _updateFirestoreProfile(
        uid: user.uid,
        displayName: displayName,
        photoURL: photoURL,
        email: user.email,
      );

      // Reload user data
      await user.reload();
      print('DEBUG: Profile update completed');
    } catch (e) {
      print('Error updating profile: $e');
      rethrow;
    }
  }

  /// อัปเดตข้อมูลใน Firestore
  static Future<void> _updateFirestoreProfile({
    required String uid,
    required String displayName,
    String? photoURL,
    String? email,
  }) async {
    try {
      final docRef = _firestore.collection('users').doc(uid);
      final docSnapshot = await docRef.get();

      final data = {
        'displayName': displayName,
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
      };

      if (photoURL != null) {
        data['photoURL'] = photoURL;
        data['hasCustomPhoto'] = true;
      }

      if (docSnapshot.exists) {
        await docRef.update(data);
        print('DEBUG: Firestore document updated');
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        data['profileVersion'] = 1;
        await docRef.set(data);
        print('DEBUG: New Firestore document created');
      }
    } catch (e) {
      print('Error updating Firestore: $e');
      throw ProfileException('ไม่สามารถบันทึกข้อมูลได้');
    }
  }

  /// อัปเดตโปรไฟล์แบบครบวงจร (รูป + ข้อมูล)
  static Future<void> updateCompleteProfile({
    required String displayName,
    File? imageFile,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw ProfileException('ไม่พบผู้ใช้');
      }

      String? downloadURL;

      // อัปโหลดรูปภาพถ้ามี
      if (imageFile != null) {
        downloadURL = await uploadProfileImage(
          imageFile: imageFile,
          userId: user.uid,
        );
      }

      // อัปเดตโปรไฟล์
      await updateUserProfile(displayName: displayName, photoURL: downloadURL);
    } catch (e) {
      print('Error in complete profile update: $e');
      rethrow;
    }
  }

  /// แปลความหมาย Firebase Error
  static String _getFirebaseErrorMessage(FirebaseException e) {
    switch (e.code) {
      case 'storage/unauthorized':
        return 'ไม่มีสิทธิ์อัปโหลดไฟล์ - ตรวจสอบ Storage Rules';
      case 'storage/object-not-found':
        return 'ไม่สามารถสร้างไฟล์ได้ - ตรวจสอบ Storage Rules';
      case 'storage/bucket-not-found':
        return 'ไม่พบ Storage Bucket - ตรวจสอบการตั้งค่าโปรเจค';
      case 'storage/quota-exceeded':
        return 'พื้นที่จัดเก็บเต็ม';
      case 'storage/unauthenticated':
        return 'กรุณาเข้าสู่ระบบใหม่';
      case 'storage/retry-limit-exceeded':
        return 'อัปโหลดล้มเหลว กรุณาลองใหม่';
      case 'storage/invalid-format':
        return 'รูปแบบไฟล์ไม่ถูกต้อง';
      default:
        return 'เกิดข้อผิดพลาดในการอัปโหลด: ${e.message}';
    }
  }

  /// ตรวจสอบความถูกต้องของรูปภาพ
  static bool isValidImage(File imageFile) {
    try {
      if (!imageFile.existsSync()) return false;

      final fileSize = imageFile.lengthSync();
      final fileSizeInMB = fileSize / (1024 * 1024);

      // ตรวจสอบขนาดไฟล์ (ไม่เกิน 5MB)
      if (fileSizeInMB > 5.0) return false;

      // ตรวจสอบนามสกุลไฟล์
      final fileName = imageFile.path.toLowerCase();
      final validExtensions = ['.jpg', '.jpeg', '.png'];

      return validExtensions.any((ext) => fileName.endsWith(ext));
    } catch (e) {
      print('Error validating image: $e');
      return false;
    }
  }
}

/// Custom Exception สำหรับ Storage
class StorageException implements Exception {
  final String message;
  StorageException(this.message);

  @override
  String toString() => message;
}

/// Custom Exception สำหรับ Profile
class ProfileException implements Exception {
  final String message;
  ProfileException(this.message);

  @override
  String toString() => message;
}
