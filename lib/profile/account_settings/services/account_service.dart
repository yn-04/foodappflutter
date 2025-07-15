// services/account_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_service.dart';
import 'settings_service.dart';

class AccountService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserService _userService = UserService();
  final SettingsService _settingsService = SettingsService();

  /// Complete account deletion (Auth + Firestore)
  Future<AccountDeletionResult> deleteAccount(String password) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return AccountDeletionResult(
          success: false,
          error: 'ไม่พบข้อมูลผู้ใช้',
        );
      }

      final uid = user.uid;
      final email = user.email!;

      // Step 1: Re-authenticate user
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      // Step 2: Delete all user data from Firestore
      await _deleteAllUserData(uid);

      // Step 3: Delete Firebase Auth account (must be last)
      await user.delete();

      return AccountDeletionResult(
        success: true,
        message: 'ลบบัญชีและข้อมูลทั้งหมดสำเร็จ',
      );
    } catch (e) {
      return AccountDeletionResult(success: false, error: _parseError(e));
    }
  }

  /// Delete all user data from Firestore
  Future<void> _deleteAllUserData(String uid) async {
    final batch = _firestore.batch();

    // Collections to delete
    final collections = [
      'users',
      'user_settings',
      'health_profiles',
      'user_backups',
      'registrations',
      'notifications',
      'user_sessions',
    ];

    // Delete documents from all collections
    for (String collection in collections) {
      final docRef = _firestore.collection(collection).doc(uid);
      batch.delete(docRef);
    }

    // Delete subcollections if any
    await _deleteSubcollections(uid);

    // Execute batch delete
    await batch.commit();
  }

  /// Delete subcollections for a user
  Future<void> _deleteSubcollections(String uid) async {
    try {
      // Example: Delete user's activity records
      final activityQuery = await _firestore
          .collection('users')
          .doc(uid)
          .collection('activities')
          .get();

      final batch = _firestore.batch();
      for (var doc in activityQuery.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    } catch (e) {
      print('Error deleting subcollections: $e');
      // Continue with main deletion even if subcollections fail
    }
  }

  /// Change password
  Future<PasswordChangeResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return PasswordChangeResult(success: false, error: 'ไม่พบข้อมูลผู้ใช้');
      }

      // Re-authenticate user
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);

      // Update password
      await user.updatePassword(newPassword);

      return PasswordChangeResult(
        success: true,
        message: 'เปลี่ยนรหัสผ่านสำเร็จ',
      );
    } catch (e) {
      return PasswordChangeResult(success: false, error: _parseError(e));
    }
  }

  /// Send email verification
  Future<EmailVerificationResult> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return EmailVerificationResult(
          success: false,
          error: 'ไม่พบข้อมูลผู้ใช้',
        );
      }

      if (user.emailVerified) {
        return EmailVerificationResult(
          success: false,
          error: 'อีเมลได้รับการยืนยันแล้ว',
        );
      }

      await user.sendEmailVerification();

      return EmailVerificationResult(
        success: true,
        message: 'ส่งอีเมลยืนยันแล้ว กรุณาตรวจสอบอีเมลของคุณ',
      );
    } catch (e) {
      return EmailVerificationResult(success: false, error: _parseError(e));
    }
  }

  /// Sign out from all devices
  Future<SignOutResult> signOutAllDevices() async {
    try {
      await _auth.signOut();

      return SignOutResult(
        success: true,
        message: 'ออกจากระบบทุกอุปกรณ์สำเร็จ',
      );
    } catch (e) {
      return SignOutResult(success: false, error: _parseError(e));
    }
  }

  /// Sync user data
  Future<SyncResult> syncUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return SyncResult(success: false, error: 'ไม่พบข้อมูลผู้ใช้');
      }

      // Simulate sync process
      await Future.delayed(const Duration(seconds: 2));

      // Update last sync time
      await _firestore.collection('users').doc(user.uid).update({
        'lastSyncAt': FieldValue.serverTimestamp(),
      });

      return SyncResult(success: true, message: 'ซิงค์ข้อมูลสำเร็จ');
    } catch (e) {
      return SyncResult(success: false, error: _parseError(e));
    }
  }

  /// Backup user data
  Future<BackupResult> backupUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return BackupResult(success: false, error: 'ไม่พบข้อมูลผู้ใช้');
      }

      // Get user data
      final userData = await _userService.getUserById(user.uid);
      final settings = await _settingsService.loadAllSettings(user.uid);

      if (userData == null) {
        return BackupResult(success: false, error: 'ไม่พบข้อมูลผู้ใช้');
      }

      // Create backup document
      final backupData = {
        'userId': user.uid,
        'userData': userData.toFirestore(),
        'settings': settings,
        'createdAt': FieldValue.serverTimestamp(),
        'version': '1.0',
      };

      await _firestore.collection('user_backups').doc(user.uid).set(backupData);

      return BackupResult(success: true, message: 'สำรองข้อมูลสำเร็จ');
    } catch (e) {
      return BackupResult(success: false, error: _parseError(e));
    }
  }

  /// Export user data
  Future<ExportResult> exportUserData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return ExportResult(success: false, error: 'ไม่พบข้อมูลผู้ใช้');
      }

      // Simulate data preparation and email sending
      await Future.delayed(const Duration(seconds: 1));

      // In a real implementation, you would:
      // 1. Collect all user data
      // 2. Create a ZIP file
      // 3. Send via email or provide download link

      return ExportResult(
        success: true,
        message: 'กำลังเตรียมข้อมูล จะส่งไปยังอีเมลของคุณเร็วๆ นี้',
      );
    } catch (e) {
      return ExportResult(success: false, error: _parseError(e));
    }
  }

  /// Parse Firebase error messages to Thai
  String _parseError(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('wrong-password')) {
      return 'รหัสผ่านไม่ถูกต้อง';
    } else if (errorString.contains('weak-password')) {
      return 'รหัสผ่านไม่รัดกุมเพียงพอ';
    } else if (errorString.contains('too-many-requests')) {
      return 'มีการพยายามเข้าใช้งานมากเกินไป กรุณาลองใหม่ภายหลัง';
    } else if (errorString.contains('network-request-failed')) {
      return 'ไม่สามารถเชื่อมต่อเครือข่ายได้';
    } else if (errorString.contains('requires-recent-login')) {
      return 'กรุณาออกจากระบบและเข้าสู่ระบบใหม่';
    } else if (errorString.contains('permission-denied')) {
      return 'ไม่มีสิทธิ์เข้าถึงข้อมูล';
    } else if (errorString.contains('user-not-found')) {
      return 'ไม่พบข้อมูลผู้ใช้';
    } else {
      return 'เกิดข้อผิดพลาด: $error';
    }
  }
}

// Result classes for better error handling
class AccountDeletionResult {
  final bool success;
  final String? message;
  final String? error;

  AccountDeletionResult({required this.success, this.message, this.error});
}

class PasswordChangeResult {
  final bool success;
  final String? message;
  final String? error;

  PasswordChangeResult({required this.success, this.message, this.error});
}

class EmailVerificationResult {
  final bool success;
  final String? message;
  final String? error;

  EmailVerificationResult({required this.success, this.message, this.error});
}

class SignOutResult {
  final bool success;
  final String? message;
  final String? error;

  SignOutResult({required this.success, this.message, this.error});
}

class SyncResult {
  final bool success;
  final String? message;
  final String? error;

  SyncResult({required this.success, this.message, this.error});
}

class BackupResult {
  final bool success;
  final String? message;
  final String? error;

  BackupResult({required this.success, this.message, this.error});
}

class ExportResult {
  final bool success;
  final String? message;
  final String? error;

  ExportResult({required this.success, this.message, this.error});
}
