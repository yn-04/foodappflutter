// lib/foodreccom/services/enhanced_ai_recommendation_service.dart
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/foodreccom/constants/nutrition_thresholds.dart';
import 'package:my_app/foodreccom/utils/allergy_utils.dart';
import 'package:my_app/foodreccom/utils/shopping_item_extensions.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';

import 'api_key_checker.dart';

class EnhancedAIRecommendationService {
  late List<String> _apiKeys;
  int _currentKeyIndex = 0;

  late GenerativeModel _primaryModel;
  late GenerativeModel _fallbackModel;
  // Defaults tuned for google_generative_ai ^0.4.x (v1beta): use gemini-pro
  String _primaryModelName = 'gemini-pro';
  String _fallbackModelName = 'gemini-pro';
  bool _useSdk = false;

  /// ✅ expose ให้ HybridRecipeService ใช้
  GenerativeModel get primaryModel => _primaryModel;
  GenerativeModel get fallbackModel => _fallbackModel;
  bool get canUseSdk => _useSdk;

  EnhancedAIRecommendationService() {
    final apiKeysStr = dotenv.env['GEMINI_API_KEYS'];
    if (apiKeysStr == null || apiKeysStr.isEmpty) {
      _apiKeys = [];
      print('⚠️ GEMINI_API_KEYS missing — AI insight will use fallback.');
    } else {
      _apiKeys = apiKeysStr
          .split(',')
          .map((k) => k.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    // allow env override of model names
    final envPrimary = (dotenv.env['GEMINI_PRIMARY_MODEL'] ?? '').trim();
    final envFallback = (dotenv.env['GEMINI_FALLBACK_MODEL'] ?? '').trim();
    if (envPrimary.isNotEmpty) _primaryModelName = envPrimary;
    if (envFallback.isNotEmpty) _fallbackModelName = envFallback;

    final sdkPref = (dotenv.env['GEMINI_USE_SDK'] ?? 'false')
        .trim()
        .toLowerCase();
    _useSdk = sdkPref == 'true' || sdkPref == '1' || sdkPref == 'on';

    // init with first key if any to avoid nulls
    _initModels();

    // ตรวจสอบว่า key ไหนใช้ได้จริง (non-fatal)
    if (_apiKeys.isNotEmpty) {
      final checker = ApiKeyChecker(_apiKeys);
      checker.checkKeys().then((validKeys) {
        if (validKeys.isEmpty) {
          print('⚠️ No valid Gemini keys — will rely on local fallback.');
          return;
        }
        _apiKeys = validKeys;
        print("🔑 ใช้งานได้ ${_apiKeys.length} keys");
        _initModels(); // refresh ด้วย key ที่ตรวจแล้ว
      });
    }

    // Optional: probe available models via ListModels if enabled
    final debugList = (dotenv.env['GEMINI_DEBUG_LIST_MODELS'] ?? 'false')
        .trim()
        .toLowerCase();
    if (debugList == 'true' || debugList == '1' || debugList == 'on') {
      _probeAndAdjustModels();
    }
  }

  void _initModels() {
    final apiKey = _apiKeys.isEmpty ? '' : _apiKeys[_currentKeyIndex];
    if (_apiKeys.isEmpty) {
      print("👉 No Gemini API key — using fallback");
    } else {
      final previewLength = apiKey.length >= 6 ? 6 : apiKey.length;
      final preview = previewLength > 0
          ? apiKey.substring(0, previewLength)
          : '';
      final suffix = apiKey.length > previewLength ? '...' : '';
      print(
        "👉 Using API Key[${_currentKeyIndex + 1}/${_apiKeys.length}]: $preview$suffix",
      );
    }

    _primaryModel = GenerativeModel(
      model: _primaryModelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.2, // เน้นความแม่นยำ
        topK: 40,
        topP: 0.9,
        maxOutputTokens: 1024,
        responseMimeType: "application/json",
      ),
    );

    _fallbackModel = GenerativeModel(
      model: _fallbackModelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.2,
        topK: 40,
        topP: 0.9,
        maxOutputTokens: 2048,
        responseMimeType: "application/json",
      ),
    );
  }

  /// ✅ หมุน API key ถ้า quota เต็ม
  void rotateApiKey() {
    _currentKeyIndex = (_currentKeyIndex + 1) % _apiKeys.length;
    _initModels();
  }

  // Smart generator: try SDK primary/fallback, then REST v1/v1beta fallbacks with multiple models
  Future<String?> generateTextSmart(String prompt) async {
    // 1) Try SDK primary
    if (_useSdk) {
      try {
        final res = await _primaryModel.generateContent([Content.text(prompt)]);
        final t = res.text?.trim();
        if (t != null && t.isNotEmpty) return t;
      } catch (_) {}
    }

    // 2) Try SDK fallback
    try {
      final res = await _fallbackModel.generateContent([Content.text(prompt)]);
      final t = res.text?.trim();
      if (t != null && t.isNotEmpty) return t;
    } catch (_) {}

    // 3) Try REST on v1 and v1beta with best-effort model list
    if (_apiKeys.isEmpty) return null;
    final models = <String>{
      _primaryModelName,
      _fallbackModelName,
      'gemini-pro',
      'gemini-1.5-flash-8b',
      'gemini-1.5-flash',
      'gemini-1.5-pro',
      'gemini-1.5-pro-002',
    }.where((m) => m.trim().isNotEmpty).toList();

    for (final key in _apiKeys) {
      for (final base in const [
        'https://generativelanguage.googleapis.com/v1',
        'https://generativelanguage.googleapis.com/v1beta',
      ]) {
        for (final m in models) {
          try {
            final txt = await _httpGenerate(base, m, key, prompt);
            if (txt != null && txt.isNotEmpty) return txt;
          } catch (_) {}
        }
      }
    }
    return null;
  }

  Future<String?> _httpGenerate(
    String base,
    String model,
    String apiKey,
    String prompt,
  ) async {
    final uri = Uri.parse('$base/models/$model:generateContent?key=$apiKey');
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
    });
    final res = await http
        .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final map = _tryDecode(res.body);
    // v1/v1beta: candidates[0].content.parts[0].text
    final cands = (map['candidates'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .toList();
    if (cands == null || cands.isEmpty) return null;
    final content = cands.first['content'] as Map<String, dynamic>?;
    final parts = (content?['parts'] as List?)
        ?.whereType<Map<String, dynamic>>()
        .toList();
    final text = parts != null && parts.isNotEmpty
        ? parts.first['text']?.toString()
        : null;
    return (text != null && text.isNotEmpty) ? text : null;
  }

  Future<void> _probeAndAdjustModels() async {
    if (_apiKeys.isEmpty) return;
    final key = _apiKeys[_currentKeyIndex];
    try {
      final chosen = await _chooseAvailableModels(key);
      if (chosen != null) {
        _primaryModelName = chosen.$1;
        _fallbackModelName = chosen.$2 ?? _fallbackModelName;
        print(
          '🔎 Gemini models selected: primary=$_primaryModelName, fallback=$_fallbackModelName',
        );
        _initModels();
      }
    } catch (e) {
      print('⚠️ Probe models failed: $e');
    }
  }

  Future<(String, String?)?> _chooseAvailableModels(String apiKey) async {
    Future<List<Map<String, dynamic>>?> fetch(String base) async {
      final uri = Uri.parse('$base/models?key=$apiKey');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = res.body;
      final data = body.isNotEmpty ? body : '{}';
      final jsonMap = _tryDecode(data);
      final models = (jsonMap['models'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList();
      return models;
    }

    final v1 = await fetch('https://generativelanguage.googleapis.com/v1');
    final v1b =
        v1 ?? await fetch('https://generativelanguage.googleapis.com/v1beta');
    final models = v1 ?? v1b;
    if (models == null || models.isEmpty) return null;

    String strip(String name) =>
        name.startsWith('models/') ? name.substring(7) : name;
    bool supportsGen(Map m) {
      final methods =
          (m['supportedGenerationMethods'] as List?)
              ?.map((e) => e.toString())
              .toSet() ??
          {};
      return methods.contains('generateContent') || methods.contains('create');
    }

    final names = models
        .where(supportsGen)
        .map((m) => strip((m['name'] ?? '').toString()))
        .toSet();

    String? pick(List<String> prefs) =>
        prefs.firstWhere((p) => names.contains(p), orElse: () => '');

    final primaryPrefs = <String>[
      _primaryModelName,
      'gemini-pro',
      'gemini-1.5-flash',
      'gemini-1.5-flash-8b',
      'gemini-1.5-pro',
      'gemini-1.5-pro-002',
    ];
    final fallbackPrefs = <String>[
      _fallbackModelName,
      'gemini-pro',
      'gemini-1.5-pro',
      'gemini-1.5-pro-002',
      'gemini-1.5-flash',
      'gemini-1.5-flash-8b',
    ];

    final p = pick(primaryPrefs);
    final f = pick(fallbackPrefs);
    final primary = (p != null && p.isNotEmpty) ? p : null;
    final fallback = (f != null && f.isNotEmpty) ? f : null;
    if (primary == null) return null;
    return (primary, fallback);
  }

  Map<String, dynamic> _tryDecode(String s) {
    try {
      final v = jsonDecode(s);
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>?> generateWeeklyMealPlan({
    required List<ShoppingItem> pantryItems,
    Map<String, dynamic>? userProfile,
    String? dietaryNotes,
  }) async {
    final prompt = _buildWeeklyMealPlanPrompt(
      pantryItems: pantryItems,
      userProfile: userProfile,
      dietaryNotes: dietaryNotes,
    );
    final raw = await generateTextSmart(prompt);
    if (raw == null || raw.trim().isEmpty) return null;
    final normalized = _stripJsonFence(raw);
    final decoded = _tryDecode(normalized);
    if (decoded.isEmpty) return null;
    _enforceFuzzyFrequencies(decoded);
    return decoded;
  }

  String _buildWeeklyMealPlanPrompt({
    required List<ShoppingItem> pantryItems,
    Map<String, dynamic>? userProfile,
    String? dietaryNotes,
  }) {
    final pantryPayload = pantryItems.map((item) {
      final frequency = item.consumptionFrequency;
      return {
        'name': item.name,
        'category': item.category,
        'quantity': item.quantity,
        'unit': item.unit,
        'frequency': frequency == null ? 'unknown' : _frequencyToken(frequency),
        if (item.consumptionReason != null)
          'frequency_reason': item.consumptionReason,
      };
    }).toList();

    final baseProfile = userProfile ?? {};
    final profile = Map<String, dynamic>.from(baseProfile);
    final dietary = (dietaryNotes ?? '').trim();
    final guidelines = dietary.isEmpty
        ? 'No additional dietary restrictions provided.'
        : dietary;

    final allergyInputs = <String>[];
    final allergiesField = baseProfile['allergies'];
    if (allergiesField is String && allergiesField.trim().isNotEmpty) {
      allergyInputs.add(allergiesField);
    } else if (allergiesField is Iterable) {
      for (final entry in allergiesField) {
        if (entry is String && entry.trim().isNotEmpty) {
          allergyInputs.add(entry);
        }
      }
    }

    final allergyExpansion = AllergyUtils.expandAllergens(allergyInputs);
    final allergyCoverage = describeAllergyCoverage(allergyInputs);
    final allergyKeywords = allergyExpansion.all.toList()..sort();
    final allergyKeywordsJson = jsonEncode(allergyKeywords);
    final allergyKeywordsEn = allergyExpansion.englishOnly.toList()..sort();
    final allergyKeywordsEnJson = allergyKeywordsEn.isEmpty
        ? null
        : jsonEncode(allergyKeywordsEn);

    if (allergyKeywords.isNotEmpty) {
      profile['allergy_keywords'] = allergyKeywords;
    }
    if (allergyKeywordsEn.isNotEmpty) {
      profile['allergy_keywords_en'] = allergyKeywordsEn;
    }

    final allergenKeywordBlock = [
      'Allergen keywords (JSON, รวมคำพ้องทั้งหมด): $allergyKeywordsJson',
      if (allergyKeywordsEnJson != null)
        'English-only allergen keywords (JSON): $allergyKeywordsEnJson',
    ].join('\n');

    return '''
คุณเป็นผู้ช่วยวางแผนอาหารที่ต้องยึดเกณฑ์โภชนาการของ DRI (ไขมัน, ไขมันอิ่มตัว, น้ำตาล, โซเดียม ต่อ 100 กรัม) และกติกา fuzzy frequency ดังนี้:
- ถ้ามีสารอาหารระดับสูงอย่างน้อยหนึ่งรายการ → จัดเป็น occasional
- ถ้ามีระดับกลาง 3 รายการขึ้นไป → จัดเป็น weekly
- ถ้ามีระดับกลาง 2 รายการ → จัดเป็น once_per_day
- ถ้าน้อยกว่านั้น → จัดเป็น daily

สร้างแผนอาหาร 7 วัน โดยให้แต่ละวันมี 3 มื้อ (เช้า กลางวัน เย็น) และทำตามกติกาเหล่านี้:
- ใช้วัตถุดิบจาก pantry snapshot ก่อนเมื่อเป็นไปได้ แล้วค่อยเติมวัตถุดิบเสริมตามความจำเป็น
- เคารพข้อมูลภูมิแพ้ใน user profile อย่างเข้มงวด: ห้ามใช้วัตถุดิบที่ตรงกับรายการภูมิแพ้ รวมถึงผลิตภัณฑ์/ส่วนประกอบที่มีต้นกำเนิดจากสารก่อภูมินั้น (เช่น แพ้นมวัว → งดนม เนย ชีส โยเกิร์ต เวย์ เคซีน; แพ้ถั่วลิสง → งดถั่วลิสง เนยถั่ว น้ำจิ้ม/ซอสที่มีถั่วลิสง) และให้ใช้หลักการเดียวกันกับภูมิแพ้ทุกชนิด
 - ให้ตรวจสอบซอส เครื่องปรุงรส อาหารหมัก/บ่ม เส้น และของแปรรูปที่อาจซ่อนสารก่อภูมิแพ้ เช่น ซีอิ๊ว/ซีอิ๊วดำ/ซอสถั่วเหลือง (soy sauce, shoyu, ponzu), ซอสเทอริยากิ, ซอสฮอยซิน, วูสเตอร์เชอร์, น้ำซุปก้อน, ซอสพริก/น้ำพริก/น้ำมันพริก (sriracha, hot sauce, gochujang, sambal), เส้นพาสต้า/ราเมน/อุด้ง/โซบะ, บะหมี่กึ่งสำเร็จรูป (มาม่า/ไวไว/ยำยำ/แบรนด์อื่น), ขนมปัง/พิซซ่า/เบเกอรี่หมัก, โยเกิร์ต, ชีส, ไวน์, เบียร์, คอมบูชะ — หากมีสารก่อภูมิแพ้ให้ตัดออกทุกกรณี
- ใช้ `allergy_keywords` และ `allergy_keywords_en` ที่ส่งมาเป็นชุดคำอ้างอิงหลัก เพื่อตรวจสอบคำพ้อง ศัพท์แสลง และชื่อการค้าของสารก่อภูมิแพ้ทุกชนิด อย่าใช้คำที่ไม่ได้อยู่ในรายการนี้
- ตรวจให้แน่ใจว่าสารอาหารรวมของทั้งวัน (เช้า+กลางวัน+เย็น) ไม่เกิน: ไขมันรวม < 70 กรัม, ไขมันอิ่มตัวรวม < 20 กรัม, น้ำตาลรวม < 90 กรัม, โซเดียมรวม < 6 กรัม หากวันใดเกินให้สลับหรือปรับเมนูจนผ่านเกณฑ์
- วางเมนูให้หลากหลาย สลับโปรตีน ผัก และรูปแบบการปรุง เพื่อไม่ให้สองวันติดกันคล้ายกันเกินไป
- ระบุเหตุผลด้านสุขภาพหรือโภชนาการของแต่ละมื้อไว้ในฟิลด์ `reason`

ข้อมูลภูมิแพ้ (ตีความครอบคลุมคำพ้อง/ผลิตภัณฑ์เกี่ยวเนื่อง):
$allergyCoverage

$allergenKeywordBlock

สำหรับแต่ละมื้อให้ระบุข้อมูลต่อไปนี้:
- `name`
- `description` (ใส่ได้ตามความเหมาะสม)
- `ingredients` (วัตถุดิบหลักที่ใช้จริง)
- `nutrition_per_serving` ที่มี `kcal`, `fat_g`, `saturated_fat_g`, `sugar_g`, `salt_g`
- `ai_frequency_guess` (การจัดหมวดเบื้องต้นของคุณ)
- `reason` (เหตุผลว่าทำไมเมนูนี้เหมาะสม)

หลังจากลิสต์มื้ออาหารครบแล้ว ให้นำค่าโภชนาการมาคำนวณ `consumption_frequency` ใหม่ตามกติกา fuzzy ข้างต้น หากต่างจากที่คาดไว้ ให้แก้ไขและอธิบายใน `frequency_reason`
เพิ่มข้อความ `summary.notes` อย่างน้อยหนึ่งรายการ ที่ระบุว่าทำไมแต่ละวันจึงผ่านเพดานโภชนาการ หรือมีการแลกเปลี่ยนตรงไหน

Pantry snapshot (JSON):
${jsonEncode(pantryPayload)}

User profile (JSON):
${jsonEncode(profile)}

Dietary notes: $guidelines

Use this sample structure as reference (values already validated):
$_seedWeeklyPlanExample

Output JSON only, matching this schema:
{
  "week_plan": [
    {
      "day": 1,
      "meals": {
        "breakfast": {
          "name": "...",
          "description": "...",
          "ingredients": ["...", "..."],
          "nutrition_per_serving": {
            "kcal": 0,
            "fat_g": 0,
            "saturated_fat_g": 0,
            "sugar_g": 0,
            "salt_g": 0
          },
          "ai_frequency_guess": "daily|once_per_day|weekly|occasional",
          "reason": "...",
          "consumption_frequency": "daily|once_per_day|weekly|occasional",
          "frequency_reason": "..."
        },
        "lunch": { ... },
        "dinner": { ... }
      }
    }
  ],
  "summary": {
    "total_kcal_per_day": "...",
    "notes": ["..."]
  }
}

Do not include markdown fences or commentary.
''';
  }

  void _enforceFuzzyFrequencies(Map<String, dynamic> plan) {
    final week = plan['week_plan'];
    if (week is! List) return;
    for (final day in week) {
      if (day is! Map<String, dynamic>) continue;
      final meals = day['meals'];
      if (meals is! Map) continue;
      meals.forEach((key, value) {
        if (value is! Map<String, dynamic>) return;
        final nutrition = value['nutrition_per_serving'];
        if (nutrition is! Map) return;
        final fat = _asDouble(nutrition['fat_g']);
        final saturates = _asDouble(nutrition['saturated_fat_g']);
        final sugar = _asDouble(nutrition['sugar_g']);
        final salt = _asDouble(nutrition['salt_g']);
        final frequency = NutritionThresholds.frequencyFromValues(
          fat: fat,
          saturates: saturates,
          sugar: sugar,
          salt: salt,
        );
        final reason = NutritionThresholds.reasonFromValues(
          fat: fat,
          saturates: saturates,
          sugar: sugar,
          salt: salt,
        );
        if (frequency != null) {
          value['consumption_frequency'] = _frequencyToken(frequency);
        }
        if (reason != null) {
          value['frequency_reason'] = reason;
        }
      });
    }
  }

  String _frequencyToken(ConsumptionFrequency frequency) {
    switch (frequency) {
      case ConsumptionFrequency.daily:
        return 'daily';
      case ConsumptionFrequency.oncePerDay:
        return 'once_per_day';
      case ConsumptionFrequency.weekly:
        return 'weekly';
      case ConsumptionFrequency.occasional:
        return 'occasional';
    }
  }

  String _stripJsonFence(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('```')) {
      final fenceIndex = trimmed.indexOf('\n');
      if (fenceIndex != -1) {
        final endFence = trimmed.lastIndexOf('```');
        if (endFence > fenceIndex) {
          return trimmed.substring(fenceIndex + 1, endFence).trim();
        }
      }
    }
    return trimmed;
  }

  static double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static const String _seedWeeklyPlanExample = '''
{
  "week_plan": [
    {
      "day": 1,
      "meals": {
        "breakfast": {
          "name": "Whole-wheat toast with cottage cheese and berries",
          "ingredients": ["whole-wheat bread", "cottage cheese", "mixed berries"],
          "nutrition_per_serving": {
            "kcal": 360,
            "fat_g": 2.5,
            "saturated_fat_g": 0.9,
            "sugar_g": 3.8,
            "salt_g": 0.2
          },
          "ai_frequency_guess": "daily",
          "reason": "All nutrients low, supports steady morning energy.",
          "consumption_frequency": "daily",
          "frequency_reason": "All tracked nutrients are low - safe for daily consumption."
        },
        "lunch": {
          "name": "Grilled chicken with brown rice and vegetables",
          "ingredients": ["chicken breast", "brown rice", "broccoli", "carrot"],
          "nutrition_per_serving": {
            "kcal": 520,
            "fat_g": 4.5,
            "saturated_fat_g": 1.2,
            "sugar_g": 4.1,
            "salt_g": 0.35
          },
          "ai_frequency_guess": "daily",
          "reason": "Lean protein and whole grains with mostly low nutrients.",
          "consumption_frequency": "daily",
          "frequency_reason": "Slightly elevated saturated fat - suitable for daily use."
        },
        "dinner": {
          "name": "Salmon stir-fry with quinoa and greens",
          "ingredients": ["salmon", "quinoa", "bok choy", "bell pepper"],
          "nutrition_per_serving": {
            "kcal": 590,
            "fat_g": 8.5,
            "saturated_fat_g": 2.6,
            "sugar_g": 5.4,
            "salt_g": 0.45
          },
          "ai_frequency_guess": "once_per_day",
          "reason": "Healthy fats but moderate saturated fat and sugar.",
          "consumption_frequency": "once_per_day",
          "frequency_reason": "Moderate saturated fat and sugar - keep to once per day."
        }
      }
    },
    {
      "day": 2,
      "meals": {
        "breakfast": {
          "name": "Overnight oats with banana and chia",
          "ingredients": ["rolled oats", "banana", "chia seeds", "soy milk"],
          "nutrition_per_serving": {
            "kcal": 380,
            "fat_g": 3.1,
            "saturated_fat_g": 0.8,
            "sugar_g": 7.8,
            "salt_g": 0.28
          },
          "ai_frequency_guess": "daily",
          "reason": "High fiber and mostly low-risk nutrients.",
          "consumption_frequency": "daily",
          "frequency_reason": "All tracked nutrients are low - safe for daily consumption."
        },
        "lunch": {
          "name": "Herb roasted turkey with sweet potato mash",
          "ingredients": ["turkey breast", "sweet potato", "olive oil", "green beans"],
          "nutrition_per_serving": {
            "kcal": 540,
            "fat_g": 5.5,
            "saturated_fat_g": 1.6,
            "sugar_g": 4.5,
            "salt_g": 0.5
          },
          "ai_frequency_guess": "once_per_day",
          "reason": "Moderate fat and salt levels, balance with rest of day.",
          "consumption_frequency": "once_per_day",
          "frequency_reason": "Moderate saturated fat and salt - keep to once per day."
        },
        "dinner": {
          "name": "Creamy coconut curry with brown rice",
          "ingredients": ["coconut milk", "chicken", "brown rice", "peas"],
          "nutrition_per_serving": {
            "kcal": 640,
            "fat_g": 18.5,
            "saturated_fat_g": 6.1,
            "sugar_g": 8.2,
            "salt_g": 1.7
          },
          "ai_frequency_guess": "occasional",
          "reason": "High fat, saturated fat, and salt.",
          "consumption_frequency": "occasional",
          "frequency_reason": "High saturated fat and salt - enjoy occasionally."
        }
      }
    }
  ]
}
''';
}
