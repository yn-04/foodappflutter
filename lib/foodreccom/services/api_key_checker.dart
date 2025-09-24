//lib/foodreccom/services/api_key_checker.dart
import 'dart:async';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiKeyChecker {
  final List<String> _apiKeys;
  final List<String> _validKeys = [];

  ApiKeyChecker(this._apiKeys);

  Future<List<String>> checkKeys() async {
    _validKeys.clear();

    for (var key in _apiKeys) {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: key);

      try {
        // ยิงคำสั้น ๆ ทดสอบ
        final response = await model
            .generateContent([Content.text("ping")])
            .timeout(const Duration(seconds: 60));

        if (response.text != null && response.text!.isNotEmpty) {
          print("✅ Key ใช้ได้: ${key.substring(0, 6)}...");
          _validKeys.add(key);
        }
      } catch (e) {
        print("❌ Key ใช้ไม่ได้/Quota หมด: ${key.substring(0, 6)}... → $e");
      }
    }

    return _validKeys;
  }

  String? getFirstValidKey() {
    return _validKeys.isNotEmpty ? _validKeys.first : null;
  }
}
