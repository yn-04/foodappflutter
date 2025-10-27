// lib/foodreccom/services/enhanced_ai_recommendation_service.dart
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/foodreccom/utils/allergy_utils.dart';

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
    if (_useSdk) {
      try {
        final res = await _fallbackModel.generateContent([Content.text(prompt)]);
        final t = res.text?.trim();
        if (t != null && t.isNotEmpty) return t;
      } catch (_) {}
    }

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

}
