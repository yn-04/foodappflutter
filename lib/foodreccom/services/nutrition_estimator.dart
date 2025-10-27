import 'package:my_app/common/measurement_constants.dart';

import '../models/recipe/recipe.dart';

class NutritionEstimator {
  // Very rough per-100g nutrition table (kcal, protein, carbs, fat, fiber, sodium mg)
  static final Map<String, List<double>> _per100g = {
    'rice': [130, 2.4, 28, 0.3, 0.4, 1],
    'ข้าว': [130, 2.4, 28, 0.3, 0.4, 1],
    'sticky rice': [169, 3.5, 37, 0.3, 0.9, 1],
    'egg': [155, 13, 1.1, 11, 0, 124],
    'ไข่': [155, 13, 1.1, 11, 0, 124],
    'pork': [242, 27, 0, 14, 0, 62],
    'หมู': [242, 27, 0, 14, 0, 62],
    'chicken': [165, 31, 0, 3.6, 0, 74],
    'ไก่': [165, 31, 0, 3.6, 0, 74],
    'garlic': [149, 6.4, 33, 0.5, 2.1, 17],
    'กระเทียม': [149, 6.4, 33, 0.5, 2.1, 17],
    'onion': [40, 1.1, 9, 0.1, 1.7, 4],
    'หอมใหญ่': [40, 1.1, 9, 0.1, 1.7, 4],
    'chili': [40, 2, 9, 0.4, 1.5, 7],
    'พริก': [40, 2, 9, 0.4, 1.5, 7],
    'holy basil': [23, 3.2, 2.7, 0.6, 1.6, 4],
    'กะเพรา': [23, 3.2, 2.7, 0.6, 1.6, 4],
    'chinese kale': [35, 2.6, 4.5, 0.7, 2.6, 20],
    'คะน้า': [35, 2.6, 4.5, 0.7, 2.6, 20],
    'oil': [884, 0, 0, 100, 0, 0],
    'น้ำมัน': [884, 0, 0, 100, 0, 0],
    'sugar': [387, 0, 100, 0, 0, 0],
    'น้ำตาล': [387, 0, 100, 0, 0, 0],
    'soy sauce': [53, 8, 5.6, 0.6, 0.8, 5493],
    'ซีอิ๊ว': [53, 8, 5.6, 0.6, 0.8, 5493],
    'oyster sauce': [51, 1.3, 11, 0.2, 0, 2000],
    'ซอสหอยนางรม': [51, 1.3, 11, 0.2, 0, 2000],
  };

  static NutritionInfo estimateForRecipe(RecipeModel recipe) {
    double kcal = 0, protein = 0, carbs = 0, fat = 0, fiber = 0, sodium = 0;

    for (final ing in recipe.ingredients) {
      final grams = _toGrams(ing.name, ing.numericAmount, ing.unit);
      if (grams <= 0) continue;

      final key = _matchKey(ing.name);
      if (key == null) continue;
      final per = _per100g[key]!; // safe since matched
      final factor = grams / 100.0;
      kcal += per[0] * factor;
      protein += per[1] * factor;
      carbs += per[2] * factor;
      fat += per[3] * factor;
      fiber += per[4] * factor;
      sodium += per[5] * factor;
    }

    return NutritionInfo(
      calories: kcal,
      protein: protein,
      carbs: carbs,
      fat: fat,
      fiber: fiber,
      sodium: sodium,
    );
  }

  static String? _matchKey(String name) {
    final n = name.trim().toLowerCase();
    for (final k in _per100g.keys) {
      if (n == k || n.contains(k)) return k;
    }
    return null;
  }

  static double _toGrams(String name, double amount, String unitRaw) {
    final unit = unitRaw.trim().toLowerCase();
    if (unit.isEmpty) {
      // special cases by ingredient name
      final n = name.toLowerCase();
      if (n.contains('egg') || n.contains('ไข่')) return amount * 50; // ~1 egg 50g
      return amount * 100; // default guess per piece
    }

    // mass units
    if (unit == 'g' || unit == 'gram' || unit == 'grams' || unit == 'กรัม') {
      return amount;
    }
    if (unit == 'kg' || unit == 'กก' || unit == 'กิโลกรัม') {
      return amount * MeasurementConstants.gramsPerKilogram;
    }

    // volume/simple units (approx to grams)
    if (unit == 'ml' || unit == 'มล' || unit == 'มิลลิลิตร') {
      return amount; // assume density 1
    }
    if (unit == 'l' || unit == 'ลิตร') {
      return amount * MeasurementConstants.millilitersPerLiter;
    }
    if (unit == 'tbsp' || unit == 'tablespoon' || unit == 'ช้อนโต๊ะ') {
      return amount * MeasurementConstants.millilitersPerTablespoon;
    }
    if (unit == 'tsp' || unit == 'teaspoon' || unit == 'ช้อนชา') {
      return amount * MeasurementConstants.millilitersPerTeaspoon;
    }
    if (unit == 'cup' || unit == 'ถ้วย') {
      return amount * MeasurementConstants.millilitersPerCup;
    }
    if (unit == 'pcs' || unit == 'pc' || unit == 'ชิ้น' || unit == 'ฟอง') {
      final n = name.toLowerCase();
      if (n.contains('egg') || n.contains('ไข่')) return amount * 50;
      return amount * 100; // generic piece size
    }

    return amount * 100; // fallback
  }
}
