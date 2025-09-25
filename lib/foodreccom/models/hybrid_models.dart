//lib/foodreccom/models/hybrid_models.dart

import 'recipe/recipe.dart';

/// 📌 ผลลัพธ์จากการแนะนำแบบ Hybrid (AI + External API)
class HybridRecommendationResult {
  List<RecipeModel> aiRecommendations = [];
  List<RecipeModel> externalRecipes = [];
  List<RecipeModel> combinedRecommendations = [];
  HybridAnalysis? hybridAnalysis;
  DateTime? aiGenerationTime;
  DateTime? externalFetchTime;
  bool isSuccess = false;
  String? error;

  int get aiRecommendationCount => aiRecommendations.length;
  int get externalRecommendationCount => externalRecipes.length;

  Duration? get totalProcessingTime {
    if (aiGenerationTime != null && externalFetchTime != null) {
      return externalFetchTime!.difference(aiGenerationTime!);
    }
    return null;
  }

  Map<String, dynamic> toSummary() {
    return {
      'ai_count': aiRecommendations.length,
      'external_count': externalRecipes.length,
      'combined_count': combinedRecommendations.length,
      'is_success': isSuccess,
      'processing_time_ms': totalProcessingTime?.inMilliseconds,
      'analysis': hybridAnalysis?.toMap(),
    };
  }
}

/// 📌 การวิเคราะห์ผลลัพธ์ Hybrid
class HybridAnalysis {
  final String summary;
  final int aiRecommendationCount;
  final int externalRecommendationCount;
  final int combinedCount;
  final int urgentIngredientsCount;
  final int wastePreventionScore;
  final int diversityScore;
  final Map<String, int> recommendationSources;

  HybridAnalysis({
    required this.summary,
    required this.aiRecommendationCount,
    required this.externalRecommendationCount,
    required this.combinedCount,
    required this.urgentIngredientsCount,
    required this.wastePreventionScore,
    required this.diversityScore,
    required this.recommendationSources,
  });

  /// ✅ สร้างการวิเคราะห์จากผลลัพธ์จริง (AI + API)
  static HybridAnalysis analyze({
    required List<RecipeModel> aiRecipes,
    required List<RecipeModel> externalRecipes,
    required int urgentIngredientsCount,
  }) {
    final combined = [...aiRecipes, ...externalRecipes];

    // คะแนนป้องกันเสีย → วัดจากการ match กับ ingredients ที่ใกล้หมดอายุ
    final wasteScore = (urgentIngredientsCount > 0 && combined.isNotEmpty)
        ? ((combined.where((r) {
                    return r.ingredients.any(
                      (ing) => aiRecipes.any(
                        (ai) => ai.ingredients.any(
                          (a) => a.name.contains(ing.name),
                        ),
                      ),
                    );
                  }).length /
                  combined.length) *
              100)
        : 50;

    // ความหลากหลายของหมวดหมู่
    final categories = combined.map((r) => r.category).toSet();
    final diversityScore =
        ((categories.length / (combined.isEmpty ? 1 : combined.length)) * 100)
            .clamp(0, 100)
            .round();

    return HybridAnalysis(
      summary:
          "AI ${aiRecipes.length} | API ${externalRecipes.length} | รวม ${combined.length} เมนู",
      aiRecommendationCount: aiRecipes.length,
      externalRecommendationCount: externalRecipes.length,
      combinedCount: combined.length,
      urgentIngredientsCount: urgentIngredientsCount,
      wastePreventionScore: wasteScore.round(),
      diversityScore: diversityScore,
      recommendationSources: {
        'ai': aiRecipes.length,
        'external': externalRecipes.length,
      },
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'summary': summary,
      'ai_count': aiRecommendationCount,
      'external_count': externalRecommendationCount,
      'combined_count': combinedCount,
      'urgent_ingredients': urgentIngredientsCount,
      'waste_prevention_score': wastePreventionScore,
      'diversity_score': diversityScore,
      'sources': recommendationSources,
    };
  }

  int get overallScore {
    return ((wastePreventionScore * 0.4) +
            (diversityScore * 0.3) +
            (combinedCount.clamp(0, 10) * 3))
        .round()
        .clamp(0, 100);
  }
}
