//lib/foodreccom/services/fallback_recipe_service.dart
import '../models/ingredient_model.dart';
import '../models/recipe/recipe.dart';

class FallbackRecipeService {
  /// 📌 Smart Fallback Recipes
  List<RecipeModel> generate(List<IngredientModel> ingredients) {
    final fallbackMenus = {
      'ไข่': ['ไข่เจียว', 'ไข่ดาว', 'ไข่ต้ม'],
      'หมู': ['หมูผัดกะเพรา', 'หมูทอดกระเทียม'],
      'ไก่': ['ไก่ผัดพริกแกง', 'ไก่ทอด'],
      'ปลา': ['ปลาทอดน้ำปลา', 'ปลานึ่งมะนาว'],
      'กุ้ง': ['กุ้งอบวุ้นเส้น', 'กุ้งทอดกระเทียม'],
      'ผัก': ['ผัดผักรวม', 'แกงจืดผักกาด'],
    };

    return ingredients.take(3).map((ing) {
      final menus = fallbackMenus.entries
          .firstWhere(
            (entry) => ing.name.contains(entry.key),
            orElse: () => MapEntry(ing.name, ['เมนูจาก${ing.name}']),
          )
          .value;

      return RecipeModel(
        id: 'hybrid_fallback_${ing.name}',
        name: menus[ing.hashCode % menus.length],
        description: 'เมนูที่ใช้ ${ing.name} เป็นหลัก',
        matchScore: ing.priorityScore,
        reason: 'Smart fallback recipe',
        ingredients: [
          RecipeIngredient(
            name: ing.name,
            amount: ing.quantity.toDouble(),
            unit: ing.unit,
          ),
        ],
        missingIngredients: ['เครื่องปรุงพื้นฐาน'],
        steps: [],
        cookingTime: 20,
        prepTime: 10,
        difficulty: 'ง่าย',
        servings: 2,
        category: 'อาหารจานหลัก',
        nutrition: NutritionInfo(
          calories: 250,
          protein: 12,
          carbs: 20,
          fat: 8,
          fiber: 3,
          sodium: 400,
        ),
        source: 'Hybrid Fallback',
        tags: ['อัตโนมัติ', 'ง่าย'],
      );
    }).toList();
  }
}
