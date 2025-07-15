// services/settings_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'user_settings';

  // Default settings values
  static const Map<String, dynamic> _defaultSettings = {
    'biometricEnabled': false,
    'notificationsEnabled': true,
    'emailNotifications': true,
    'smsNotifications': false,
    'pushNotifications': true,
    'healthReminders': true,
    'familyNotifications': true,
    // Notification times
    'morningNotificationEnabled': true,
    'morningNotificationTime': '08:00',
    'eveningNotificationEnabled': true,
    'eveningNotificationTime': '18:00',
    'bedtimeNotificationEnabled': false,
    'bedtimeNotificationTime': '21:00',
    // Privacy settings
    'shareHealthData': true,
    'anonymousAnalytics': false,
    'personalizedMarketing': false,
    'dataProcessingConsent': true,
    'thirdPartySharing': false,
  };

  /// Load all settings for a user
  Future<Map<String, bool>> loadSettings(String userId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(userId).get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        // Convert to Map<String, bool> and apply defaults
        final Map<String, bool> settings = {};

        _defaultSettings.forEach((key, defaultValue) {
          if (defaultValue is bool) {
            settings[key] = data[key] ?? defaultValue;
          }
        });

        return settings;
      } else {
        // Return default settings if document doesn't exist
        final Map<String, bool> boolSettings = {};
        _defaultSettings.forEach((key, value) {
          if (value is bool) {
            boolSettings[key] = value;
          }
        });
        return boolSettings;
      }
    } catch (e) {
      print('Error loading settings: $e');
      // Return default settings on error
      final Map<String, bool> boolSettings = {};
      _defaultSettings.forEach((key, value) {
        if (value is bool) {
          boolSettings[key] = value;
        }
      });
      return boolSettings;
    }
  }

  /// Load all settings including non-boolean values
  Future<Map<String, dynamic>> loadAllSettings(String userId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(userId).get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        // Merge with defaults
        final Map<String, dynamic> settings = Map.from(_defaultSettings);
        data.forEach((key, value) {
          settings[key] = value;
        });

        return settings;
      } else {
        return Map.from(_defaultSettings);
      }
    } catch (e) {
      print('Error loading all settings: $e');
      return Map.from(_defaultSettings);
    }
  }

  /// Update a single setting
  Future<bool> updateSetting(String userId, String key, dynamic value) async {
    try {
      await _firestore.collection(_collection).doc(userId).set({
        key: value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return true;
    } catch (e) {
      print('Error updating setting $key: $e');
      return false;
    }
  }

  /// Update multiple settings at once
  Future<bool> updateSettings(
    String userId,
    Map<String, dynamic> settings,
  ) async {
    try {
      final updateData = Map<String, dynamic>.from(settings);
      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore
          .collection(_collection)
          .doc(userId)
          .set(updateData, SetOptions(merge: true));

      return true;
    } catch (e) {
      print('Error updating settings: $e');
      return false;
    }
  }

  /// Initialize settings for a new user
  Future<bool> initializeSettings(String userId) async {
    try {
      final initialSettings = Map<String, dynamic>.from(_defaultSettings);
      initialSettings['createdAt'] = FieldValue.serverTimestamp();
      initialSettings['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection(_collection).doc(userId).set(initialSettings);

      return true;
    } catch (e) {
      print('Error initializing settings: $e');
      return false;
    }
  }

  /// Delete all settings for a user
  Future<bool> deleteSettings(String userId) async {
    try {
      await _firestore.collection(_collection).doc(userId).delete();
      return true;
    } catch (e) {
      print('Error deleting settings: $e');
      return false;
    }
  }

  /// Reset settings to default values
  Future<bool> resetToDefaults(String userId) async {
    try {
      final defaultSettings = Map<String, dynamic>.from(_defaultSettings);
      defaultSettings['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore.collection(_collection).doc(userId).set(defaultSettings);

      return true;
    } catch (e) {
      print('Error resetting settings: $e');
      return false;
    }
  }

  /// Get notification time settings
  Future<Map<String, String>> getNotificationTimes(String userId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(userId).get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        return {
          'morningTime': data['morningNotificationTime'] ?? '08:00',
          'eveningTime': data['eveningNotificationTime'] ?? '18:00',
          'bedtimeTime': data['bedtimeNotificationTime'] ?? '21:00',
        };
      } else {
        return {
          'morningTime': '08:00',
          'eveningTime': '18:00',
          'bedtimeTime': '21:00',
        };
      }
    } catch (e) {
      print('Error getting notification times: $e');
      return {
        'morningTime': '08:00',
        'eveningTime': '18:00',
        'bedtimeTime': '21:00',
      };
    }
  }

  /// Update notification time settings
  Future<bool> updateNotificationTimes(
    String userId,
    Map<String, String> times,
  ) async {
    try {
      final updateData = <String, dynamic>{};

      if (times.containsKey('morningTime')) {
        updateData['morningNotificationTime'] = times['morningTime'];
      }
      if (times.containsKey('eveningTime')) {
        updateData['eveningNotificationTime'] = times['eveningTime'];
      }
      if (times.containsKey('bedtimeTime')) {
        updateData['bedtimeNotificationTime'] = times['bedtimeTime'];
      }

      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore
          .collection(_collection)
          .doc(userId)
          .set(updateData, SetOptions(merge: true));

      return true;
    } catch (e) {
      print('Error updating notification times: $e');
      return false;
    }
  }

  /// Get privacy settings
  Future<Map<String, bool>> getPrivacySettings(String userId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(userId).get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        return {
          'shareHealthData': data['shareHealthData'] ?? true,
          'anonymousAnalytics': data['anonymousAnalytics'] ?? false,
          'personalizedMarketing': data['personalizedMarketing'] ?? false,
          'dataProcessingConsent': data['dataProcessingConsent'] ?? true,
          'thirdPartySharing': data['thirdPartySharing'] ?? false,
        };
      } else {
        return {
          'shareHealthData': true,
          'anonymousAnalytics': false,
          'personalizedMarketing': false,
          'dataProcessingConsent': true,
          'thirdPartySharing': false,
        };
      }
    } catch (e) {
      print('Error getting privacy settings: $e');
      return {
        'shareHealthData': true,
        'anonymousAnalytics': false,
        'personalizedMarketing': false,
        'dataProcessingConsent': true,
        'thirdPartySharing': false,
      };
    }
  }

  /// Update privacy settings
  Future<bool> updatePrivacySettings(
    String userId,
    Map<String, bool> privacySettings,
  ) async {
    try {
      final updateData = Map<String, dynamic>.from(privacySettings);
      updateData['updatedAt'] = FieldValue.serverTimestamp();

      await _firestore
          .collection(_collection)
          .doc(userId)
          .set(updateData, SetOptions(merge: true));

      return true;
    } catch (e) {
      print('Error updating privacy settings: $e');
      return false;
    }
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled(String userId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(userId).get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        return data['notificationsEnabled'] ?? true;
      }
      return true;
    } catch (e) {
      print('Error checking notifications status: $e');
      return true;
    }
  }

  /// Get settings last updated time
  Future<DateTime?> getLastUpdated(String userId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(userId).get();

      if (doc.exists) {
        final data = doc.data() ?? {};
        final timestamp = data['updatedAt'] as Timestamp?;
        return timestamp?.toDate();
      }
      return null;
    } catch (e) {
      print('Error getting last updated time: $e');
      return null;
    }
  }
}
