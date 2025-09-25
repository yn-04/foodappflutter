import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiUsageService {
  static const _dateKey = 'api_usage_date';
  static const _rapidKey = 'api_usage_rapidapi_calls';
  static const _geminiKey = 'api_usage_gemini_calls';
  static const _translateKey = 'api_usage_translate_calls';
  static const _geminiLastKey = 'api_usage_gemini_last_ms';
  static const _rapidLastKey = 'api_usage_rapid_last_ms';
  static const _geminiCooldownKey = 'api_usage_gemini_cooldown_until_ms';
  static const _rapidCooldownKey = 'api_usage_rapid_cooldown_until_ms';

  static Future<void> initDaily() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayString();
    final stored = prefs.getString(_dateKey);
    if (stored != today) {
      await prefs.setString(_dateKey, today);
      await prefs.setInt(_rapidKey, 0);
      await prefs.setInt(_geminiKey, 0);
      await prefs.setInt(_translateKey, 0);
      debugPrint('🗓️ Reset API usage counters for $today');
    }
  }

  // --- Limits from .env (with safe defaults) ---
  static int _envInt(String key, int fallback) {
    final v = dotenv.env[key];
    if (v == null) return fallback;
    return int.tryParse(v.trim()) ?? fallback;
    }

  static int get rapidDailyLimit => _envInt('RAPIDAPI_DAILY_LIMIT', 200);
  static int get geminiDailyLimit => _envInt('GEMINI_DAILY_LIMIT', 300);
  static int get translateDailyLimit => _envInt('TRANSLATE_DAILY_LIMIT', 500);
  static int get geminiMinIntervalMs => _envInt('GEMINI_MIN_INTERVAL_MS', 4000); // ~15/min
  static int get rapidMinIntervalMs => _envInt('RAPID_MIN_INTERVAL_MS', 1500);

  // --- Counters ---
  static Future<int> _increment(String key, {int by = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(key) ?? 0;
    final next = current + by;
    await prefs.setInt(key, next);
    return next;
  }

  static Future<int> _get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? 0;
  }

  // --- Min interval & cooldown helpers ---
  static Future<bool> _respectMinInterval(String lastKey, int minMs) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt(lastKey) ?? 0;
    if (now - last < minMs) {
      debugPrint('⏳ Throttled: need ${minMs - (now - last)}ms more');
      return false;
    }
    await prefs.setInt(lastKey, now);
    return true;
  }

  static Future<bool> _notCoolingDown(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final until = prefs.getInt(key) ?? 0;
    if (now < until) {
      final remain = ((until - now) / 1000).toStringAsFixed(1);
      debugPrint('🧊 Cooling down ${key.contains("gemini") ? 'Gemini' : 'RapidAPI'} for ${remain}s');
      return false;
    }
    return true;
  }

  static Future<void> setGeminiCooldown(Duration d) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(d).millisecondsSinceEpoch;
    await prefs.setInt(_geminiCooldownKey, until);
    debugPrint('🧊 Set Gemini cooldown ${d.inSeconds}s');
  }

  static Future<void> setRapidCooldown(Duration d) async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(d).millisecondsSinceEpoch;
    await prefs.setInt(_rapidCooldownKey, until);
    debugPrint('🧊 Set RapidAPI cooldown ${d.inSeconds}s');
  }

  static Future<bool> allowGeminiCall() async {
    await initDaily();
    if (!await _notCoolingDown(_geminiCooldownKey)) return false;
    return _respectMinInterval(_geminiLastKey, geminiMinIntervalMs);
  }

  static Future<bool> allowRapidCall() async {
    await initDaily();
    if (!await _notCoolingDown(_rapidCooldownKey)) return false;
    return _respectMinInterval(_rapidLastKey, rapidMinIntervalMs);
  }

  static Future<bool> canUseRapid() async {
    await initDaily();
    final used = await _get(_rapidKey);
    return used < rapidDailyLimit;
  }

  static Future<bool> canUseGemini() async {
    await initDaily();
    final used = await _get(_geminiKey);
    return used < geminiDailyLimit;
  }

  static Future<bool> canUseTranslate() async {
    await initDaily();
    final used = await _get(_translateKey);
    return used < translateDailyLimit;
  }

  static Future<void> countRapid({int by = 1}) async {
    final next = await _increment(_rapidKey, by: by);
    _log('RapidAPI', next, rapidDailyLimit);
  }

  static Future<void> countGemini({int by = 1}) async {
    final next = await _increment(_geminiKey, by: by);
    _log('Gemini', next, geminiDailyLimit);
  }

  static Future<void> countTranslate({int by = 1}) async {
    final next = await _increment(_translateKey, by: by);
    _log('Translator', next, translateDailyLimit);
  }

  static Future<String> summary() async {
    final usedRapid = await _get(_rapidKey);
    final usedGemini = await _get(_geminiKey);
    final usedTrans = await _get(_translateKey);
    return 'Usage today → RapidAPI: $usedRapid/$rapidDailyLimit, Gemini: $usedGemini/$geminiDailyLimit, Translate: $usedTrans/$translateDailyLimit';
  }

  static void _log(String label, int used, int limit) {
    final pct = (used / (limit == 0 ? 1 : limit) * 100).toStringAsFixed(0);
    final warn = used >= (limit * 0.9) ? ' ⚠️ near quota' : '';
    debugPrint('📊 $label usage $used/$limit ($pct%)$warn');
  }

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
