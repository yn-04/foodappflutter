// lib/foodreccom/models/recipe/used_ingredient.dart
class UsedIngredient {
  final String name;
  final double amount;
  final String unit;
  final String category;
  final double cost;
  final List<String> rawMaterialIds;

  UsedIngredient({
    required this.name,
    required this.amount,
    required this.unit,
    required this.category,
    required this.cost,
    this.rawMaterialIds = const [],
  });

  factory UsedIngredient.fromMap(Map<String, dynamic> map) {
    return UsedIngredient(
      name: map['name'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      unit: map['unit'] ?? '',
      category: map['category'] ?? '',
      cost: (map['cost'] ?? 0).toDouble(),
      rawMaterialIds: List<String>.from(
        (map['raw_material_ids'] as List? ?? const <dynamic>[]).map(
          (e) => e?.toString() ?? '',
        ),
      )..removeWhere((element) => element.isEmpty),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'amount': amount,
      'unit': unit,
      'category': category,
      'cost': cost,
      if (rawMaterialIds.isNotEmpty) 'raw_material_ids': rawMaterialIds,
    };
  }
}
