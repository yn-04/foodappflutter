// lib/foodreccom/services/enhanced_ai_recommendation_service.dart
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/ingredient_model.dart';
import '../models/recipe/recipe.dart';
import '../models/cooking_history_model.dart';
import 'cooking_service.dart';
import 'api_key_checker.dart';

class EnhancedAIRecommendationService {
  static const String _cacheKey = 'enhanced_cached_recommendations';

  late List<String> _apiKeys;
  int _currentKeyIndex = 0;

  late GenerativeModel _primaryModel;
  late GenerativeModel _fallbackModel;

  final CookingService _cookingService = CookingService();

  EnhancedAIRecommendationService() {
    final apiKeysStr = dotenv.env['GEMINI_API_KEYS'];
    if (apiKeysStr == null || apiKeysStr.isEmpty) {
      throw Exception('❌ GEMINI_API_KEYS is missing in .env');
    }

    _apiKeys = apiKeysStr.split(',').map((k) => k.trim()).toList();

    // ✅ init model ทันทีด้วย key ตัวแรก ป้องกัน LateInitializationError
    _initModels();

    // ✅ แล้วค่อยไปเช็คว่า key ไหนใช้ได้จริง
    final checker = ApiKeyChecker(_apiKeys);
    checker.checkKeys().then((validKeys) {
      if (validKeys.isEmpty) {
        throw Exception("❌ ไม่มี API Key ไหนที่ใช้ได้เลย");
      }
      _apiKeys = validKeys;
      print("🔑 ใช้งานได้ ${_apiKeys.length} keys");
      _initModels(); // refresh ด้วย key ที่ตรวจแล้ว
    });
  }

  void _initModels() {
    final apiKey = _apiKeys[_currentKeyIndex];
    print(
      "👉 Using API Key[${_currentKeyIndex + 1}/${_apiKeys.length}]: ${apiKey.substring(0, 6)}...",
    );

    _primaryModel = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.8,
        topK: 40,
        topP: 0.9,
        maxOutputTokens: 4096,
        responseMimeType: "application/json",
      ),
    );

    _fallbackModel = GenerativeModel(
      model: 'gemini-2.5-pro',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.8,
        topK: 50,
        topP: 0.95,
        maxOutputTokens: 6144,
        responseMimeType: "application/json",
      ),
    );
  }

  void _rotateApiKey() {
    _currentKeyIndex = (_currentKeyIndex + 1) % _apiKeys.length;
    _initModels();
  }

  Future<List<RecipeModel>> getEnhancedRecommendations(
    List<IngredientModel> ingredients, {
    List<CookingHistory>? cookingHistory,
  }) async {
    try {
      cookingHistory ??= await _cookingService.getCookingHistory(limitDays: 30);

      print("⚡ เรียก Gemini-1.5-Flash (forced refresh)...");
      final prompt = _buildEnhancedPrompt(ingredients, cookingHistory);

      String? responseText;
      try {
        final response = await _primaryModel
            .generateContent([Content.text(prompt)])
            .timeout(const Duration(seconds: 60));
        responseText = response.text;
      } catch (e) {
        final errorStr = e.toString();
        if (errorStr.contains("Quota") || errorStr.contains("429")) {
          print("⚠️ Quota หมด → ใช้ pro");
          final response = await _fallbackModel
              .generateContent([Content.text(prompt)])
              .timeout(const Duration(seconds: 60));
          responseText = response.text;
        } else {
          rethrow;
        }
      }

      if (responseText == null) throw Exception('AI ไม่สามารถสร้างคำแนะนำได้');

      final recipes = _parseDetailedResponse(responseText);

      // ✅ เก็บ cache backup เท่านั้น
      await _cacheRecommendations(ingredients, recipes, cookingHistory);

      return recipes;
    } catch (e) {
      print("❌ Enhanced AI Error: $e");
      _rotateApiKey();
      return _getSmartFallbackRecommendations(ingredients, cookingHistory);
    }
  }

  String _buildEnhancedPrompt(
    List<IngredientModel> ingredients,
    List<CookingHistory> history,
  ) {
    return '''
คุณเป็นเชฟ AI ที่มีหน้าที่แนะนำเมนูอาหารจากวัตถุดิบที่มีอยู่
- วัตถุดิบ: ${ingredients.map((i) => "${i.name} (${i.quantity}${i.unit})").join(", ")}
- ประวัติการทำอาหารล่าสุด: ${history.map((h) => h.recipeName).join(", ")}
แนะนำ 5 เมนูที่เหมาะสม พร้อมเหตุผล, ส่วนผสม, วิธีทำ, โภชนาการ
ตอบกลับเป็น JSON:
{
  "recommendations": [...]
}
''';
  }

  List<RecipeModel> _parseDetailedResponse(String response) {
    try {
      final cleanJson = _sanitizeJson(response);
      final parsed = json.decode(cleanJson) as Map<String, dynamic>;
      final recs = parsed['recommendations'] as List? ?? [];
      return recs.map((json) => RecipeModel.fromAI(json)).toList();
    } catch (e) {
      print("❌ Enhanced Parse Error: $e");
      return [];
    }
  }

  String _sanitizeJson(String response) {
    String clean = response
        .replaceAll("```json", "")
        .replaceAll("```", "")
        .trim();

    final start = clean.indexOf("{");
    final end = clean.lastIndexOf("}") + 1;
    if (start != -1 && end > start) clean = clean.substring(start, end);

    // ✅ case: amount: 1-2 → ค่าเฉลี่ย
    clean = clean.replaceAllMapped(
      RegExp(r'"amount":\s*(\d+\.?\d*)-(\d+\.?\d*)'),
      (m) {
        final avg = (double.parse(m.group(1)!) + double.parse(m.group(2)!)) / 2;
        return '"amount": $avg';
      },
    );

    // ✅ case: nutrition field เป็น string → ดึงเลขออกมา
    clean = clean.replaceAllMapped(
      RegExp(r'"(calories|protein|carbs|fat|fiber|sodium)"\s*:\s*"([^"]+)"'),
      (m) {
        final field = m.group(1)!;
        final valueStr = m.group(2)!;

        // หาตัวเลขทั้งหมดใน string
        final matches = RegExp(
          r'(\d+\.?\d*)',
        ).allMatches(valueStr).map((e) => e.group(1)!).toList();

        if (matches.isEmpty) return '"$field": 0';
        if (matches.length == 1) return '"$field": ${matches.first}';

        // มี range เช่น "250-300"
        final avg =
            (double.parse(matches.first) + double.parse(matches.last)) / 2;
        return '"$field": $avg';
      },
    );

    // ✅ ลบ comma เกิน
    clean = clean.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');

    return clean;
  }

  List<RecipeModel> _getSmartFallbackRecommendations(
    List<IngredientModel> ingredients,
    List<CookingHistory>? history,
  ) {
    if (ingredients.isEmpty) {
      return [
        RecipeModel(
          id: 'fallback_basic',
          name: 'ข้าวผัดไข่',
          description: 'เมนูง่าย ใช้วัตถุดิบพื้นฐาน',
          matchScore: 60,
          reason: 'เมนู fallback พื้นฐาน',
          ingredients: [
            RecipeIngredient(name: 'ข้าวสวย', amount: 1, unit: 'จาน'),
            RecipeIngredient(name: 'ไข่ไก่', amount: 1, unit: 'ฟอง'),
          ],
          missingIngredients: [],
          steps: [],
          cookingTime: 10,
          prepTime: 5,
          difficulty: 'ง่าย',
          servings: 1,
          category: 'อาหารจานหลัก',
          nutrition: NutritionInfo(
            calories: 350,
            protein: 12,
            carbs: 45,
            fat: 8,
            fiber: 1,
            sodium: 400,
          ),
          source: 'Fallback',
        ),
      ];
    }

    return ingredients.take(3).map((i) {
      return RecipeModel(
        id: 'fallback_${i.name}',
        name: 'เมนูจาก${i.name}',
        description: 'ใช้ ${i.name} เป็นวัตถุดิบหลัก',
        matchScore: i.priorityScore,
        reason: 'เมนู fallback จากวัตถุดิบที่มี',
        ingredients: [
          RecipeIngredient(name: i.name, amount: i.quantity, unit: i.unit),
        ],
        missingIngredients: ['เครื่องปรุง'],
        steps: [],
        cookingTime: 20,
        prepTime: 5,
        difficulty: 'ง่าย',
        servings: 2,
        category: 'อาหารจานหลัก',
        nutrition: NutritionInfo(
          calories: 300,
          protein: 15,
          carbs: 30,
          fat: 10,
          fiber: 3,
          sodium: 500,
        ),
        source: 'Fallback',
      );
    }).toList();
  }

  Future<void> _cacheRecommendations(
    List<IngredientModel> ingredients,
    List<RecipeModel> recipes,
    List<CookingHistory> history,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      final cacheKey = '${_cacheKey}_$userId';

      final cacheData = {
        'ingredients_hash': _getIngredientsHash(ingredients),
        'history_hash': _getHistoryHash(history),
        'recipes': recipes.map((r) => r.toJson()).toList(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await prefs.setString(cacheKey, json.encode(cacheData));
      print("✅ Enhanced cache saved (backup only) for $userId");
    } catch (e) {
      print('⚠️ Enhanced cache save error: $e');
    }
  }

  String _getIngredientsHash(List<IngredientModel> ingredients) {
    final sorted =
        ingredients
            .map((i) => '${i.name}-${i.quantity}-${i.daysToExpiry}')
            .toList()
          ..sort();
    return sorted.join('|');
  }

  String _getHistoryHash(List<CookingHistory> history) {
    final recent = history
        .take(5)
        .map((h) => '${h.recipeName}-${h.cookedAt.day}')
        .join('|');
    return recent;
  }
}
