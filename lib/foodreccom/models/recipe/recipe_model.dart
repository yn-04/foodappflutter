//lib/foodreccom/models/recipe/recipe_model.dart
import 'package:flutter/material.dart';
import 'recipe_ingredient.dart';
import 'cooking_step.dart';
import 'nutrition_info.dart';

class RecipeModel {
  final String id;
  final String name;
  final String description;
  final int matchScore;
  final String reason;
  final List<RecipeIngredient> ingredients;
  final List<String> missingIngredients;
  final List<CookingStep> steps;
  final int cookingTime;
  final int prepTime;
  final String difficulty;
  final int servings;
  final String category;
  final NutritionInfo nutrition;
  final String? imageUrl;
  final List<String> tags;
  final String? source;
  final String? sourceUrl;

  RecipeModel({
    required this.id,
    required this.name,
    required this.description,
    required this.matchScore,
    required this.reason,
    required this.ingredients,
    required this.missingIngredients,
    required this.steps,
    required this.cookingTime,
    required this.prepTime,
    required this.difficulty,
    required this.servings,
    required this.category,
    required this.nutrition,
    this.imageUrl,
    this.tags = const [],
    this.source,
    this.sourceUrl,
  });

  /// ✅ Parse จาก AI
  factory RecipeModel.fromAI(Map<String, dynamic> json) {
    return RecipeModel(
      id: (json['id'] ?? DateTime.now().millisecondsSinceEpoch).toString(),
      name: json['name'] ?? json['menu_name'] ?? 'ไม่ระบุชื่อ',
      description: json['description'] ?? '',
      matchScore: (json['matchScore'] ?? json['match_score'] ?? 0).round(),
      reason: json['reason'] ?? '',
      ingredients: (json['ingredients'] as List? ?? []).map((i) {
        if (i is String) {
          return RecipeIngredient(name: i, amount: 1, unit: "");
        }
        if (i is Map<String, dynamic>) {
          return RecipeIngredient.fromJson(i);
        }
        return RecipeIngredient(name: i.toString(), amount: 1, unit: "");
      }).toList(),
      missingIngredients: List<String>.from(
        json['missingIngredients'] ?? json['missing_ingredients'] ?? [],
      ),
      steps: (json['steps'] as List? ?? []).map((s) {
        if (s is String) return CookingStep(stepNumber: 1, instruction: s);
        if (s is Map<String, dynamic>) return CookingStep.fromJson(s);
        return CookingStep(stepNumber: 1, instruction: s.toString());
      }).toList(),
      cookingTime: json['cookingTime'] ?? json['cooking_time'] ?? 30,
      prepTime: json['prepTime'] ?? json['prep_time'] ?? 10,
      difficulty: json['difficulty'] ?? 'ปานกลาง',
      servings: json['servings'] ?? 2,
      category: json['category'] ?? 'อาหารจานหลัก',
      nutrition: NutritionInfo.fromJson(json['nutrition'] ?? {}),
      imageUrl: json['imageUrl'] ?? json['image_url'],
      tags: List<String>.from(json['tags'] ?? []),
      source: json['source'] ?? "AI",
      sourceUrl: json['sourceUrl'] ?? json['source_url'],
    );
  }

  /// ✅ Parse จาก RapidAPI (spoonacular)
  factory RecipeModel.fromAPI(Map<String, dynamic> json) {
    return RecipeModel(
      id: json['id'].toString(),
      name: json['title'] ?? json['name'] ?? 'ไม่ระบุชื่อ',
      description: json['summary'] ?? json['description'] ?? '',
      matchScore: 70,
      reason: 'Imported from RapidAPI',
      ingredients: (json['extendedIngredients'] as List? ?? []).map((i) {
        return RecipeIngredient(
          name: i['name'] ?? 'ไม่ระบุ',
          amount: (i['amount'] ?? 1).toDouble(),
          unit: i['unit'] ?? '',
        );
      }).toList(),
      missingIngredients: [],
      steps:
          ((json['analyzedInstructions'] as List?)?.expand((ins) {
            final steps = ins['steps'] as List? ?? [];
            return steps.map(
              (s) => CookingStep(
                stepNumber: s['number'] ?? 1,
                instruction: s['step'] ?? '',
              ),
            );
          }).toList()) ??
          [],
      cookingTime: json['readyInMinutes'] ?? 0,
      prepTime: 0,
      difficulty: 'ไม่ระบุ',
      servings: json['servings'] ?? 1,
      category: 'ไม่ระบุ',
      nutrition: NutritionInfo.fromJson(
        json['nutrition']?['nutrients'] != null
            ? {
                'calories':
                    (json['nutrition']['nutrients'].firstWhere(
                              (n) => n['name'] == 'Calories',
                              orElse: () => {'amount': 0},
                            )['amount'] ??
                            0)
                        .toDouble(),
              }
            : {},
      ),
      imageUrl: json['image'],
      tags: [],
      source: 'RapidAPI',
      sourceUrl: json['sourceUrl'],
    );
  }

  /// ✅ Parse Generic JSON (offline/fallback)
  factory RecipeModel.fromJson(Map<String, dynamic> json) {
    return RecipeModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      matchScore: (json['matchScore'] ?? json['match_score'] ?? 0).round(),
      reason: json['reason'] ?? '',
      ingredients: (json['ingredients'] as List? ?? []).map((i) {
        if (i is Map<String, dynamic>) return RecipeIngredient.fromJson(i);
        return RecipeIngredient(name: i.toString(), amount: 1, unit: "");
      }).toList(),
      missingIngredients:
          (json['missingIngredients'] ?? json['missing_ingredients'] ?? [])
              .cast<String>(),
      steps: (json['steps'] as List? ?? []).map((s) {
        if (s is Map<String, dynamic>) return CookingStep.fromJson(s);
        return CookingStep(stepNumber: 1, instruction: s.toString());
      }).toList(),
      cookingTime: json['cookingTime'] ?? json['cooking_time'] ?? 0,
      prepTime: json['prepTime'] ?? json['prep_time'] ?? 0,
      difficulty: json['difficulty'] ?? 'ง่าย',
      servings: json['servings'] ?? 1,
      category: json['category'] ?? 'ไม่ระบุ',
      nutrition: NutritionInfo.fromJson(json['nutrition'] ?? {}),
      imageUrl: json['imageUrl'] ?? json['image_url'],
      tags: (json['tags'] as List? ?? []).cast<String>(),
      source: json['source'],
      sourceUrl: json['sourceUrl'] ?? json['source_url'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'match_score': matchScore,
    'reason': reason,
    'ingredients': ingredients.map((i) => i.toJson()).toList(),
    'missing_ingredients': missingIngredients,
    'steps': steps.map((s) => s.toJson()).toList(),
    'cooking_time': cookingTime,
    'prep_time': prepTime,
    'difficulty': difficulty,
    'servings': servings,
    'category': category,
    'nutrition': nutrition.toJson(),
    'image_url': imageUrl,
    'tags': tags,
    'source': source,
    'source_url': sourceUrl,
  };

  List<String> get ingredientsUsed => ingredients.map((i) => i.name).toList();

  int get totalTime => cookingTime + prepTime;

  Color get scoreColor {
    if (matchScore >= 80) return Colors.green;
    if (matchScore >= 60) return Colors.orange;
    return Colors.red;
  }

  double get caloriesPerServing =>
      servings > 0 ? nutrition.calories / servings : 0;
}

/// ✅ ต้องอยู่นอก class
extension RecipeCopy on RecipeModel {
  RecipeModel copyWith({
    String? id,
    String? name,
    String? description,
    int? matchScore,
    String? reason,
    List<RecipeIngredient>? ingredients,
    List<String>? missingIngredients,
    List<CookingStep>? steps,
    int? cookingTime,
    int? prepTime,
    String? difficulty,
    int? servings,
    String? category,
    NutritionInfo? nutrition,
    String? imageUrl,
    List<String>? tags,
    String? source,
    String? sourceUrl,
  }) {
    return RecipeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      matchScore: matchScore ?? this.matchScore,
      reason: reason ?? this.reason,
      ingredients: ingredients ?? this.ingredients,
      missingIngredients: missingIngredients ?? this.missingIngredients,
      steps: steps ?? this.steps,
      cookingTime: cookingTime ?? this.cookingTime,
      prepTime: prepTime ?? this.prepTime,
      difficulty: difficulty ?? this.difficulty,
      servings: servings ?? this.servings,
      category: category ?? this.category,
      nutrition: nutrition ?? this.nutrition,
      imageUrl: imageUrl ?? this.imageUrl,
      tags: tags ?? this.tags,
      source: source ?? this.source,
      sourceUrl: sourceUrl ?? this.sourceUrl,
    );
  }
}
