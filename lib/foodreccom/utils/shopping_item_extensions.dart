import 'package:my_app/foodreccom/constants/nutrition_thresholds.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';

extension ShoppingItemConsumptionX on ShoppingItem {
  /// Placeholder until nutrition metadata is tracked for raw materials.
  ConsumptionFrequency? get consumptionFrequency => null;

  /// Placeholder reason matching the consumption frequency shim.
  String? get consumptionReason => null;
}
