// lib/foodreccom/models/ingredient_model.dart
import '../utils/date_utils.dart';

class IngredientModel {
  final String name;
  final double quantity;
  final String unit;
  final String category;
  final DateTime? expiryDate;
  final double? price;
  final String? notes;
  final DateTime addedDate;
  final int usageCount;
  final DateTime? lastUsedDate;
  final double utilizationRate;

  IngredientModel({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.category,
    this.expiryDate,
    this.price,
    this.notes,
    DateTime? addedDate,
    this.usageCount = 0,
    this.lastUsedDate,
    this.utilizationRate = 0.0,
  }) : addedDate = addedDate ?? DateTime.now();

  factory IngredientModel.fromFirestore(Map<String, dynamic> data) {
    return IngredientModel(
      name: data['name'] ?? '',
      quantity: (data['quantity'] ?? 0).toDouble(),
      unit: data['unit'] ?? '',
      category: data['category'] ?? '',
      expiryDate: parseDate(data['expiry_date']),
      price: (data['price'] != null) ? (data['price'] as num).toDouble() : null,
      notes: data['notes'],
      addedDate: parseDate(data['added_date']),
      usageCount: data['usage_count'] ?? 0,
      lastUsedDate: parseDate(data['last_used_date']),
      utilizationRate: (data['utilization_rate'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'category': category,
      'expiry_date': expiryDate?.toIso8601String(),
      'price': price,
      'notes': notes,
      'added_date': addedDate.toIso8601String(),
      'usage_count': usageCount,
      'last_used_date': lastUsedDate?.toIso8601String(),
      'utilization_rate': utilizationRate,
    };
  }

  int get daysToExpiry {
    if (expiryDate == null) return 999;
    final now = DateTime.now();
    final difference = expiryDate!.difference(now).inDays;
    return difference < 0 ? 0 : difference;
  }

  bool get isNearExpiry => daysToExpiry <= 3;
  bool get isUrgentExpiry => daysToExpiry <= 1;
  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());
  int get daysToExpiryRaw =>
      expiryDate == null ? 999 : expiryDate!.difference(DateTime.now()).inDays;
  bool get isFrequentlyUsed => usageCount >= 5 || utilizationRate >= 0.7;

  bool get isUnderutilized {
    if (usageCount == 0) return true;
    if (lastUsedDate == null) return true;
    final daysSinceLastUse = DateTime.now().difference(lastUsedDate!).inDays;
    return daysSinceLastUse > 30 && usageCount < 2;
  }

  int get priorityScore {
    int score = 0;
    if (isUrgentExpiry) {
      score += 40;
    } else if (isNearExpiry) {
      score += 30;
    } else if (daysToExpiry <= 7) {
      score += 20;
    }

    if (isFrequentlyUsed) {
      score += 30;
    } else if (usageCount > 0) {
      score += 15;
    }

    if (isUnderutilized) {
      score += 20;
    }

    if (price != null && price! > 50) {
      score += 10;
    } else if (price != null && price! > 20) {
      score += 5;
    }

    return score.clamp(0, 100);
  }

  Map<String, dynamic> toAIFormat() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'category': category,
      'days_to_expiry': daysToExpiry,
      'is_near_expiry': isNearExpiry,
      'is_urgent_expiry': isUrgentExpiry,
      'is_expired': isExpired,
      'usage_count': usageCount,
      'is_frequently_used': isFrequentlyUsed,
      'is_underutilized': isUnderutilized,
      'priority_score': priorityScore,
      'utilization_rate': utilizationRate,
      'price': price ?? 0,
      'days_since_added': DateTime.now().difference(addedDate).inDays,
    };
  }

  IngredientModel copyWithUsage({
    double? quantity,
    int? additionalUsage = 1,
    DateTime? lastUsed,
    double? newUtilizationRate,
  }) {
    return IngredientModel(
      name: name,
      quantity: quantity ?? this.quantity,
      unit: unit,
      category: category,
      expiryDate: expiryDate,
      price: price,
      notes: notes,
      addedDate: addedDate,
      usageCount: usageCount + (additionalUsage ?? 0),
      lastUsedDate: lastUsed ?? DateTime.now(),
      utilizationRate: newUtilizationRate ?? utilizationRate,
    );
  }
}
