// lib/foodreccom/models/cooking_history_model.dart
import '../utils/date_utils.dart';
import 'recipe/recipe.dart';
import 'recipe/used_ingredient.dart';

class HistoryIngredientPortion {
  final String name;
  final double amount;
  final String unit;
  final double canonicalAmount;
  final String canonicalUnit;
  final bool isOptional;

  const HistoryIngredientPortion({
    required this.name,
    required this.amount,
    required this.unit,
    required this.canonicalAmount,
    required this.canonicalUnit,
    required this.isOptional,
  });

  factory HistoryIngredientPortion.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return const HistoryIngredientPortion(
        name: '',
        amount: 0,
        unit: '',
        canonicalAmount: 0,
        canonicalUnit: 'gram',
        isOptional: false,
      );
    }
    double _toDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    final canonicalRaw = map.containsKey('canonical_amount')
        ? map['canonical_amount']
        : map['canonical_required_amount'];
    return HistoryIngredientPortion(
      name: map['name'] ?? '',
      amount: _toDouble(map['amount'] ?? map['required_amount']),
      unit: map['unit'] ?? '',
      canonicalAmount: _toDouble(
        canonicalRaw ?? map['amount'] ?? map['required_amount'],
      ),
      canonicalUnit: map['canonical_unit'] ?? 'gram',
      isOptional: map['is_optional'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'amount': amount,
      'unit': unit,
      'canonical_amount': canonicalAmount,
      'canonical_unit': canonicalUnit,
      'is_optional': isOptional,
    };
  }
}

class CookingHistory {
  final String id;
  final String recipeId;
  final String recipeName;
  final String recipeCategory;
  final DateTime cookedAt;
  final int servingsMade;
  final List<UsedIngredient> usedIngredients;
  final NutritionInfo totalNutrition;
  final int rating;
  final String? notes;
  final String userId;
  final List<HistoryIngredientPortion> recipeIngredientPortions;
  final NutritionInfo? recipeNutritionPerServing;
  final List<CookingStep> recipeSteps;

  CookingHistory({
    required this.id,
    required this.recipeId,
    required this.recipeName,
    required this.recipeCategory,
    required this.cookedAt,
    required this.servingsMade,
    required this.usedIngredients,
    required this.totalNutrition,
    required this.rating,
    this.notes,
    required this.userId,
    this.recipeIngredientPortions = const [],
    this.recipeNutritionPerServing,
    this.recipeSteps = const [],
  });

  factory CookingHistory.fromFirestore(Map<String, dynamic> data) {
    return CookingHistory(
      id: data['id'] ?? '',
      recipeId: data['recipe_id'] ?? '',
      recipeName: data['recipe_name'] ?? '',
      recipeCategory: data['recipe_category'] ?? '',
      cookedAt: parseDate(data['cooked_at']),
      servingsMade: data['servings_made'] ?? 0,
      usedIngredients: (data['used_ingredients'] as List? ?? [])
          .map((i) => UsedIngredient.fromMap(i))
          .toList(),
      totalNutrition: NutritionInfo.fromMap(data['total_nutrition'] ?? {}),
      rating: data['rating'] ?? 0,
      notes: data['notes'],
      userId: data['user_id'] ?? '',
      recipeIngredientPortions:
          (data['recipe_ingredient_portions'] as List? ?? []).map((item) {
        final map = (item is Map)
            ? Map<String, dynamic>.from(item as Map)
            : null;
        return HistoryIngredientPortion.fromMap(map);
      }).toList(),
      recipeNutritionPerServing:
          data['recipe_nutrition_per_serving'] != null
              ? NutritionInfo.fromMap(
                  Map<String, dynamic>.from(
                    data['recipe_nutrition_per_serving'] as Map,
                  ),
                )
              : null,
      recipeSteps: (data['recipe_steps'] as List? ?? []).map((step) {
        final map = (step is Map)
            ? Map<String, dynamic>.from(step as Map)
            : <String, dynamic>{};
        return CookingStep.fromJson(map);
      }).toList(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'recipe_id': recipeId,
      'recipe_name': recipeName,
      'recipe_category': recipeCategory,
      'cooked_at': cookedAt.toIso8601String(),
      'servings_made': servingsMade,
      'used_ingredients': usedIngredients.map((i) => i.toMap()).toList(),
      'total_nutrition': totalNutrition.toMap(),
      'rating': rating,
      'notes': notes,
      'user_id': userId,
      'recipe_ingredient_portions':
          recipeIngredientPortions.map((e) => e.toMap()).toList(),
      if (recipeNutritionPerServing != null)
        'recipe_nutrition_per_serving': recipeNutritionPerServing!.toMap(),
      'recipe_steps': recipeSteps.map((e) => e.toJson()).toList(),
    };
  }
}
