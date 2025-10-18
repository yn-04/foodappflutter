import '../models/recipe/recipe.dart';
import 'thai_localizer.dart';

/// 🥘 Adapter สำหรับแปล RecipeModel → ภาษาไทย
class ThaiRecipeAdapter {
  /// แปล Recipe เดียว
  static Future<RecipeModel> translateRecipe(RecipeModel recipe) async {
    try {
      final nameTh = await ThaiLocalizer.toThaiText(recipe.name);
      final descTh = await ThaiLocalizer.toThaiText(recipe.description);
      final reasonTh = await ThaiLocalizer.toThaiText(recipe.reason);

      final ingredientsTh = await Future.wait(
        recipe.ingredients.map(
          (ing) async => RecipeIngredient(
            name: await ThaiLocalizer.toThaiIngredient(ing.name),
            amount: ing.amount,
            unit: ThaiLocalizer.toThaiUnit(ing.unit),
            isOptional: ing.isOptional,
          ),
        ),
      );

      final missingTh = await Future.wait(
        recipe.missingIngredients.map(ThaiLocalizer.toThaiText),
      );

      final stepsTh = await Future.wait(
        recipe.steps.map(
          (s) async => CookingStep(
            stepNumber: s.stepNumber,
            instruction: await ThaiLocalizer.toThaiText(s.instruction),
            timeMinutes: s.timeMinutes,
            tips: await Future.wait(s.tips.map(ThaiLocalizer.toThaiText)),
          ),
        ),
      );

      final tagsTh = <String>[];
      for (final t in recipe.tags) {
        final cuisineTh = ThaiLocalizer.toThaiCuisineTag(t);
        if (cuisineTh != t) {
          tagsTh.add(cuisineTh);
        } else {
          tagsTh.add(await ThaiLocalizer.toThaiText(t));
        }
      }

      return recipe.copyWith(
        name: nameTh,
        description: descTh,
        reason: reasonTh,
        ingredients: ingredientsTh,
        missingIngredients: missingTh,
        steps: stepsTh,
        tags: tagsTh,
        difficulty: await ThaiLocalizer.toThaiText(recipe.difficulty),
        category: await ThaiLocalizer.toThaiText(recipe.category),
        source: recipe.source != null
            ? await ThaiLocalizer.toThaiText(recipe.source!)
            : null,
      );
    } catch (e) {
      print("❌ Translation Error: $e");
      return recipe; // ถ้า error คืนค่าเดิม
    }
  }

  /// แปลหลาย Recipe
  static Future<List<RecipeModel>> translateRecipes(
    List<RecipeModel> recipes,
  ) async {
    return Future.wait(recipes.map(translateRecipe));
  }
}
