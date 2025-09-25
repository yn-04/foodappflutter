// lib/foodreccom/services/enhanced_ai_recommendation_service.dart
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'api_key_checker.dart';

class EnhancedAIRecommendationService {
  late List<String> _apiKeys;
  int _currentKeyIndex = 0;

  late GenerativeModel _primaryModel;
  late GenerativeModel _fallbackModel;

  /// ✅ expose ให้ HybridRecipeService ใช้
  GenerativeModel get primaryModel => _primaryModel;
  GenerativeModel get fallbackModel => _fallbackModel;

  EnhancedAIRecommendationService() {
    final apiKeysStr = dotenv.env['GEMINI_API_KEYS'];
    if (apiKeysStr == null || apiKeysStr.isEmpty) {
      throw Exception('❌ GEMINI_API_KEYS is missing in .env');
    }

    _apiKeys = apiKeysStr.split(',').map((k) => k.trim()).toList();

    // ✅ init model ทันที
    _initModels();

    // ✅ ตรวจสอบว่า key ไหนใช้ได้จริง
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
        temperature: 0.2, // เน้นความแม่นยำ
        topK: 40,
        topP: 0.9,
        maxOutputTokens: 1024,
        responseMimeType: "application/json",
      ),
    );

    _fallbackModel = GenerativeModel(
      model: 'gemini-2.5-pro',
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
}
