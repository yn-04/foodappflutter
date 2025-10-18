//lib/foodreccom/utils/ingredient_utils.dart
import '../models/ingredient_model.dart';
import '../models/cooking_history_model.dart';

/// ---- Ingredient Matching ----
bool ingredientsMatch(String available, String required) {
  final a = available.toLowerCase();
  final r = required.toLowerCase();
  return a.contains(r) ||
      r.contains(a) ||
      _getSimilarIngredients(a).contains(r);
}

/// Map ของ alias วัตถุดิบ
Set<String> _getSimilarIngredients(String ingredient) {
  final similarMap = {
    'ไก่': {'chicken', 'poultry'},
    'หมู': {'pork', 'pig'},
    'เนื้อ': {'beef', 'meat'},
    'ปลา': {'fish', 'salmon', 'tuna'},
    'กุ้ง': {'shrimp', 'prawn'},
    'หอม': {'onion', 'shallot'},
    'กระเทียม': {'garlic'},
    'มะเขือเทศ': {'tomato'},
    'มะนาว': {'lime', 'lemon'},
    'พริก': {'chili', 'pepper'},
  };

  for (final entry in similarMap.entries) {
    if (ingredient.contains(entry.key)) {
      return entry.value;
    }
    for (final similar in entry.value) {
      if (ingredient.contains(similar)) {
        return {entry.key};
      }
    }
  }
  return {};
}

/// ---- Utilization Rate ----
double calculateNewUtilizationRate(
  double currentRate,
  double usedAmount,
  double initialQuantity,
) {
  final usageRatio = usedAmount / initialQuantity;
  return ((currentRate * 0.8) + (usageRatio * 0.2)).clamp(0.0, 1.0);
}

/// ---- Cooking History Helpers ----
Map<String, int> summarizeFavoriteCategories(List<CookingHistory> history) {
  final categories = <String, int>{};
  for (final record in history) {
    categories[record.recipeCategory] =
        (categories[record.recipeCategory] ?? 0) + 1;
  }
  return Map.fromEntries(
    categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );
}

List<String> findLessUsedIngredients(
  List<CookingHistory> history,
  List<IngredientModel> available,
) {
  final usage = <String, int>{};

  for (final record in history) {
    for (final ing in record.usedIngredients) {
      usage[ing.name] = (usage[ing.name] ?? 0) + 1;
    }
  }

  return available
      .where((ing) => (usage[ing.name] ?? 0) == 0)
      .map((ing) => ing.name)
      .toList();
}
