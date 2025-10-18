//lib/foodreccom/services/api_key_checker.dart
import 'dart:async';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
      final modelName = (dotenv.env['GEMINI_PRIMARY_MODEL'] ?? 'gemini-1.5-flash-8b').trim();
      final model = GenerativeModel(model: modelName.isEmpty ? 'gemini-1.5-flash-8b' : modelName, apiKey: key);

      try {
        // ยิงคำสั้น ๆ ทดสอบ
        final response = await model
            .generateContent([Content.text("ping")])
            .timeout(const Duration(seconds: 60));

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

  String? getFirstValidKey() {
    return _validKeys.isNotEmpty ? _validKeys.first : null;
  }
}
