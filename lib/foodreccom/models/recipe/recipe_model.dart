import 'package:flutter/material.dart';
import 'recipe_ingredient.dart';
import 'cooking_step.dart';
import 'nutrition_info.dart';

class RecipeModel {
  final String id;
  final String name;
  final String description;
  final int matchScore;
  final double matchRatio;
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
    this.matchRatio = 0.0,
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
    num _numOrZero(dynamic value) {
      if (value is num) return value;
      if (value is String) {
        return num.tryParse(value) ?? 0;
      }
      return 0;
    }

    final rawScore = _numOrZero(json['matchScore'] ?? json['match_score']);
    final rawRatio = _numOrZero(json['matchRatio'] ?? json['match_ratio']);
    final inferredRatio = rawRatio > 0
        ? rawRatio.toDouble()
        : (rawScore.toDouble() / 100);
    final normalizedRatio = inferredRatio.clamp(0.0, 1.0);

    return RecipeModel(
      id: (json['id'] ?? DateTime.now().millisecondsSinceEpoch).toString(),
      name: json['name'] ?? json['menu_name'] ?? 'ไม่ระบุชื่อ',
      description: json['description'] ?? '',
      matchScore: (json['matchScore'] ?? json['match_score'] ?? 0).round(),
      matchRatio: normalizedRatio,
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
      nutrition: json['nutrition'] != null
          ? NutritionInfo.fromJson(json['nutrition'])
          : NutritionInfo.empty(),
      imageUrl: json['imageUrl'] ?? json['image_url'],
      tags: List<String>.from(json['tags'] ?? []),
      source: json['source'] ?? "AI",
      sourceUrl: json['sourceUrl'] ?? json['source_url'],
    );
  }

  /// ✅ Parse จาก RapidAPI (spoonacular)
  factory RecipeModel.fromAPI(Map<String, dynamic> json) {
    final cuisines = (json['cuisines'] as List? ?? [])
        .whereType<String>()
        .toList();
    final diets = (json['diets'] as List? ?? []).whereType<String>().toList();
    final dishTypes = (json['dishTypes'] as List? ?? [])
        .whereType<String>()
        .toList();
    double _clampRatio(double value) => value.clamp(0.0, 1.0);
    double _nutrientAmount(String key) {
      final nutrients = (json['nutrition']?['nutrients'] as List?) ?? [];
      for (final item in nutrients) {
        if (item is Map<String, dynamic>) {
          final name = (item['name'] ?? '').toString().toLowerCase();
          if (name == key.toLowerCase()) {
            return (item['amount'] ?? 0).toDouble();
          }
        }
      }
      return 0;
    }

    final servings = (json['servings'] ?? 1);
    final servingsCount = (servings is num && servings > 0)
        ? servings.toDouble()
        : 1.0;

    final nutrition = json['nutrition'] != null
        ? NutritionInfo(
            calories: _nutrientAmount('calories') * servingsCount,
            protein: _nutrientAmount('protein') * servingsCount,
            carbs: _nutrientAmount('carbohydrates') * servingsCount,
            fat: _nutrientAmount('fat') * servingsCount,
            fiber: _nutrientAmount('fiber') * servingsCount,
            sodium: _nutrientAmount('sodium') * servingsCount,
          )
        : NutritionInfo.empty();

    final tagSet = <String>{
      ...cuisines.map((e) => e.toLowerCase()),
      ...diets.map((e) => e.toLowerCase()),
      ...dishTypes.map((e) => e.toLowerCase()),
    }..removeWhere((e) => e.trim().isEmpty);

    return RecipeModel(
      id: json['id'].toString(),
      name: json['title'] ?? json['name'] ?? 'ไม่ระบุชื่อ',
      description: json['summary'] ?? json['description'] ?? '',
      matchScore: 70,
      matchRatio: _clampRatio(70 / 100),
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
      servings: servingsCount.round(),
      category: 'ไม่ระบุ',
      nutrition: nutrition,
      imageUrl: json['image'],
      tags: tagSet.toList(),
      source: 'RapidAPI',
      sourceUrl: json['sourceUrl'],
    );
  }

  /// ✅ Parse Generic JSON (offline/fallback)
  factory RecipeModel.fromJson(Map<String, dynamic> json) {
    num _numOrZero(dynamic value) {
      if (value is num) return value;
      if (value is String) return num.tryParse(value) ?? 0;
      return 0;
    }

    final rawScore = _numOrZero(json['matchScore'] ?? json['match_score']);
    final rawRatio = _numOrZero(json['matchRatio'] ?? json['match_ratio']);
    final inferredRatio = rawRatio > 0
        ? rawRatio.toDouble()
        : rawScore.toDouble() / 100;
    final normalizedRatio = inferredRatio.clamp(0.0, 1.0);

    return RecipeModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      matchScore: (json['matchScore'] ?? json['match_score'] ?? 0).round(),
      matchRatio: normalizedRatio,
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
      nutrition: json['nutrition'] != null
          ? NutritionInfo.fromJson(json['nutrition'])
          : NutritionInfo.empty(),
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
    'match_ratio': matchRatio,
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

  double get matchScorePercent =>
      matchRatio > 0 ? (matchRatio * 100).clamp(0, 100) : matchScore.toDouble();

  String get matchScoreLabel {
    final percent = matchScorePercent;
    if (percent == percent.roundToDouble()) {
      return percent.toStringAsFixed(0);
    }
    final decimals = percent < 10 ? 2 : 1;
    return percent.toStringAsFixed(decimals);
  }

  Color get scoreColor {
    final percent = matchScorePercent;
    if (percent >= 80) return Colors.green;
    if (percent >= 60) return Colors.orange;
    return Colors.red;
  }

  String get shortDescription {
    final normalized = description.replaceAll(RegExp(r'\s+'), ' ').trim();
    String base = '';
    if (normalized.isNotEmpty) {
      final sentences = normalized
          .split(RegExp(r'(?<=[.!?。！？])\s+'))
          .where((s) => s.trim().isNotEmpty);
      if (sentences.isNotEmpty) {
        base = sentences.first.trim();
      } else {
        base = normalized;
      }
      if (!RegExp(r'[.!?。！？]$').hasMatch(base)) {
        base = '$base.';
      }
    }

    final highlightParts = <String>[];
    if (servings > 0) {
      highlightParts.add('เสิร์ฟ $servings ที่');
    }
    if (totalTime > 0) {
      highlightParts.add('~${totalTime} นาที');
    }
    final cals = caloriesPerServing.round();
    if (cals > 0) {
      highlightParts.add('$cals kcal/ที่');
    }
    if (difficulty.trim().isNotEmpty) {
      highlightParts.add('ระดับ $difficulty');
    }

    final highlight = highlightParts.join(' • ');
    final segments = <String>[];
    if (base.isNotEmpty) segments.add(base);
    if (highlight.isNotEmpty) segments.add(highlight);

    if (segments.isEmpty) {
      return name.trim().isNotEmpty ? name : 'เมนูอาหาร';
    }

    String summary = segments.join(' | ');
    const limit = 160;
    if (summary.length <= limit) return summary;

    if (segments.length == 2) {
      final allowedForBase = limit - highlight.length - 3; // " | "
      if (allowedForBase <= 0) {
        if (highlight.length <= limit) {
          return highlight;
        }
        return highlight.substring(0, limit - 1).trimRight() + '…';
      }
      var trimmedBase = base;
      if (trimmedBase.length > allowedForBase) {
        trimmedBase = trimmedBase.substring(0, allowedForBase).trimRight();
        if (!trimmedBase.endsWith('…')) {
          trimmedBase = trimmedBase.endsWith('.')
              ? '${trimmedBase.substring(0, trimmedBase.length - 1)}…'
              : '$trimmedBase…';
        }
      }
      summary = '$trimmedBase | $highlight';
      if (summary.length <= limit) return summary;
    }

    final trimmed = summary.substring(0, limit).trimRight();
    if (trimmed.endsWith('…')) return trimmed;
    if (trimmed.endsWith('.')) return trimmed;
    return '$trimmed…';
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
    double? matchRatio,
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
      matchRatio: matchRatio ?? this.matchRatio,
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
