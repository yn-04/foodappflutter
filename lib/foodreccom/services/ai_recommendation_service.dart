//lib/foodreccom/services/ai_recommendation_service.dart
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/ingredient_model.dart';
import '../models/recipe/recipe.dart';

class ApiKeyChecker {
  final List<String> _apiKeys;
  final List<String> _validKeys = [];

  ApiKeyChecker(this._apiKeys);

  String _mask(String key) {
    if (key.isEmpty) return '(empty)';
    final previewLength = key.length >= 6 ? 6 : key.length;
    final preview = key.substring(0, previewLength);
    final suffix = key.length > previewLength ? '...' : '';
    return '$preview$suffix';
  }

  Future<List<String>> checkKeys() async {
    _validKeys.clear();
    for (var key in _apiKeys) {
      final primary = (dotenv.env['GEMINI_PRIMARY_MODEL'] ?? 'gemini-1.5-flash-8b').trim();
      final model = GenerativeModel(model: primary.isEmpty ? 'gemini-1.5-flash-8b' : primary, apiKey: key);
      try {
        final response = await model
            .generateContent([Content.text("ping")])
            .timeout(const Duration(seconds: 5));
        if (response.text != null && response.text!.isNotEmpty) {
          print("✅ Key ใช้ได้: ${_mask(key)}");
          _validKeys.add(key);
        }
      } catch (e) {
        print("❌ Key ใช้ไม่ได้/Quota หมด: ${_mask(key)} → $e");
      }
    }
    return _validKeys;
  }
}

class AIRecommendationService {
  static const String _cacheKey = 'cached_recommendations';

  final FirebaseAuth _auth = FirebaseAuth.instance;

  late int _rateLimitMs;
  late int _cacheDurationMs;
  late List<String> _apiKeys;
  int _currentKeyIndex = 0;

  late GenerativeModel _primaryModel;
  late GenerativeModel _fallbackModel;

  static final Map<String, int> _lastRequestTime = {};

  AIRecommendationService() {
    final apiKeysStr = dotenv.env['GEMINI_API_KEYS'];
    if (apiKeysStr == null || apiKeysStr.isEmpty) {
      throw Exception('❌ GEMINI_API_KEYS is missing in .env');
    }
    _apiKeys = apiKeysStr
        .split(',')
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();

    _rateLimitMs = int.tryParse(dotenv.env['AI_RATE_LIMIT'] ?? '') ?? 30000;
    _cacheDurationMs =
        int.tryParse(dotenv.env['AI_CACHE_DURATION'] ?? '') ?? 7200000;

    print("⚙️ RateLimit=$_rateLimitMs ms | CacheDuration=$_cacheDurationMs ms");

    final checker = ApiKeyChecker(_apiKeys);
    checker.checkKeys().then((validKeys) {
      if (validKeys.isEmpty) {
        print("⚠️ ไม่มี Gemini key ที่ใช้ได้ — จะใช้ fallback เท่านั้น");
        return;
      }
      _apiKeys = validKeys;
      print("🔑 ใช้งานได้ ${_apiKeys.length} keys");
      _initModels();
    });
  }

  String _maskKey(String key) {
    if (key.isEmpty) return '(empty)';
    final previewLength = key.length >= 6 ? 6 : key.length;
    final preview = key.substring(0, previewLength);
    final suffix = key.length > previewLength ? '...' : '';
    return '$preview$suffix';
  }

  void _initModels() {
    final apiKey = _apiKeys[_currentKeyIndex];
    print(
      "👉 Using API Key[${_currentKeyIndex + 1}/${_apiKeys.length}]: ${_maskKey(apiKey)}",
    );

    _primaryModel = GenerativeModel(
      model: 'gemini-1.5-flash-8b',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 4096,
        responseMimeType: "application/json",
      ),
    );

    _fallbackModel = GenerativeModel(
      model: 'gemini-1.5-pro-002',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        topK: 40,
        topP: 0.9,
        maxOutputTokens: 6144,
        responseMimeType: "application/json",
      ),
    );
  }

  void _rotateApiKey() {
    _currentKeyIndex = (_currentKeyIndex + 1) % _apiKeys.length;
    print("🔄 Rotate API Key → index=$_currentKeyIndex");
    _initModels();
  }

  String _getUserCacheKey() {
    final user = _auth.currentUser;
    return user == null ? _cacheKey : "${_cacheKey}_${user.uid}";
  }

  Future<List<RecipeModel>> getRecommendations(
    List<IngredientModel> ingredients, {
    bool forceRefresh = false, // ✅ เพิ่ม parameter นี้
  }) async {
    bool _geminiEnabled() {
      final v = (dotenv.env['AI_GEMINI_ENABLED'] ?? 'true').trim().toLowerCase();
      return !(v == 'false' || v == '0' || v == 'off');
    }

    if (!_geminiEnabled()) {
      print('🧠 Gemini disabled via env → use cache/fallback');
      final cached = await _getCachedRecommendations(ingredients);
      if (cached != null) return cached;
      return _getFallbackRecommendations(ingredients);
    }
    final userId = _auth.currentUser?.uid ?? 'guest';
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastTime = _lastRequestTime[userId] ?? 0;

    // Rate limit (ยกเว้นถ้า forceRefresh = true)
    if (!forceRefresh && now - lastTime < _rateLimitMs) {
      print("⏳ Rate limit → ใช้ cache/fallback");
      final cached = await _getCachedRecommendations(ingredients);
      if (cached != null) return cached;
      return _getFallbackRecommendations(ingredients);
    }

    _lastRequestTime[userId] = now;

    // Cache (ยกเว้นถ้า forceRefresh = true)
    if (!forceRefresh) {
      final cached = await _getCachedRecommendations(ingredients);
      if (cached != null) {
        print('🎯 ใช้ข้อมูลจาก cache (user=$userId)');
        return cached;
      }
    } else {
      print("🔄 Force refresh → ข้าม cache");
    }

    // AI call
    print('🤖 เรียก Gemini...');
    final prompt = _buildPrompt(ingredients);

    String? responseText;
    try {
      final response = await _primaryModel
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 60));
      responseText = response.text;
    } catch (e) {
      if (e.toString().contains("Quota") || e.toString().contains("429")) {
        print("🚫 Quota เต็ม → Rotate Key");
        _rotateApiKey();
        return getRecommendations(ingredients, forceRefresh: forceRefresh);
      }
      print("⚠️ Flash error → ใช้ Pro");
      final response = await _fallbackModel
          .generateContent([Content.text(prompt)])
          .timeout(const Duration(seconds: 60));
      responseText = response.text;
    }

    if (responseText == null) {
      print("❌ ไม่มี response");
      return _getFallbackRecommendations(ingredients);
    }

    final recipes = _parseRecipes(responseText);
    await _cacheRecommendations(ingredients, recipes);
    return recipes;
  }

  String _buildPrompt(List<IngredientModel> ingredients) {
    final nearExpiry = ingredients.where((i) => i.isNearExpiry).toList();
    final available = ingredients.where((i) => !i.isNearExpiry).toList();

    return '''
คุณเป็นเชฟ AI แนะนำเมนูอาหาร 3-5 เมนู ใช้วัตถุดิบใกล้หมดอายุก่อน
**ใกล้หมดอายุ**:
${nearExpiry.map((i) => '- ${i.name}: ${i.quantity} ${i.unit} (${i.daysToExpiry} วัน)').join('\n')}
**ที่มี**:
${available.map((i) => '- ${i.name}: ${i.quantity} ${i.unit}').join('\n')}
ตอบ JSON:
{
 "recommendations": [ ... ]
}
''';
  }

  List<RecipeModel> _parseRecipes(String response) {
    try {
      final cleanJson = _sanitizeJson(response);
      final parsed = json.decode(cleanJson) as Map<String, dynamic>;
      final recs = parsed['recommendations'] as List? ?? [];
      return recs.map((r) => RecipeModel.fromAI(r)).toList();
    } catch (e) {
      print("❌ Parse error: $e");
      print("Raw: $response");
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

    clean = clean.replaceAllMapped(
      RegExp(r'"amount":\s*(\d+\.?\d*)-(\d+\.?\d*)'),
      (m) {
        final avg = (double.parse(m.group(1)!) + double.parse(m.group(2)!)) / 2;
        return '"amount": $avg';
      },
    );

    clean = clean.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');
    return clean;
  }

  // --- Cache ---
  Future<void> _cacheRecommendations(
    List<IngredientModel> ingredients,
    List<RecipeModel> recipes,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'ingredients_hash': _getIngredientsHash(ingredients),
        'recipes': recipes.map((r) => r.toJson()).toList(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_getUserCacheKey(), json.encode(cacheData));
      print("✅ Cache saved (user=${_auth.currentUser?.uid})");
    } catch (e) {
      print('❌ Cache save error: $e');
    }
  }

  Future<List<RecipeModel>?> _getCachedRecommendations(
    List<IngredientModel> ingredients,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_getUserCacheKey());
      if (cached == null) return null;

      final data = json.decode(cached);
      final timestamp = data['timestamp'] as int;

      if (DateTime.now().millisecondsSinceEpoch - timestamp >
          _cacheDurationMs) {
        print("⌛ Cache expired");
        return null;
      }

      if (data['ingredients_hash'] != _getIngredientsHash(ingredients)) {
        print("🔄 Cache mismatch");
        return null;
      }

      final recipesData = data['recipes'] as List;
      return recipesData.map((d) => RecipeModel.fromAI(d)).toList();
    } catch (e) {
      print('❌ Cache load error: $e');
      return null;
    }
  }

  // --- Fallback ---
  List<RecipeModel> _getFallbackRecommendations(
    List<IngredientModel> ingredients,
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
        reason: 'เมนู fallback',
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

  // --- Helpers ---
  String _getIngredientsHash(List<IngredientModel> ingredients) {
    final sorted =
        ingredients
            .map((i) => '${i.name}-${i.quantity}-${i.daysToExpiry}')
            .toList()
          ..sort();
    return sorted.join('|');
  }
}
