import 'package:translator/translator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_usage_service.dart';

class AITranslationService {
  static final GoogleTranslator _translator = GoogleTranslator();
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

    try {
      await ApiUsageService.initDaily();
      // ใช้โควตาแยกสำหรับ translator (ไม่ใช้ Gemini แปลอีกต่อไป)
      if (!await ApiUsageService.canUseTranslate()) {
        print('⛔ Translate quota reached → return original text');
        return text;
      }
      await ApiUsageService.countTranslate();
      final response = await _translator.translate(text, from: 'en', to: 'th');
      final translated = response.text.trim();

      // 💾 4) Save ลง cache
      await prefs.setString(cacheKey, translated);

      return translated;
    } catch (e) {
      print("❌ Translation Error (translator): $e");
      return text;
    }
  }
}
