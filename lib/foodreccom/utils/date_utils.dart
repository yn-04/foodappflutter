// lib/foodreccom/utils/date_utils.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Utility: แปลง Firestore Timestamp หรือ String → DateTime
DateTime parseDate(dynamic value) {
  if (value == null) return DateTime.now();

  if (value is Timestamp) {
    return value.toDate().toLocal();
  }

  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.isUtc ? parsed.toLocal() : parsed;
    }
  }

  return DateTime.now();
}
