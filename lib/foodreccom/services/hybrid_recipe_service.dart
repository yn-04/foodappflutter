// lib/foodreccom/services/hybrid_recipe_service.dart
import 'dart:convert';
import '../models/ingredient_model.dart';
import '../models/recipe/recipe.dart';
import '../models/cooking_history_model.dart';
import '../models/hybrid_models.dart';
import 'enhanced_ai_recommendation_service.dart';
import 'rapidapi_recipe_service.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'api_usage_service.dart';

class HybridRecipeService {
  final EnhancedAIRecommendationService _aiService =
      EnhancedAIRecommendationService();
  final RapidAPIRecipeService _rapidApiService = RapidAPIRecipeService();

  Future<HybridRecommendationResult> getHybridRecommendations(
    List<IngredientModel> ingredients, {
    List<CookingHistory>? cookingHistory,
    int maxExternalRecipes = 5,
    // Optional user overrides/filters
    List<IngredientModel>? manualSelectedIngredients,
    List<String> cuisineFilters = const [], // english lowercase
    Set<String> dietGoals = const {},
    int? minCalories,
    int? maxCalories,
  }) async {
    final result = HybridRecommendationResult();

    try {
      final ingredientPayload =
          ingredients.map((ingredient) => ingredient.toAIFormat()).toList();

      final filterPrompt =
          '''
คุณเป็นผู้ช่วยจัดการวัตถุดิบ
ภารกิจ: เลือกไม่เกิน 6 วัตถุดิบที่ควรหยิบมาใช้ก่อนที่สุด โดยเรียงลำดับจากใกล้หมดอายุที่สุด → ใกล้หมดอายุ → ยังมีเวลา แต่ควรใช้ให้ตรงกับของที่ผู้ใช้มี

แนวทางการตัดสินใจ:
0. ห้ามเลือกวัตถุดิบที่ `is_expired` = true
1. ให้ความสำคัญกับ `days_to_expiry` น้อยที่สุดก่อน (0 หรือ 1 วัน → ด่วนที่สุด)
2. รองลงมาคือวัตถุดิบที่ `days_to_expiry` <= 3 (ใกล้หมดอายุ)
3. หากยังไม่ครบ 6 ให้เติมด้วยวัตถุดิบที่เหลือ โดยเลือกที่มี `days_to_expiry` น้อย และ `priority_score` สูง
4. ห้ามสร้างชื่อใหม่ ต้องเลือกเฉพาะ `name` ที่ให้ไว้เท่านั้น

ข้อมูลวัตถุดิบ (JSON):
${jsonEncode(ingredientPayload)}

ตอบกลับเป็น JSON รูปแบบเดียวเท่านั้น:
{
  "priority_ingredients": ["ชื่อวัตถุดิบ1", "ชื่อวัตถุดิบ2", ...]
}

อย่าใส่คำอธิบายเพิ่มเติม หรือข้อความอื่นนอกเหนือ JSON
''';

      List<IngredientModel> selectedIngredients;
      if (manualSelectedIngredients != null && manualSelectedIngredients.isNotEmpty) {
        selectedIngredients = manualSelectedIngredients.take(6).toList();
        print("👤 ผู้ใช้เลือกวัตถุดิบเอง: ${selectedIngredients.map((i) => i.name).join(', ')}");
      } else {
        final priorityIngredients = await _getPriorityIngredientNames(
          prompt: filterPrompt,
        );
        print("✅ Gemini เลือกวัตถุดิบที่ควรใช้ก่อน: $priorityIngredients");

        selectedIngredients = _selectTopPriorityIngredients(
          allIngredients: ingredients,
          priorityNames: priorityIngredients,
          limit: 6,
        );
      }
      print(
        "📦 ใช้วัตถุดิบ ${selectedIngredients.length} รายการสำหรับ RapidAPI: ${selectedIngredients.map((i) => i.name).join(', ')}",
      );

      // ✅ 2) ดึงเมนูจาก RapidAPI (สูงสุด 5 เมนู) โดยใช้วัตถุดิบที่คัดกรองแล้ว
      if (selectedIngredients.isEmpty) {
        print('⚠️ ไม่มีวัตถุดิบที่ผ่านเกณฑ์สำหรับ RapidAPI');
        result.externalRecipes = [];
      } else {
        result.externalRecipes = await _rapidApiService.searchRecipesByIngredients(
          selectedIngredients,
          maxResults: maxExternalRecipes,
          ranking: 1, // prioritize using as many selected ingredients as possible
          cuisineFilters: cuisineFilters,
          dietGoals: dietGoals,
          minCalories: minCalories,
          maxCalories: maxCalories,
        );
      }
      result.externalFetchTime = DateTime.now();

      // ✅ 3) รวมผลลัพธ์ (ใช้ RapidAPI เท่านั้น แต่ผ่าน AI filter)
      result.combinedRecommendations = [...result.externalRecipes];

      // Log current API usage summary to help monitor quotas
      final usage = await ApiUsageService.summary();
      print('📊 $usage');

      // ✅ 4) วิเคราะห์ผลลัพธ์
      result.hybridAnalysis = HybridAnalysis.analyze(
        aiRecipes: [], // เราใช้ AI แค่ช่วยคัดกรอง ไม่ generate เมนู
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

  /// Helper: parse priority_ingredients JSON
  List<String> _parsePriorityIngredients(String? responseText) {
    if (responseText == null || responseText.isEmpty) return [];
    try {
      final clean = responseText
          .replaceAll("```json", "")
          .replaceAll("```", "")
          .trim();
      final Map<String, dynamic> parsed = jsonDecode(clean);
      final list = parsed['priority_ingredients'] as List?;
      return list?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      print("⚠️ Parse priority ingredients error: $e");
      return [];
    }
  }

  Future<List<String>> _getPriorityIngredientNames({
    required String prompt,
  }) async {
    Future<List<String>> runModel(GenerativeModel model, String label) async {
      try {
        final response = await model.generateContent([
          Content.text(prompt),
        ]);
        final parsed = _parsePriorityIngredients(response.text);
        if (parsed.isNotEmpty) {
          return parsed;
        }
        print('⚠️ $label model returned empty list, will fallback');
      } on GenerativeAIException catch (e) {
        final message = e.message;
        print('⚠️ $label model error: $message');
        final isOverloaded = message.contains('503') ||
            message.toLowerCase().contains('unavailable') ||
            message.toLowerCase().contains('overloaded');
        if (isOverloaded) {
          print('ℹ️ Model overloaded, attempting fallback model');
        }
      } catch (e) {
        print('⚠️ $label model unexpected error: $e');
      }
      return [];
    }

    final primary = await runModel(_aiService.primaryModel, 'Primary');
    if (primary.isNotEmpty) {
      return primary;
    }

    final fallback = await runModel(_aiService.fallbackModel, 'Fallback');
    if (fallback.isNotEmpty) {
      return fallback;
    }

    print('ℹ️ ใช้วิธีเรียงตามวันหมดอายุแทน เนื่องจาก Gemini ใช้งานไม่ได้');
    return [];
  }

  List<IngredientModel> _selectTopPriorityIngredients({
    required List<IngredientModel> allIngredients,
    required List<String> priorityNames,
    int limit = 6,
  }) {
    if (allIngredients.isEmpty) return [];

    final usableIngredients =
        allIngredients.where((ingredient) => !ingredient.isExpired).toList();

    if (usableIngredients.isEmpty) {
      print('ℹ️ ไม่มีวัตถุดิบที่ยังไม่หมดอายุให้เลือก');
      return [];
    }

    final normalizedLookup = <String, IngredientModel>{};
    for (final ingredient in usableIngredients) {
      normalizedLookup[_normalizeName(ingredient.name)] = ingredient;
    }

    final selected = <IngredientModel>[];
    final seen = <String>{};

    void addIngredient(IngredientModel ingredient) {
      final key = _normalizeName(ingredient.name);
      if (seen.add(key) && selected.length < limit) {
        selected.add(ingredient);
      }
    }

    for (final name in priorityNames) {
      final normalized = _normalizeName(name);
      if (normalized.isEmpty) continue;
      final ingredient = _findIngredientByName(
        normalizedLookup: normalizedLookup,
        searchPool: usableIngredients,
        normalizedName: normalized,
      );
      if (ingredient != null) {
        addIngredient(ingredient);
      }
      if (selected.length >= limit) {
        return selected;
      }
    }

    final fallbackSorted = List<IngredientModel>.from(usableIngredients)
      ..sort((a, b) {
        final expiryCompare = a.daysToExpiry.compareTo(b.daysToExpiry);
        if (expiryCompare != 0) return expiryCompare;
        return b.priorityScore.compareTo(a.priorityScore);
      });

    for (final ingredient in fallbackSorted) {
      addIngredient(ingredient);
      if (selected.length >= limit) {
        break;
      }
    }

    return selected;
  }

  IngredientModel? _findIngredientByName({
    required Map<String, IngredientModel> normalizedLookup,
    required List<IngredientModel> searchPool,
    required String normalizedName,
  }) {
    if (normalizedLookup.containsKey(normalizedName)) {
      return normalizedLookup[normalizedName];
    }

    for (final entry in normalizedLookup.entries) {
      if (entry.key.contains(normalizedName) ||
          normalizedName.contains(entry.key)) {
        return entry.value;
      }
    }

    for (final ingredient in searchPool) {
      final ingredientName = _normalizeName(ingredient.name);
      if (ingredientName == normalizedName) {
        return ingredient;
      }
    }

    return null;
  }

  String _normalizeName(String name) => name.trim().toLowerCase();
}
