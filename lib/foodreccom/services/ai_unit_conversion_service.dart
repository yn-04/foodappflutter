// lib/foodreccom/services/ai_unit_conversion_service.dart
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// ✅ [แก้ไข] import class ที่ถูกต้องจากไฟล์ของคุณ
import '../utils/smart_unit_converter.dart'
    show AiIngredientContext, CanonicalQuantity, SmartUnitConverter;

class AiUnitConversionService {
  late final GenerativeModel _model;
  bool _isInitialized = false;

  AiUnitConversionService() {
    // ⭐️ ดึง API Key จาก .env ที่โหลดไว้ใน main.dart
    final apiKeys = dotenv.env['GEMINI_API_KEYS'];

    if (apiKeys == null || apiKeys.isEmpty) {
      print('❌ AI Unit Converter: ไม่พบ GEMINI_API_KEYS ใน .env');
      return;
    }

    final apiKey = apiKeys.split(',').first;

    _model = GenerativeModel(
      model: 'gemini-pro',
      apiKey: apiKey,
      // ⭐️ เพิ่มการตั้งค่าความปลอดภัย
      safetySettings: [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.none),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.none),
      ],
    );
    _isInitialized = true;
  }

  /// 🧠 พยายามแปลงหน่วยโดยใช้ AI เป็นแผนสำรอง
  Future<CanonicalQuantity?> convertWithAi({
    // ✅ [แก้ไข] ใช้ CanonicalQuantity
    required String ingredientName,
    required double recipeAmount,
    required String recipeUnit,
  }) async {
    if (!_isInitialized) {
      print('❌ AI Unit Converter: ไม่ได้เริ่มต้นการทำงาน (ไม่มี API Key)');
      return null;
    }

    final context =
        SmartUnitConverter.buildAiIngredientContext(ingredientName);
    final targetHint = _preferredCanonicalUnit(context, ingredientName);
    final examples = SmartUnitConverter.aiSampleConversions()
        .map((e) => '- $e')
        .join('\n');
    final contextJson = jsonEncode(context.toPromptMap());
    final prompt = '''
You are a precise unit conversion API for a Thai cooking assistant.
Convert the requested ingredient into the most logical canonical unit ("gram", "milliliter", "piece", or "ฟอง").

Ingredient metadata (JSON): $contextJson
Preferred canonical unit hint: "$targetHint"

Recipe request:
- Ingredient: "$ingredientName"
- Amount: $recipeAmount
- Unit: "$recipeUnit"

Helpful Thai cooking examples:
$examples

Guidelines:
1. Honour Thai measuring habits (e.g., 1 ถ้วย = 240 ml, 1 ขีด = 100 g, 1 กระป๋องนมข้น = 385 g).
2. Use density hints when converting between milliliter and gram.
3. If grams-per-piece is provided, convert to the nearest sensible piece amount. Use unit "ฟอง" for eggs.
4. Round to a reasonable precision (max 2 decimals for gram/ml, 1 decimal for piece counts).
5. Respond ONLY with a valid JSON object: {"amount": <number>, "unit": "<canonical_unit>"}.
''';

    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      final text = response.text;

      if (text == null) {
        print('❌ AI Unit Converter: ได้รับการตอบกลับว่างเปล่า');
        return null;
      }

      final cleanText = text
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final jsonResponse = jsonDecode(cleanText) as Map<String, dynamic>;

      final amount = (jsonResponse['amount'] as num?)?.toDouble();
      final unit = jsonResponse['unit'] as String?;

      if (amount != null && unit != null) {
        print(
          '✅ AI Unit Converter: แปลงค่าสำเร็จ ($ingredientName -> $amount $unit)',
        );
        return CanonicalQuantity(
          amount,
          unit,
        ); // ✅ [แก้ไข] ใช้ CanonicalQuantity
      }

      return null;
    } catch (e) {
      print('❌ AI Unit Converter Error: $e');
      return null;
    }
  }

  String _preferredCanonicalUnit(
    AiIngredientContext context,
    String ingredientName,
  ) {
    final lower = ingredientName.trim().toLowerCase();
    if (lower.contains('ไข่') || lower.contains('egg')) {
      return 'ฟอง';
    }
    if (context.gramsPerPiece != null) {
      return 'piece';
    }
    if (context.category == 'liquid' || context.category == 'sauce') {
      return 'milliliter';
    }
    if (context.category == 'fresh-herb') {
      return 'gram';
    }
    return 'gram';
  }
}
