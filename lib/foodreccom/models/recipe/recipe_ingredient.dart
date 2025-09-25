//lib/foodreccom/models/recipe/recipe_ingredient.dart
class RecipeIngredient {
  final String name;
  final dynamic amount; // double หรือ string ("5-10")
  final String unit;
  final bool isOptional;

  RecipeIngredient({
    required this.name,
    required this.amount,
    required this.unit,
    this.isOptional = false,
  });

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      name: json['name'] ?? '',
      amount: _parseAmount(json['amount']),
      unit: json['unit'] ?? '',
      isOptional: json['is_optional'] ?? false,
    );
  }

  static dynamic _parseAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      if (value.contains('-')) return value;
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'amount': amount,
    'unit': unit,
    'is_optional': isOptional,
  };

  String get displayAmount {
    if (amount is String) return amount.toString();
    if (amount is num) {
      return amount == amount.toInt()
          ? amount.toInt().toString()
          : amount.toString();
    }
    return '0';
  }

  double get numericAmount {
    if (amount is num) return amount.toDouble();
    if (amount is String && amount.contains('-')) {
      return double.tryParse(amount.split('-').first.trim()) ?? 0.0;
    }
    return 0.0;
  }

  String get amountRange => (amount is String && amount.contains('-'))
      ? amount.toString()
      : displayAmount;
}
