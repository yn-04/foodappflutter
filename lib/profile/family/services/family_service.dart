// screens/family/services/family_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';

class FamilyService {
  final String familyId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  FamilyService(this.familyId);

  // Load all family data
  Future<Map<String, dynamic>> loadFamilyData() async {
    try {
      // Load family members
      final membersSnapshot = await _firestore
          .collection('family_members')
          .where('familyId', isEqualTo: familyId)
          .orderBy('addedAt', descending: false)
          .get();

      final members = membersSnapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();

      // Load family stats
      final statsDoc = await _firestore
          .collection('family_stats')
          .doc(familyId)
          .get();

      Map<String, dynamic>? stats;
      if (statsDoc.exists) {
        stats = statsDoc.data();
      } else {
        // Generate initial stats if not exists
        stats = await generateFamilyStats(members);
      }

      return {'members': members, 'stats': stats};
    } catch (e) {
      print('Error loading family data: $e');
      rethrow;
    }
  }

  // Generate family statistics
  Future<Map<String, dynamic>> generateFamilyStats(
    List<Map<String, dynamic>> members,
  ) async {
    try {
      int membersWithWeightGoals = 0;
      int activeMembers = 0;
      int membersWithAllergies = 0;
      double averageAge = 0;
      int totalMembers = members.length + 1; // +1 for owner

      // Calculate statistics from member data
      for (var member in members) {
        if (member['hasWeightGoal'] == true) membersWithWeightGoals++;
        if (member['isActive'] == true) activeMembers++;
        if (member['hasAllergies'] == true) membersWithAllergies++;
        averageAge += (member['age'] ?? 25);
      }

      // Add owner's data (mock data)
      membersWithWeightGoals += 1;
      activeMembers += 1;
      averageAge += 30; // Mock owner age

      averageAge = averageAge / totalMembers;

      final stats = {
        'weightControl': membersWithWeightGoals,
        'exercise': activeMembers,
        'allergies': membersWithAllergies,
        'averageAge': averageAge.round(),
        'totalMembers': totalMembers,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      // Save stats to Firestore
      await _firestore.collection('family_stats').doc(familyId).set(stats);

      return stats;
    } catch (e) {
      print('Error generating family stats: $e');
      rethrow;
    }
  }

  // Add new family member
  Future<void> addFamilyMember({
    required String name,
    required String email,
    required String phone,
    required int? age,
    required String gender,
    required String relationship,
    Map<String, bool>? permissions,
  }) async {
    try {
      await _firestore.collection('family_members').add({
        'familyId': familyId,
        'name': name,
        'email': email,
        'phone': phone,
        'age': age,
        'gender': gender,
        'relationship': relationship,
        'role': 'สมาชิก',
        'addedAt': FieldValue.serverTimestamp(),
        'permissions': permissions ?? _getDefaultPermissions(),
        'isOnline': false,
        'healthStatus': 'ไม่ทราบ',
        'hasWeightGoal': false,
        'isActive': false,
        'hasAllergies': false,
        'bmi': null,
        'allergies': null,
        'medications': null,
        'exerciseStatus': null,
      });

      // Update family stats
      await updateFamilyStats();
    } catch (e) {
      print('Error adding family member: $e');
      rethrow;
    }
  }

  // Update family member
  Future<void> updateFamilyMember({
    required String memberId,
    required String name,
    required String email,
    required String phone,
    required int? age,
    required String gender,
    required String relationship,
  }) async {
    try {
      await _firestore.collection('family_members').doc(memberId).update({
        'name': name,
        'email': email,
        'phone': phone,
        'age': age,
        'gender': gender,
        'relationship': relationship,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error updating family member: $e');
      rethrow;
    }
  }

  // Delete family member
  Future<void> deleteFamilyMember(String memberId) async {
    try {
      await _firestore.collection('family_members').doc(memberId).delete();

      // Update family stats
      await updateFamilyStats();
    } catch (e) {
      print('Error deleting family member: $e');
      rethrow;
    }
  }

  // Update family statistics
  Future<void> updateFamilyStats() async {
    try {
      final data = await loadFamilyData();
      await generateFamilyStats(data['members']);
    } catch (e) {
      print('Error updating family stats: $e');
    }
  }

  // Save default permissions
  Future<void> saveDefaultPermissions(Map<String, bool> permissions) async {
    try {
      await _firestore.collection('family_settings').doc(familyId).set({
        'defaultPermissions': permissions,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving permissions: $e');
      rethrow;
    }
  }

  // Load default permissions
  Future<Map<String, bool>> loadDefaultPermissions() async {
    try {
      final doc = await _firestore
          .collection('family_settings')
          .doc(familyId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        return Map<String, bool>.from(
          data?['defaultPermissions'] ?? _getDefaultPermissions(),
        );
      }

      return _getDefaultPermissions();
    } catch (e) {
      print('Error loading permissions: $e');
      return _getDefaultPermissions();
    }
  }

  // Share invite link
  Future<void> shareInviteLink() async {
    try {
      final inviteCode = 'FAMILY_${familyId.substring(0, 8).toUpperCase()}';
      final inviteLink = 'https://yourapp.com/join/$inviteCode';

      await Share.share(
        'เชิญเข้าร่วมครอบครัวใน Health App\n\nใช้รหัสเชิญ: $inviteCode\nหรือคลิกลิงก์: $inviteLink',
        subject: 'เชิญเข้าร่วมครอบครัว',
      );
    } catch (e) {
      print('Error sharing invite link: $e');
      rethrow;
    }
  }

  // Generate invite QR code data
  String generateInviteQRData() {
    final inviteCode = 'FAMILY_${familyId.substring(0, 8).toUpperCase()}';
    return 'https://yourapp.com/join/$inviteCode';
  }

  // Disband family
  Future<void> disbandFamily(List<Map<String, dynamic>> members) async {
    try {
      // Delete all family members
      for (var member in members) {
        await _firestore
            .collection('family_members')
            .doc(member['id'])
            .delete();
      }

      // Delete family stats and settings
      await _firestore.collection('family_stats').doc(familyId).delete();

      await _firestore.collection('family_settings').doc(familyId).delete();

      // Delete emergency contacts
      await _firestore.collection('emergency_contacts').doc(familyId).delete();
    } catch (e) {
      print('Error disbanding family: $e');
      rethrow;
    }
  }

  // Save family notification settings
  Future<void> saveFamilyNotificationSettings(
    Map<String, bool> settings,
  ) async {
    try {
      await _firestore.collection('family_settings').doc(familyId).set({
        'notificationSettings': settings,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving notification settings: $e');
      rethrow;
    }
  }

  // Load family notification settings
  Future<Map<String, bool>> loadFamilyNotificationSettings() async {
    try {
      final doc = await _firestore
          .collection('family_settings')
          .doc(familyId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        return Map<String, bool>.from(
          data?['notificationSettings'] ?? _getDefaultNotificationSettings(),
        );
      }

      return _getDefaultNotificationSettings();
    } catch (e) {
      print('Error loading notification settings: $e');
      return _getDefaultNotificationSettings();
    }
  }

  // Add emergency contact
  Future<void> addEmergencyContact({
    required String name,
    required String phone,
    required String type,
  }) async {
    try {
      await _firestore
          .collection('emergency_contacts')
          .doc(familyId)
          .collection('contacts')
          .add({
            'name': name,
            'phone': phone,
            'type': type,
            'addedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error adding emergency contact: $e');
      rethrow;
    }
  }

  // Load emergency contacts
  Future<List<Map<String, dynamic>>> loadEmergencyContacts() async {
    try {
      final snapshot = await _firestore
          .collection('emergency_contacts')
          .doc(familyId)
          .collection('contacts')
          .orderBy('addedAt')
          .get();

      return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    } catch (e) {
      print('Error loading emergency contacts: $e');
      return [];
    }
  }

  // Export family data
  Future<Map<String, dynamic>> exportFamilyData() async {
    try {
      final data = await loadFamilyData();
      final emergencyContacts = await loadEmergencyContacts();
      final permissions = await loadDefaultPermissions();
      final notificationSettings = await loadFamilyNotificationSettings();

      return {
        'familyId': familyId,
        'members': data['members'],
        'stats': data['stats'],
        'emergencyContacts': emergencyContacts,
        'defaultPermissions': permissions,
        'notificationSettings': notificationSettings,
        'exportedAt': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('Error exporting family data: $e');
      rethrow;
    }
  }

  // Backup family data
  Future<void> backupFamilyData(List<String> dataTypes) async {
    try {
      final backupData = <String, dynamic>{};

      if (dataTypes.contains('members')) {
        final data = await loadFamilyData();
        backupData['members'] = data['members'];
        backupData['stats'] = data['stats'];
      }

      if (dataTypes.contains('emergencyContacts')) {
        backupData['emergencyContacts'] = await loadEmergencyContacts();
      }

      if (dataTypes.contains('settings')) {
        backupData['permissions'] = await loadDefaultPermissions();
        backupData['notificationSettings'] =
            await loadFamilyNotificationSettings();
      }

      // Save backup to Firestore
      await _firestore
          .collection('family_backups')
          .doc(familyId)
          .collection('backups')
          .add({
            'data': backupData,
            'dataTypes': dataTypes,
            'createdAt': FieldValue.serverTimestamp(),
            'version': '1.0',
          });
    } catch (e) {
      print('Error backing up family data: $e');
      rethrow;
    }
  }

  // Get family insights
  Future<Map<String, dynamic>> getFamilyInsights() async {
    try {
      final data = await loadFamilyData();
      final members = data['members'] as List<Map<String, dynamic>>;

      // Calculate insights
      final insights = <String, dynamic>{};

      // Age distribution
      final ages = members
          .map((m) => m['age'] as int? ?? 0)
          .where((age) => age > 0)
          .toList();
      if (ages.isNotEmpty) {
        insights['averageAge'] = ages.reduce((a, b) => a + b) / ages.length;
        insights['youngestAge'] = ages.reduce((a, b) => a < b ? a : b);
        insights['oldestAge'] = ages.reduce((a, b) => a > b ? a : b);
      }

      // Health status distribution
      final healthStatuses = members
          .map((m) => m['healthStatus'] as String? ?? 'ไม่ทราบ')
          .toList();
      insights['healthStatusCounts'] = <String, int>{};
      for (var status in healthStatuses) {
        insights['healthStatusCounts'][status] =
            (insights['healthStatusCounts'][status] ?? 0) + 1;
      }

      // Activity levels
      final activeCount = members.where((m) => m['isActive'] == true).length;
      insights['activityRate'] = members.isNotEmpty
          ? (activeCount / members.length * 100).round()
          : 0;

      // Recent additions
      final now = DateTime.now();
      final thisMonth = DateTime(now.year, now.month, 1);
      final recentMembers = members.where((m) {
        final addedAt = (m['addedAt'] as Timestamp?)?.toDate();
        return addedAt != null && addedAt.isAfter(thisMonth);
      }).length;
      insights['newMembersThisMonth'] = recentMembers;

      return insights;
    } catch (e) {
      print('Error getting family insights: $e');
      return {};
    }
  }

  // Send health reminders to family members
  Future<void> sendHealthReminders(
    List<String> memberIds,
    String reminderType,
  ) async {
    try {
      for (var memberId in memberIds) {
        await _firestore.collection('notifications').add({
          'familyId': familyId,
          'memberId': memberId,
          'type': 'health_reminder',
          'reminderType': reminderType,
          'message': _getHealthReminderMessage(reminderType),
          'createdAt': FieldValue.serverTimestamp(),
          'read': false,
        });
      }
    } catch (e) {
      print('Error sending health reminders: $e');
      rethrow;
    }
  }

  // Update member health status
  Future<void> updateMemberHealthStatus(
    String memberId,
    Map<String, dynamic> healthData,
  ) async {
    try {
      await _firestore.collection('family_members').doc(memberId).update({
        ...healthData,
        'lastHealthUpdate': FieldValue.serverTimestamp(),
      });

      // Update family stats after health data change
      await updateFamilyStats();
    } catch (e) {
      print('Error updating member health status: $e');
      rethrow;
    }
  }

  // Get member health history
  Future<List<Map<String, dynamic>>> getMemberHealthHistory(
    String memberId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('health_history')
          .where('familyId', isEqualTo: familyId)
          .where('memberId', isEqualTo: memberId)
          .orderBy('recordedAt', descending: true)
          .limit(50)
          .get();

      return snapshot.docs.map((doc) => {'id': doc.id, ...doc.data()}).toList();
    } catch (e) {
      print('Error getting member health history: $e');
      return [];
    }
  }

  // Private helper methods
  Map<String, bool> _getDefaultPermissions() {
    return {
      'viewGeneralHealth': true,
      'viewBMI': true,
      'viewExercise': false,
      'viewMedications': false,
      'emergencyNotifications': true,
      'viewAllergies': true,
      'receiveReminders': false,
    };
  }

  Map<String, bool> _getDefaultNotificationSettings() {
    return {
      'memberJoined': true,
      'healthCheck': true,
      'emergency': true,
      'weeklyReport': false,
      'medicationReminder': true,
      'exerciseReminder': false,
    };
  }

  String _getHealthReminderMessage(String reminderType) {
    switch (reminderType) {
      case 'checkup':
        return 'ได้เวลาตรวจสุขภาพประจำปีแล้ว';
      case 'exercise':
        return 'อย่าลืมออกกำลังกายวันนี้นะ!';
      case 'medication':
        return 'เตือนทานยาตามเวลา';
      case 'water':
        return 'ดื่มน้ำให้เพียงพอในวันนี้';
      case 'sleep':
        return 'ได้เวลาพักผ่อนแล้ว นอนให้เพียงพอนะ';
      default:
        return 'ดูแลสุขภาพให้ดีนะ';
    }
  }

  // Validation methods
  bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  bool isValidPhone(String phone) {
    return RegExp(r'^\+?[\d\s\-\(\)]+$').hasMatch(phone);
  }

  bool isValidAge(int? age) {
    return age != null && age > 0 && age < 150;
  }

  // Get family statistics for dashboard
  Future<Map<String, dynamic>> getFamilyDashboardStats() async {
    try {
      final data = await loadFamilyData();
      final members = data['members'] as List<Map<String, dynamic>>;
      final stats = data['stats'] as Map<String, dynamic>?;

      return {
        'totalMembers': members.length + 1, // +1 for owner
        'newMembersThisMonth': _getNewMembersCount(members),
        'healthyMembers': _getHealthyMembersCount(members),
        'onlineMembers': _getOnlineMembersCount(members),
        'averageAge': stats?['averageAge'] ?? 0,
        'activePercentage': _getActivePercentage(members),
        'lastUpdated': DateTime.now(),
      };
    } catch (e) {
      print('Error getting dashboard stats: $e');
      return {};
    }
  }

  int _getNewMembersCount(List<Map<String, dynamic>> members) {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    return members.where((member) {
      final addedAt = (member['addedAt'] as Timestamp?)?.toDate();
      return addedAt != null && addedAt.isAfter(startOfMonth);
    }).length;
  }

  int _getHealthyMembersCount(List<Map<String, dynamic>> members) {
    return members
            .where(
              (member) =>
                  member['healthStatus'] == 'ดี' ||
                  member['healthStatus'] == 'ปกติ',
            )
            .length +
        1; // +1 for owner (assumed healthy)
  }

  int _getOnlineMembersCount(List<Map<String, dynamic>> members) {
    return members.where((member) => member['isOnline'] == true).length +
        1; // +1 for owner (always online)
  }

  double _getActivePercentage(List<Map<String, dynamic>> members) {
    if (members.isEmpty) return 100.0; // Owner is active

    final activeCount =
        members.where((member) => member['isActive'] == true).length +
        1; // +1 for owner

    return (activeCount / (members.length + 1)) * 100;
  }
}
