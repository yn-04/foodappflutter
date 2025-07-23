// lib/services/ai_recommendation_service.dart
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ingredient_model.dart';
import '../models/recipe_model.dart';

class AIRecommendationService {
  static const String _apiKey = 'AIzaSyCy1cWTsLIlBDsY1BfaUpgUw5ArL_aSrc0';
  static const String _cacheKey = 'cached_recommendations';

  late final GenerativeModel _model;

  AIRecommendationService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 4096,
      ),
    );
  }

  // เปลี่ยนชื่อจาก getDetailedRecommendations เป็น getRecommendations
  Future<List<RecipeModel>> getRecommendations(
    List<IngredientModel> ingredients,
  ) async {
    try {
      // ตรวจสอบ cache ก่อน
      final cached = await _getCachedRecommendations(ingredients);
      if (cached != null) {
        print('🎯 ใช้ข้อมูลจาก cache');
        return cached;
      }

      print('🤖 เรียก Gemini AI...');

      final prompt = _buildDetailedPrompt(ingredients);
      final response = await _model
          .generateContent([Content.text(prompt)])
          .timeout(Duration(seconds: 45));

      if (response.text == null) {
        throw Exception('AI ไม่สามารถสร้างคำแนะนำได้');
      }

      final recipes = _parseDetailedResponse(response.text!);

      // บันทึก cache
      await _cacheRecommendations(ingredients, recipes);

      return recipes;
    } catch (e) {
      print('❌ AI Error: $e');
      return _getFallbackRecommendations(ingredients);
    }
  }

  // แทนที่ method _buildDetailedPrompt ในไฟล์ ai_recommendation_service.dart

  // ✅ ปรับปรุง prompt ให้ชัดเจนขึ้น
  String _buildDetailedPrompt(List<IngredientModel> ingredients) {
    final nearExpiry = ingredients.where((i) => i.isNearExpiry).toList();
    final available = ingredients.where((i) => !i.isNearExpiry).toList();

    return '''
คุณเป็นเชฟมืออาชีพและนักโภชนาการ กรุณาแนะนำเมนูอาหาร 3-5 เมนู

**วัตถุดิบใกล้หมดอายุ (ให้ความสำคัญ)**:
${nearExpiry.map((i) => '- ${i.name}: ${i.quantity} ${i.unit} (หมดอายุใน ${i.daysToExpiry} วัน)').join('\n')}

**วัตถุดิบที่มี**:
${available.map((i) => '- ${i.name}: ${i.quantity} ${i.unit}').join('\n')}

**ตอบเฉพาะ JSON รูปแบบนี้เท่านั้น**:

{
  "recommendations": [
    {
      "menu_name": "ไก่ผัดกะเพรา",
      "description": "เมนูยอดฮิต ใช้ไก่และกะเพราที่ใกล้หมดอายุ",
      "match_score": 95,
      "reason": "ใช้ไก่และกะเพราที่ใกล้หมดอายุได้หมด",
      "category": "อาหารจานหลัก",
      "cooking_time": 20,
      "prep_time": 10,
      "difficulty": "ง่าย",
      "servings": 2,
      "ingredients": [
        {"name": "ไก่", "amount": 300, "unit": "กรัม", "is_optional": false},
        {"name": "กะเพรา", "amount": 100, "unit": "กรัม", "is_optional": false},
        {"name": "พริกขี้หนู", "amount": 5, "unit": "เม็ด", "is_optional": true}
      ],
      "missing_ingredients": ["ซอสปรุงรส"],
      "steps": [
        {"step_number": 1, "instruction": "หั่นไก่เป็นชิ้นเล็ก", "time_minutes": 5, "tips": ["หั่นตามเนื้อไก่"]},
        {"step_number": 2, "instruction": "ผัดไก่จนสุก", "time_minutes": 10, "tips": ["ใช้ไฟแรง"]}
      ],
      "nutrition": {"calories": 350, "protein": 25, "carbs": 15, "fat": 20, "fiber": 3, "sodium": 800},
      "tags": ["ง่าย", "ไว", "ไทย"],
      "source": "สูตรดั้งเดิม",
      "source_url": ""
    }
  ]
}

**สำคัญมาก**:
- amount ต้องเป็นตัวเลขเท่านั้น (เช่น 5, 300, 1.5)
- ห้ามใส่ช่วง (เช่น 5-10)
- ห้ามใส่ข้อความอื่นนอกจาก JSON
- ตรวจสอบรูปแบบ JSON ให้ถูกต้อง
- ใส่ครบทุก field ตามตัวอย่าง
''';
  }
  // แทนที่ method _parseDetailedResponse ในไฟล์ ai_recommendation_service.dart

  List<RecipeModel> _parseDetailedResponse(String response) {
    try {
      // ทำความสะอาด response
      String cleanJson = response
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      // หา JSON object
      final jsonStart = cleanJson.indexOf('{');
      final jsonEnd = cleanJson.lastIndexOf('}') + 1;

      if (jsonStart != -1 && jsonEnd > jsonStart) {
        cleanJson = cleanJson.substring(jsonStart, jsonEnd);
      }

      // ✅ แก้ไขปัญหา amount ที่เป็น range (เช่น 5-10)
      cleanJson = _fixJsonIssues(cleanJson);

      final Map<String, dynamic> parsed = json.decode(cleanJson);
      final List<dynamic> recommendations = parsed['recommendations'] ?? [];

      return recommendations
          .map((json) => RecipeModel.fromAI(json))
          .where((recipe) => recipe.name.isNotEmpty)
          .toList();
    } catch (e) {
      print('❌ Parse Error: $e');
      print('Response: $response');
      return [];
    }
  }

  // ✅ ปรับปรุง method สำหรับแก้ไข JSON issues
  String _fixJsonIssues(String jsonString) {
    // แก้ไขปัญหา amount ที่เป็น range
    // เช่น "amount": 5-10 → "amount": "5-10"
    jsonString = jsonString.replaceAllMapped(
      RegExp(r'"amount":\s*(\d+\.?\d*)-(\d+\.?\d*)'),
      (match) => '"amount": "${match.group(1)}-${match.group(2)}"',
    );

    // แก้ไขปัญหา amount ที่เป็นจำนวนเต็มหรือทศนิยมธรรมดา
    // ให้แน่ใจว่าเป็น number ที่ถูกต้อง
    jsonString = jsonString.replaceAllMapped(
      RegExp(r'"amount":\s*"?(\d+\.?\d*)"?(?!["\d-])'),
      (match) => '"amount": ${match.group(1)}',
    );

    // ลบ trailing commas ที่ผิดรูปแบบ
    jsonString = jsonString.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');

    // แก้ไข missing commas ระหว่าง objects
    jsonString = jsonString.replaceAll(RegExp(r'}(\s*{)'), r'},$1');

    // แก้ไข missing commas ระหว่าง arrays
    jsonString = jsonString.replaceAll(RegExp(r'](\s*\[)'), r'],$1');

    // แก้ไขปัญหา quotes ผิดรูปแบบ
    jsonString = jsonString.replaceAll(RegExp(r'([{,]\s*)(\w+):'), r'$1"$2":');

    return jsonString;
  }

  List<RecipeModel> _getFallbackRecommendations(
    List<IngredientModel> ingredients,
  ) {
    final nearExpiry = ingredients.where((i) => i.isNearExpiry).toList();

    if (nearExpiry.isEmpty) {
      return [
        RecipeModel(
          id: 'fallback_1',
          name: 'ข้าวผัดไข่',
          description: 'เมนูง่ายที่ทำได้รวดเร็ว',
          matchScore: 70,
          reason: 'เมนูพื้นฐานที่ทำได้จากวัตถุดิบที่มี',
          ingredients: [
            RecipeIngredient(name: 'ข้าวสวย', amount: 2, unit: 'จาน'),
            RecipeIngredient(name: 'ไข่ไก่', amount: 2, unit: 'ฟอง'),
          ],
          missingIngredients: [],
          steps: [
            CookingStep(
              stepNumber: 1,
              instruction: 'ตีไข่ให้เข้ากัน',
              timeMinutes: 2,
            ),
            CookingStep(
              stepNumber: 2,
              instruction: 'ผัดไข่ให้สุก แล้วใส่ข้าว',
              timeMinutes: 5,
            ),
          ],
          cookingTime: 10,
          prepTime: 5,
          difficulty: 'ง่าย',
          servings: 2,
          category: 'อาหารจานหลัก',
          nutrition: NutritionInfo(
            calories: 350,
            protein: 12,
            carbs: 45,
            fat: 8,
            fiber: 1,
            sodium: 400,
          ),
          source: 'สูตรพื้นฐาน',
        ),
      ];
    }

    return nearExpiry.map((ingredient) {
      return RecipeModel(
        id: 'fallback_${ingredient.name}',
        name: 'เมนูจาก${ingredient.name}',
        description: 'เมนูที่ใช้${ingredient.name}เป็นหลัก',
        matchScore: 60,
        reason:
            'ใช้${ingredient.name}ที่ใกล้หมดอายุใน ${ingredient.daysToExpiry} วัน',
        ingredients: [
          RecipeIngredient(
            name: ingredient.name,
            amount: ingredient.quantity.toDouble(),
            unit: ingredient.unit,
          ),
        ],
        missingIngredients: ['เครื่องปรุง'],
        steps: [
          CookingStep(
            stepNumber: 1,
            instruction: 'เตรียม${ingredient.name}และวัตถุดิบอื่นๆ',
            timeMinutes: 5,
          ),
          CookingStep(
            stepNumber: 2,
            instruction: 'ปรุงอาหารตามวิธีที่ถนัด',
            timeMinutes: 15,
          ),
        ],
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
        source: 'สูตรแนะนำพื้นฐาน',
      );
    }).toList();
  }

  // Cache functions
  Future<void> _cacheRecommendations(
    List<IngredientModel> ingredients,
    List<RecipeModel> recipes,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = {
        'ingredients_hash': _getIngredientsHash(ingredients),
        'recipes': recipes
            .map(
              (r) => {
                'menu_name': r.name,
                'description': r.description,
                'match_score': r.matchScore,
                'reason': r.reason,
                'ingredients': r.ingredients.map((i) => i.toJson()).toList(),
                'missing_ingredients': r.missingIngredients,
                'cooking_time': r.cookingTime,
                'prep_time': r.prepTime,
                'difficulty': r.difficulty,
                'servings': r.servings,
                'category': r.category,
                'nutrition': r.nutrition.toJson(),
                'tags': r.tags,
                'source': r.source,
                'source_url': r.sourceUrl,
              },
            )
            .toList(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      await prefs.setString(_cacheKey, json.encode(cacheData));
    } catch (e) {
      print('Cache save error: $e');
    }
  }

  Future<List<RecipeModel>?> _getCachedRecommendations(
    List<IngredientModel> ingredients,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKey);

      if (cached == null) return null;

      final cacheData = json.decode(cached);
      final timestamp = cacheData['timestamp'] as int;

      // ใช้ cache ไม่เกิน 2 ชั่วโมง
      if (DateTime.now().millisecondsSinceEpoch - timestamp > 7200000) {
        return null;
      }

      final cachedHash = cacheData['ingredients_hash'] as String;
      final currentHash = _getIngredientsHash(ingredients);

      if (cachedHash != currentHash) return null;

      final recipesData = cacheData['recipes'] as List;
      return recipesData.map((data) => RecipeModel.fromAI(data)).toList();
    } catch (e) {
      print('Cache load error: $e');
      return null;
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
}
