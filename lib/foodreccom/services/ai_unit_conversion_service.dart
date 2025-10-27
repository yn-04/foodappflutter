// lib/foodreccom/services/ai_unit_conversion_service.dart
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

// ✅ [แก้ไข] import class ที่ถูกต้องจากไฟล์ของคุณ
import '../utils/smart_unit_converter.dart' show CanonicalQuantity;

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

    final prompt =
        '''
      You are a precise unit conversion API for a cooking app.
      Convert the following recipe ingredient into its most logical canonical unit (either 'gram', 'milliliter', 'piece', or 'ฟอง').

      - Ingredient: "$ingredientName"
      - Amount: $recipeAmount
      - Unit: "$recipeUnit"

      Rules:
      1. Analyze the ingredient. If it's a liquid/sauce ('$ingredientName'), target unit should be 'milliliter'.
      2. If it's a dry good/solid/powder ('$ingredientName'), target unit should be 'gram'.
      3. If it's something counted ('$ingredientName', e.g., 'egg', 'shrimp'), target unit should be 'piece' or 'ฟอง' (for 'egg').
      4. Perform the conversion. (e.g., 1 tablespoon = 15 ml, 1 cup of flour = 120 g, 1 serving of pork = 100 g, 1 pinch of salt = 0.3 g).
      5. Respond ONLY with a valid JSON object in this format:
      {"amount": 123.4, "unit": "gram"}
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
}
