import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AITranslationService {
  static final String? _apiKey = dotenv.env['GEMINI_API_KEYS']
      ?.split(',')
      .first;
  static const String _cacheKeyPrefix = 'translation_cache_';

  /// ✅ Translate English → Thai (with cache)
  static Future<String> translateToThai(String text) async {
    if (text.trim().isEmpty) return text;

    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_cacheKeyPrefix${text.hashCode}';

    // 🔎 1) ลองเช็ค cache ก่อน
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      return cached;
    }

    // 🚫 2) ถ้าไม่มี API key → return ต้นฉบับ
    if (_apiKey == null || _apiKey!.isEmpty) {
      return text;
    }

    try {
      // ⚡ 3) เรียก Gemini API
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _apiKey!,
      );
      final response = await model.generateContent([
        Content.text(
          "Translate this food recipe text to Thai (short, natural, and food-friendly tone): $text",
        ),
      ]);

      final translated = response.text?.trim() ?? text;

      // 💾 4) Save ลง cache
      await prefs.setString(cacheKey, translated);

      return translated;
    } catch (e) {
      print("❌ AI Translation Error: $e");
      return text;
    }
  }
}
