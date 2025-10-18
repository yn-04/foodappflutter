// lib/foodreccom/utils/recipe_parser.dart
import 'package:my_app/common/measurement_constants.dart';
import 'package:my_app/common/smart_unit_converter.dart'
    as piece_converter; // 🍳 สำหรับวัตถุดิบแบบ "ชิ้น"
import '../utils/smart_unit_converter.dart'
    as unit_converter; // 🧪 สำหรับการแปลงหน่วยทั่วไป

import '../models/recipe/recipe.dart';

class RecipeParser {
  /// แปลงข้อมูล Spoonacular API → RecipeModel
  static RecipeModel parseSpoonacularRecipe(Map<String, dynamic> data) {
    final ingredients = (data['extendedIngredients'] as List? ?? []).map((
      rawIng,
    ) {
      final ing = rawIng as Map<String, dynamic>?;
      final name = ing?['name']?.toString() ?? '';
      final metric =
          (ing?['measures'] as Map?)?['metric'] as Map<String, dynamic>?;

      double amount = 0.0;
      String? unitRaw;

      if (metric != null) {
        amount = _parseNumericAmount(metric['amount']);
        unitRaw = metric['unitShort']?.toString();
        if ((unitRaw == null || unitRaw.trim().isEmpty) &&
            metric['unitLong'] != null) {
          unitRaw = metric['unitLong'].toString();
        }
      }

      if (amount == 0.0) {
        amount = _parseNumericAmount(ing?['amount']);
      }

      unitRaw ??= ing?['unit']?.toString();

      final coerced = _coerceToAllowedUnit(
        amount: amount,
        unitRaw: unitRaw,
        ingredientName: name,
      );

      return RecipeIngredient(
        name: name,
        amount: coerced.amount,
        unit: coerced.unit,
      );
    }).toList();

    final steps = <CookingStep>[];
    if (data['analyzedInstructions'] != null &&
        data['analyzedInstructions'].isNotEmpty) {
      for (final step in data['analyzedInstructions'][0]['steps'] ?? []) {
        steps.add(
          CookingStep(
            stepNumber: step['number'] ?? 0,
            instruction: step['step'] ?? '',
            timeMinutes: 0,
          ),
        );
      }
    }

    final nutritionMap = <String, double>{};
    if (data['nutrition'] != null && data['nutrition']['nutrients'] != null) {
      for (final nutrient in data['nutrition']['nutrients']) {
        nutritionMap[nutrient['name'].toString().toLowerCase()] =
            (nutrient['amount'] ?? 0).toDouble();
      }
    }

    final servings = (data['servings'] ?? 1).toDouble().clamp(1, double.infinity);

    final rawServings = data['servings'];
    final servingsCount = (rawServings is num && rawServings > 0)
        ? rawServings.toDouble()
        : 1.0;
    int servingsInt = servingsCount.round();
    if (servingsInt < 1) servingsInt = 1;
    if (servingsInt > 1000) servingsInt = 1000;

    final nutrition = NutritionInfo(
      calories: (nutritionMap['calories'] ?? 0) * servingsCount,
      protein: (nutritionMap['protein'] ?? 0) * servingsCount,
      carbs: (nutritionMap['carbohydrates'] ?? 0) * servingsCount,
      fat: (nutritionMap['fat'] ?? 0) * servingsCount,
      fiber: (nutritionMap['fiber'] ?? 0) * servingsCount,
      sodium: (nutritionMap['sodium'] ?? 0) * servingsCount,
    );

    final rawDishTypes = (data['dishTypes'] as List?) ?? [];
    final dishTypes = rawDishTypes
        .map((type) => type == null ? '' : type.toString().trim())
        .where((type) => type.isNotEmpty)
        .cast<String>()
        .toList();

    final primaryDishType = dishTypes.isNotEmpty ? dishTypes.first : '';

    return RecipeModel(
      id: 'rapid_${data['id']}',
      name: data['title'] ?? 'ไม่ระบุชื่อ',
      description: cleanHtmlTags(data['summary'] ?? ''),
      matchScore: calculateMatchScore(data),
      reason: 'สูตรจาก Spoonacular API',
      ingredients: ingredients,
      missingIngredients: getMissingIngredients(data),
      steps: steps,
      cookingTime: data['readyInMinutes'] ?? 30,
      prepTime: data['preparationMinutes'] ?? 15,
      difficulty: getDifficulty(data['readyInMinutes'] ?? 30),
      servings: servingsInt,
      category: translateDishType(primaryDishType),
      nutrition: nutrition,
      imageUrl: data['image'],
      tags: getTags(data),
      source: 'Spoonacular',
      sourceUrl: data['sourceUrl'],
    );
  }

  // ----------------- Helpers -----------------
  static int calculateMatchScore(Map<String, dynamic> data) {
    final used = data['usedIngredients'] as List? ?? [];
    final missed = data['missedIngredients'] as List? ?? [];
    final total = used.length + missed.length;
    if (total == 0) return 50;
    return ((used.length / total) * 100).round().clamp(30, 100);
  }

  static String translateDishType(String dishType) {
    final map = {
      'main course': 'อาหารจานหลัก',
      'dessert': 'ของหวาน',
      'appetizer': 'อาหารเรียกน้ำย่อย',
      'salad': 'สลัด',
      'soup': 'ซุป',
      'snack': 'ขนม',
      'drink': 'เครื่องดื่ม',
    };
    return map[dishType.toLowerCase()] ?? 'อาหารจานหลัก';
  }

  static String getDifficulty(int time) {
    if (time <= 20) return 'ง่าย';
    if (time <= 45) return 'ปานกลาง';
    return 'ยาก';
  }

  static List<String> getTags(Map<String, dynamic> data) {
    final tags = <String>[];
    if (data['vegetarian'] == true) {
      tags.add('มังสวิรัติ');
      tags.add('vegetarian');
    }
    if (data['vegan'] == true) {
      tags.add('วีแกน');
      tags.add('vegan');
    }
    if (data['glutenFree'] == true) {
      tags.add('ปลอดกลูเตน');
      tags.add('gluten-free');
      tags.add('glutenfree');
    }
    if (data['dairyFree'] == true) {
      tags.add('ปลอดนม');
      tags.add('dairy-free');
      tags.add('dairyfree');
    }
    if (data['cheap'] == true) tags.add('ประหยัด');
    if (data['veryPopular'] == true) tags.add('ยอดนิยม');
    if (data['readyInMinutes'] != null && data['readyInMinutes'] <= 30) {
      tags.add('ทำเร็ว');
    }
    final diets = (data['diets'] as List? ?? [])
        .map((d) => d?.toString()?.trim().toLowerCase() ?? '')
        .where((d) => d.isNotEmpty)
        .toList();
    tags.addAll(diets);
    final cuisines = (data['cuisines'] as List? ?? [])
        .map((c) => c?.toString()?.trim().toLowerCase() ?? '')
        .where((c) => c.isNotEmpty)
        .toList();
    tags.addAll(cuisines);
    return tags;
  }

  static List<String> getMissingIngredients(Map<String, dynamic> data) {
    return (data['missedIngredients'] as List? ?? [])
        .map((i) => i['name']?.toString() ?? '')
        .toList();
  }

  static String cleanHtmlTags(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .trim();
  }
}

double _parseNumericAmount(dynamic raw) {
  if (raw == null) return 0.0;
  if (raw is num) return raw.toDouble();
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 0.0;

    final direct = double.tryParse(trimmed);
    if (direct != null) return direct;

    final parts = trimmed.split(RegExp(r'\s+'));
    double total = 0.0;
    for (final part in parts) {
      if (part.isEmpty) continue;
      final numeric = double.tryParse(part);
      if (numeric != null) {
        total += numeric;
        continue;
      }
      final fraction = part.split('/');
      if (fraction.length == 2) {
        final numerator = double.tryParse(fraction[0]);
        final denominator = double.tryParse(fraction[1]);
        if (numerator != null && denominator != null && denominator != 0) {
          total += numerator / denominator;
          continue;
        }
      }
      return 0.0;
    }
    return total;
  }
  return 0.0;
}

class _AllowedMeasure {
  final double amount;
  final String unit;

  const _AllowedMeasure(this.amount, this.unit);
}

_AllowedMeasure _coerceToAllowedUnit({
  required double amount,
  required String? unitRaw,
  required String ingredientName,
}) {
  if (!amount.isFinite || amount <= 0) {
    return const _AllowedMeasure(0, 'กรัม');
  }

  final lowerName = ingredientName.trim().toLowerCase();
  final normalizedUnit = unitRaw?.trim().toLowerCase() ?? '';
  final cleanedUnit = normalizedUnit.replaceAll('.', '');

  final pieceRule = piece_converter.SmartUnitConverter.pieceRuleFor(
    lowerName,
    cleanedUnit,
  );
  if (pieceRule != null &&
      (piece_converter.SmartUnitConverter.isPieceUnit(cleanedUnit) ||
          pieceRule.matchesUnit(cleanedUnit) ||
          cleanedUnit.isEmpty)) {
    return _AllowedMeasure(amount, pieceRule.displayUnit);
  }

  const gramUnits = {'g', 'gram', 'grams', 'gm', 'gms'};
  const kilogramUnits = {'kg', 'kgs', 'kilogram', 'kilograms'};
  const milliliterUnits = {
    'ml',
    'mls',
    'milliliter',
    'milliliters',
    'millilitre',
    'millilitres',
    'cc',
  };
  const literUnits = {'l', 'lt', 'liter', 'liters', 'litre', 'litres', 'ltr'};

  if (gramUnits.contains(cleanedUnit)) {
    return _AllowedMeasure(amount, 'กรัม');
  }
  if (kilogramUnits.contains(cleanedUnit)) {
    final grams = amount * MeasurementConstants.gramsPerKilogram;
    return grams >= MeasurementConstants.gramsPerKilogram
        ? _AllowedMeasure(
            grams / MeasurementConstants.gramsPerKilogram,
            'กิโลกรัม',
          )
        : _AllowedMeasure(grams, 'กรัม');
  }
  if (cleanedUnit == 'mg' ||
      cleanedUnit == 'milligram' ||
      cleanedUnit == 'milligrams') {
    final grams = amount / MeasurementConstants.milligramsPerGram;
    return grams >= MeasurementConstants.gramsPerKilogram
        ? _AllowedMeasure(
            grams / MeasurementConstants.gramsPerKilogram,
            'กิโลกรัม',
          )
        : _AllowedMeasure(grams, 'กรัม');
  }
  if (piece_converter.SmartUnitConverter.isPieceUnit(cleanedUnit)) {
    final fallbackRule = piece_converter.SmartUnitConverter.pieceRuleFor(
      lowerName,
    );
    final displayUnit = fallbackRule?.displayUnit ?? 'ชิ้น';
    return _AllowedMeasure(amount, displayUnit);
  }

  return _AllowedMeasure(amount, 'กรัม');
}
