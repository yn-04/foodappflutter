// lib/models/cooking_history_model.dart
import 'package:my_app/foodreccom/models/recipe_model.dart';

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

  CookingHistory({
    required this.id,
    required this.recipeId,
    required this.recipeName,
    required this.recipeCategory,
    required this.cookedAt,
    required this.servingsMade,
    required this.usedIngredients,
    required this.totalNutrition,
    this.rating = 0,
    this.notes,
    required this.userId,
  });

  factory CookingHistory.fromFirestore(Map<String, dynamic> data) {
    return CookingHistory(
      id: data['id'] ?? '',
      recipeId: data['recipe_id'] ?? '',
      recipeName: data['recipe_name'] ?? '',
      recipeCategory: data['recipe_category'] ?? '',
      cookedAt: DateTime.parse(data['cooked_at']),
      servingsMade: data['servings_made'] ?? 0,
      usedIngredients: (data['used_ingredients'] as List? ?? [])
          .map((i) => UsedIngredient.fromJson(i))
          .toList(),
      totalNutrition: NutritionInfo.fromJson(data['total_nutrition'] ?? {}),
      rating: data['rating'] ?? 0,
      notes: data['notes'],
      userId: data['user_id'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'recipe_id': recipeId,
    'recipe_name': recipeName,
    'recipe_category': recipeCategory,
    'cooked_at': cookedAt.toIso8601String(),
    'servings_made': servingsMade,
    'used_ingredients': usedIngredients.map((i) => i.toJson()).toList(),
    'total_nutrition': totalNutrition.toJson(),
    'rating': rating,
    'notes': notes,
    'user_id': userId,
  };
}

class UsedIngredient {
  final String name;
  final double amount;
  final String unit;
  final String category;
  final double cost;

  UsedIngredient({
    required this.name,
    required this.amount,
    required this.unit,
    required this.category,
    this.cost = 0.0,
  });

  factory UsedIngredient.fromJson(Map<String, dynamic> json) {
    return UsedIngredient(
      name: json['name'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      unit: json['unit'] ?? '',
      category: json['category'] ?? '',
      cost: (json['cost'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'amount': amount,
    'unit': unit,
    'category': category,
    'cost': cost,
  };
}
