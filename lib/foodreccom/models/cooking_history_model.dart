// lib/foodreccom/models/cooking_history_model.dart
import '../utils/date_utils.dart';
import 'recipe/recipe.dart';
import 'recipe/used_ingredient.dart';

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
    required this.rating,
    this.notes,
    required this.userId,
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
    };
  }
}
