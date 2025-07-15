// services/user_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app/profile/my_user.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'users';

  /// Get user by ID
  Future<MyUser?> getUserById(String userId) async {
    try {
      print('Fetching user data for UID: $userId');

      final doc = await _firestore.collection(_collection).doc(userId).get();

      if (doc.exists) {
        print('User document found');
        return MyUser.fromFirestore(doc);
      } else {
        print('User document not found');
        return null;
      }
    } catch (e) {
      print('Error getting user: $e');
      rethrow; // Re-throw to let caller handle the error
    }
  }

  /// Get current logged-in user
  Future<MyUser?> getCurrentUser() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No authenticated user found');
        return null;
      }

      return await getUserById(currentUser.uid);
    } catch (e) {
      print('Error getting current user: $e');
      return null;
    }
  }

  /// Create a new user
  Future<bool> createUser(String userId, MyUser user) async {
    try {
      print('Creating user with UID: $userId');

      final userData = user.toFirestore();
      userData['createdAt'] = FieldValue.serverTimestamp();

      await _firestore.collection(_collection).doc(userId).set(userData);

      print('User created successfully');
      return true;
    } catch (e) {
      print('Error creating user: $e');
      rethrow;
    }
  }

  /// Update user data
  Future<bool> updateUser(String userId, MyUser user) async {
    try {
      print('Updating user data for UID: $userId');

      final userData = user.toFirestore();
      userData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection(_collection).doc(userId).update(userData);

      print('User data updated successfully');
      return true;
    } catch (e) {
      print('Error updating user: $e');
      rethrow;
    }
  }

  /// Update specific user fields
  Future<bool> updateUserFields(
    String userId,
    Map<String, dynamic> fields,
  ) async {
    try {
      print('Updating user fields for UID: $userId');

      final updateData = Map<String, dynamic>.from(fields);
      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection(_collection).doc(userId).update(updateData);

      print('User fields updated successfully');
      return true;
    } catch (e) {
      print('Error updating user fields: $e');
      rethrow;
    }
  }

  /// Update user health data
  Future<bool> updateHealthData(
    String userId, {
    double? height,
    double? weight,
    String? allergies,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (height != null) updateData['height'] = height;
      if (weight != null) updateData['weight'] = weight;
      if (allergies != null) updateData['allergies'] = allergies;

      if (updateData.isEmpty) return true; // Nothing to update

      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection(_collection).doc(userId).update(updateData);

      print('Health data updated successfully');
      return true;
    } catch (e) {
      print('Error updating health data: $e');
      rethrow;
    }
  }

  /// Update user contact info
  Future<bool> updateContactInfo(
    String userId, {
    String? phoneNumber,
    String? email,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (phoneNumber != null) updateData['phoneNumber'] = phoneNumber;
      if (email != null) updateData['email'] = email;

      if (updateData.isEmpty) return true; // Nothing to update

      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection(_collection).doc(userId).update(updateData);

      print('Contact info updated successfully');
      return true;
    } catch (e) {
      print('Error updating contact info: $e');
      rethrow;
    }
  }

  /// Mark profile as completed
  Future<bool> markProfileCompleted(String userId) async {
    try {
      await _firestore.collection(_collection).doc(userId).update({
        'profileCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('Profile marked as completed');
      return true;
    } catch (e) {
      print('Error marking profile as completed: $e');
      return false;
    }
  }

  /// Check if user exists
  Future<bool> userExists(String userId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(userId).get();
      return doc.exists;
    } catch (e) {
      print('Error checking if user exists: $e');
      return false;
    }
  }

  /// Delete user data (for account deletion)
  Future<bool> deleteUser(String userId) async {
    try {
      print('Deleting user data for UID: $userId');

      await _firestore.collection(_collection).doc(userId).delete();

      print('User data deleted successfully');
      return true;
    } catch (e) {
      print('Error deleting user: $e');
      rethrow;
    }
  }

  /// Get users by email (for admin purposes)
  Future<List<MyUser>> getUsersByEmail(String email) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collection)
          .where('email', isEqualTo: email)
          .get();

      return querySnapshot.docs
          .map((doc) => MyUser.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Error getting users by email: $e');
      return [];
    }
  }

  /// Search users by name
  Future<List<MyUser>> searchUsersByName(String name) async {
    try {
      final querySnapshot = await _firestore
          .collection(_collection)
          .where('fullName', isGreaterThanOrEqualTo: name)
          .where('fullName', isLessThanOrEqualTo: '$name\uf8ff')
          .limit(20)
          .get();

      return querySnapshot.docs
          .map((doc) => MyUser.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('Error searching users by name: $e');
      return [];
    }
  }

  /// Get user statistics
  Future<Map<String, dynamic>> getUserStats(String userId) async {
    try {
      final user = await getUserById(userId);
      if (user == null) return {};

      return {
        'age': user.age,
        'bmi': user.bmi,
        'bmiCategory': user.bmiCategory,
        'profileCompleted': user.profileCompleted,
        'hasAllergies': user.allergies.isNotEmpty,
        'hasPhoneNumber': user.phoneNumber.isNotEmpty,
        'accountAge': DateTime.now().difference(user.createdAt).inDays,
      };
    } catch (e) {
      print('Error getting user stats: $e');
      return {};
    }
  }

  /// Validate user data
  Map<String, String> validateUserData(MyUser user) {
    final errors = <String, String>{};

    // Validate required fields
    if (user.firstName.isEmpty) {
      errors['firstName'] = 'กรุณากรอกชื่อ';
    }
    if (user.lastName.isEmpty) {
      errors['lastName'] = 'กรุณากรอกนามสกุล';
    }
    if (user.email.isEmpty) {
      errors['email'] = 'กรุณากรอกอีเมล';
    }

    // Validate email format
    if (user.email.isNotEmpty &&
        !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(user.email)) {
      errors['email'] = 'รูปแบบอีเมลไม่ถูกต้อง';
    }

    // Validate phone number
    if (user.phoneNumber.isNotEmpty && !user.isValidPhoneNumber) {
      errors['phoneNumber'] = 'รูปแบบเบอร์โทรไม่ถูกต้อง';
    }

    // Validate health data
    if (user.height < 0 || user.height > 300) {
      errors['height'] = 'ส่วนสูงต้องอยู่ระหว่าง 0-300 ซม.';
    }
    if (user.weight < 0 || user.weight > 500) {
      errors['weight'] = 'น้ำหนักต้องอยู่ระหว่าง 0-500 กก.';
    }

    // Validate age
    final age = user.age;
    if (age < 0 || age > 150) {
      errors['birthDate'] = 'อายุไม่ถูกต้อง';
    }

    return errors;
  }

  /// Get user creation statistics
  Future<Map<String, int>> getUserCreationStats() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final startOfWeek = startOfDay.subtract(Duration(days: now.weekday - 1));
      final startOfMonth = DateTime(now.year, now.month, 1);

      // Today's registrations
      final todayQuery = await _firestore
          .collection(_collection)
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .get();

      // This week's registrations
      final weekQuery = await _firestore
          .collection(_collection)
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfWeek),
          )
          .get();

      // This month's registrations
      final monthQuery = await _firestore
          .collection(_collection)
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth),
          )
          .get();

      return {
        'today': todayQuery.docs.length,
        'thisWeek': weekQuery.docs.length,
        'thisMonth': monthQuery.docs.length,
      };
    } catch (e) {
      print('Error getting user creation stats: $e');
      return {'today': 0, 'thisWeek': 0, 'thisMonth': 0};
    }
  }

  /// Batch delete users (for admin use)
  Future<bool> batchDeleteUsers(List<String> userIds) async {
    try {
      final batch = _firestore.batch();

      for (String userId in userIds) {
        final userRef = _firestore.collection(_collection).doc(userId);
        batch.delete(userRef);
      }

      await batch.commit();
      print('Batch deleted ${userIds.length} users');
      return true;
    } catch (e) {
      print('Error batch deleting users: $e');
      return false;
    }
  }
}
