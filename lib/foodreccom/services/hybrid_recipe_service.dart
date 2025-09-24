//lib/foodreccom/services/hybrid_recipe_service.dart
import '../models/ingredient_model.dart';
import '../models/recipe/recipe.dart';
import '../models/cooking_history_model.dart';
import '../models/hybrid_models.dart';
import 'enhanced_ai_recommendation_service.dart';
import 'rapidapi_recipe_service.dart';

class HybridRecipeService {
  final EnhancedAIRecommendationService _aiService =
      EnhancedAIRecommendationService();
  final RapidAPIRecipeService _rapidApiService = RapidAPIRecipeService();

  Future<HybridRecommendationResult> getHybridRecommendations(
    List<IngredientModel> ingredients, {
    List<CookingHistory>? cookingHistory,
    int maxExternalRecipes = 5,
  }) async {
    final result = HybridRecommendationResult();

    try {
      // 1) เรียก Gemini (AI)final result = await HybridRecipeService().getHybridRecommendations(ingredients);
      result.aiRecommendations = await _aiService.getEnhancedRecommendations(
        ingredients,
        cookingHistory: cookingHistory,
      );
      result.aiGenerationTime = DateTime.now();

      // 2) เรียก RapidAPI (External)
      result.externalRecipes = await _rapidApiService
          .searchRecipesByIngredients(
            ingredients.take(5).toList(),
            maxResults: maxExternalRecipes,
          );
      result.externalFetchTime = DateTime.now();

      // 3) รวมผลลัพธ์
      result.combinedRecommendations = [
        ...result.aiRecommendations,
        ...result.externalRecipes,
      ];

      // 4) วิเคราะห์ผลลัพธ์ด้วย HybridAnalysis.analyze()
      result.hybridAnalysis = HybridAnalysis.analyze(
        aiRecipes: result.aiRecommendations,
        externalRecipes: result.externalRecipes,
        urgentIngredientsCount: ingredients
            .where((i) => i.isUrgentExpiry)
            .length,
      );

      result.isSuccess = true;
    } catch (e) {
      result.error = e.toString();
      result.isSuccess = false;
      print("❌ HybridRecommendation Error: $e");
    }

    return result;
  }
}
