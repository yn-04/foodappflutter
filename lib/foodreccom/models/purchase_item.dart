import 'package:my_app/foodreccom/constants/nutrition_thresholds.dart';

class PurchaseItem {
  final String name;
  final int quantity;
  final String unit;
  final String? category;
  final double requiredAmount;
  final double availableAmount;
  final String canonicalUnit;
  final ConsumptionFrequency? consumptionFrequency;
  final String? frequencyReason;

  const PurchaseItem({
    required this.name,
    required this.quantity,
    required this.unit,
    this.category,
    this.requiredAmount = 0,
    this.availableAmount = 0,
    this.canonicalUnit = '',
    this.consumptionFrequency,
    this.frequencyReason,
  });

  double get missingAmount {
    final missing = requiredAmount - availableAmount;
    return missing < 0 ? 0 : missing;
  }

  bool get hasAnyStock => availableAmount > 0;
}
