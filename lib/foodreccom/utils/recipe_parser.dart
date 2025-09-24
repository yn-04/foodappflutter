//lib/foodreccom/utils/recipe_parser.dart
import '../models/recipe/recipe.dart';

class RecipeParser {
  /// แปลงข้อมูล Spoonacular API → RecipeModel
  static RecipeModel parseSpoonacularRecipe(Map<String, dynamic> data) {
    final ingredients = (data['extendedIngredients'] as List? ?? [])
        .map(
          (ing) => RecipeIngredient(
            name: ing['name'] ?? '',
            amount: (ing['amount'] ?? 0).toDouble(),
            unit: ing['unit'] ?? '',
          ),
        )
        .toList();

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

    final nutrition = NutritionInfo(
      calories: nutritionMap['calories'] ?? 0,
      protein: nutritionMap['protein'] ?? 0,
      carbs: nutritionMap['carbohydrates'] ?? 0,
      fat: nutritionMap['fat'] ?? 0,
      fiber: nutritionMap['fiber'] ?? 0,
      sodium: nutritionMap['sodium'] ?? 0,
    );

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
      servings: data['servings'] ?? 2,
      category: translateDishType(
        (data['dishTypes'] as List?)?.first?.toString() ?? '',
      ),
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
    if (data['vegetarian'] == true) tags.add('มังสวิรัติ');
    if (data['vegan'] == true) tags.add('วีแกน');
    if (data['glutenFree'] == true) tags.add('ปลอดกลูเตน');
    if (data['dairyFree'] == true) tags.add('ปลอดนม');
    if (data['cheap'] == true) tags.add('ประหยัด');
    if (data['veryPopular'] == true) tags.add('ยอดนิยม');
    if (data['readyInMinutes'] != null && data['readyInMinutes'] <= 30) {
      tags.add('ทำเร็ว');
    }
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
