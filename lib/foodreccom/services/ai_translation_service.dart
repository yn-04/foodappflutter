//lib/foodreccom/services/ai_translation_service.dart
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:translator/translator.dart';
import 'api_usage_service.dart';

class AITranslationService {
  static const String _cacheKeyPrefix = 'translation_cache_';
  static const String _modelEnvKey = 'GEMINI_TRANSLATE_MODEL';
  static const String _defaultModel = 'gemini-1.5-flash';

  static List<String> _apiKeys = [];
  static int _currentKeyIndex = 0;
  static GenerativeModel? _model;
  static String _modelName = _defaultModel;
  static Future<void>? _initFuture;
  static DateTime? _throttleUntil;
  static DateTime? _geminiSuspendedUntil;
  static bool _sdkDisabled = false;
  static final GoogleTranslator _legacyTranslator = GoogleTranslator();
  static bool _translatorDisabled = false;
  static DateTime? _translatorRetryAt;

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

    String? translated;
    var fallbackTried = false;

    try {
      if (!await ApiUsageService.canUseTranslate()) {
        print('⛔ Translate quota reached → return original text');
        return text;
      }

      await _ensureInitialized();

      final hasGeminiKey = _apiKeys.isNotEmpty;
      final suspended = _geminiSuspendedUntil != null &&
          DateTime.now().isBefore(_geminiSuspendedUntil!);
      final canUseGemini =
          hasGeminiKey && !suspended && await ApiUsageService.canUseGemini();

      if (hasGeminiKey && canUseGemini) {
        final now = DateTime.now();
        final isThrottled =
            _throttleUntil != null && now.isBefore(_throttleUntil!);
        if (!isThrottled) {
          final allowedNow = await ApiUsageService.allowGeminiCall();
          if (allowedNow) {
            _throttleUntil = null;
            final prompt = _buildPrompt(text);
            translated = await _requestTranslation(prompt);
          } else {
            final wait = Duration(
              milliseconds: ApiUsageService.geminiMinIntervalMs,
            );
            final planned = now.add(wait);
            if (_throttleUntil == null || planned.isAfter(_throttleUntil!)) {
              _throttleUntil = planned;
            }
            print('⏳ Gemini throttle active → ใช้ translator fallback');
          }
        } else {
          print('⏳ Gemini throttle active → ใช้ translator fallback');
        }
      } else {
        if (!hasGeminiKey) {
          print('ℹ️ ไม่มี Gemini API key → ใช้ translator fallback');
        } else if (suspended) {
          final diff = _geminiSuspendedUntil!.difference(DateTime.now());
          var remaining = diff.inSeconds;
          if (remaining < 0) remaining = 0;
          if (remaining > 3600) remaining = 3600;
          print(
            '🧊 Gemini translation cool-down เหลืออีก ${remaining}s → ใช้ translator fallback',
          );
        } else {
          print('ℹ️ เกินโควตาหรือปิดการใช้งาน Gemini → ใช้ translator fallback');
        }
      }

      if (translated == null || translated.trim().isEmpty) {
        fallbackTried = true;
        translated = await _translateWithFallback(text);
      }
    } catch (e) {
      print("❌ Translation Error (gemini): $e");
      if (!fallbackTried) {
        translated ??= await _translateWithFallback(text);
        fallbackTried = true;
      }
    }

    final output = translated?.trim();
    if (output == null || output.isEmpty) {
      return text;
    }

    await prefs.setString(cacheKey, output);
    return output;
  }

  static Future<void> _ensureInitialized() async {
    final hasKeys = _apiKeys.isNotEmpty;
    if (hasKeys && (_model != null || _sdkDisabled)) {
      return;
    }
    _initFuture ??= _initModel();
    await _initFuture;
  }

  static Future<void> _initModel() async {
    final rawKeys = (dotenv.env['GEMINI_API_KEYS'] ?? '').split(',');
    _apiKeys = rawKeys.map((k) => k.trim()).where((k) => k.isNotEmpty).toList();

    final translateModel = (dotenv.env[_modelEnvKey] ?? '').trim();
    if (translateModel.isNotEmpty) {
      _modelName = translateModel;
    } else {
      final fallbackModel = (dotenv.env['GEMINI_PRIMARY_MODEL'] ?? '').trim();
      if (fallbackModel.isNotEmpty) {
        _modelName = fallbackModel;
      }
    }

    if (_apiKeys.isEmpty) {
      print('⚠️ GEMINI_API_KEYS missing — translation will be skipped.');
      _model = null;
      return;
    }

    if (_sdkDisabled) {
      _model = null;
      return;
    }

    _model = _buildModel(_apiKeys[_currentKeyIndex]);
  }

  static GenerativeModel _buildModel(String apiKey) {
    return GenerativeModel(
      model: _modelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.2,
        topP: 0.9,
        topK: 32,
        maxOutputTokens: 256,
        responseMimeType: 'text/plain',
      ),
    );
  }

  static void _rotateKey() {
    if (_apiKeys.isEmpty) return;
    _currentKeyIndex = (_currentKeyIndex + 1) % _apiKeys.length;
    if (_sdkDisabled) {
      _model = null;
      return;
    }
    _model = _buildModel(_apiKeys[_currentKeyIndex]);
  }

  static void _invalidateCurrentKey() {
    if (_apiKeys.isEmpty) return;
    final removed = _apiKeys.removeAt(_currentKeyIndex);
    final masked = removed.length <= 4
        ? removed
        : '${removed.substring(0, 4)}***${removed.substring(removed.length - 2)}';
    print('⚠️ ปิดการใช้งาน Gemini key ที่ไม่ถูกต้อง: $masked');
    if (_apiKeys.isEmpty) {
      _model = null;
      print(
        '⛔ ไม่มี Gemini API key ที่ใช้งานได้เหลือ ตรวจสอบค่า GEMINI_API_KEYS ใน .env',
      );
      return;
    }
    if (_currentKeyIndex >= _apiKeys.length) {
      _currentKeyIndex = 0;
    }
    if (_sdkDisabled) {
      _model = null;
    } else {
      _model = _buildModel(_apiKeys[_currentKeyIndex]);
    }
  }

  static Future<String?> _requestTranslation(String prompt) async {
    if (_apiKeys.isEmpty) return null;

    for (var attempt = 0;
        _apiKeys.isNotEmpty && attempt < _apiKeys.length;
        attempt++) {
      final totalKeys = _apiKeys.length;
      final apiKey = _apiKeys[_currentKeyIndex];
      String? candidate;
      bool rotateAfter = false;
      bool quotaHit = false;
      Duration? cooldown;
      var tryHttp = _model == null;
      final canRotateKeys = totalKeys > 1;

      if (_model != null) {
        try {
          final res = await _model!.generateContent([Content.text(prompt)]);
          candidate = _sanitize(res.text);
        } on GenerativeAIException catch (e) {
          final String? rawMessage = e.message;
          final message = (rawMessage == null || rawMessage.isEmpty)
              ? e.toString()
              : rawMessage;
          print('❌ Translation Error (gemini): $message');

          if (_looksLikeInvalidKey(message)) {
            print('⛔ พบ Gemini API key ไม่ถูกต้อง (SDK) → ลบ key ปัจจุบัน');
            _invalidateCurrentKey();
            if (_apiKeys.isEmpty) return null;
            attempt--;
            continue;
          }

          if (_looksLikeQuota(message)) {
            quotaHit = true;
            cooldown = _parseRetryAfter(message) ?? const Duration(seconds: 60);
            rotateAfter = canRotateKeys;
          } else {
            tryHttp = true;
            rotateAfter = canRotateKeys;
            if (_isSdkFormatBug(message)) {
              if (!_sdkDisabled) {
                print(
                  '⚠️ Gemini SDK format issue detected → using REST fallback only.',
                );
              }
              _sdkDisabled = true;
              _model = null;
              _initFuture = null;
              rotateAfter = false; // keep same key for REST fallback
            }
          }
        } catch (e) {
          final message = e.toString();
          print('❌ Translation Error (gemini sdk): $message');
          if (_looksLikeInvalidKey(message)) {
            print('⛔ พบ Gemini API key ไม่ถูกต้อง (SDK) → ลบ key ปัจจุบัน');
            _invalidateCurrentKey();
            if (_apiKeys.isEmpty) return null;
            attempt--;
            continue;
          }
          tryHttp = true;
          rotateAfter = canRotateKeys;
          if (_isSdkFormatBug(message)) {
            if (!_sdkDisabled) {
              print(
                '⚠️ Gemini SDK format issue detected → using REST fallback only.',
              );
            }
            _sdkDisabled = true;
            _model = null;
            _initFuture = null;
            rotateAfter = false;
          }
        }
      }

      if (!quotaHit &&
          (candidate == null || candidate.isEmpty) &&
          _model != null) {
        tryHttp = true;
      }

      if (candidate != null && candidate.isNotEmpty) {
        await ApiUsageService.countTranslate();
        await ApiUsageService.countGemini();
        _geminiSuspendedUntil = null;
        return candidate;
      }

      if (tryHttp && apiKey.isNotEmpty) {
        final restResult = await _httpTranslate(prompt, apiKey);
        if (restResult.cooldown != null) {
          cooldown = restResult.cooldown;
        }
        if (restResult.quotaHit) {
          quotaHit = true;
        }
        if (restResult.invalidKey) {
          print('⛔ พบ Gemini API key ไม่ถูกต้อง (REST) → ลบ key ปัจจุบัน');
          _invalidateCurrentKey();
          if (_apiKeys.isEmpty) return restResult.text;
          attempt--;
          continue;
        }
        if (restResult.rotateKey) {
          rotateAfter = canRotateKeys;
        }
        if (restResult.text != null && restResult.text!.isNotEmpty) {
          await ApiUsageService.countTranslate();
          await ApiUsageService.countGemini();
          _geminiSuspendedUntil = null;
          return restResult.text;
        }
      }

      if (cooldown != null) {
        await ApiUsageService.setGeminiCooldown(cooldown);
        final planned = DateTime.now().add(cooldown);
        if (_throttleUntil == null || planned.isAfter(_throttleUntil!)) {
          _throttleUntil = planned;
        }
        if (_geminiSuspendedUntil == null ||
            planned.isAfter(_geminiSuspendedUntil!)) {
          _geminiSuspendedUntil = planned;
          print('🧊 Set Gemini cooldown ${cooldown.inSeconds}s');
        }
      }

      if (rotateAfter) {
        if (canRotateKeys) {
          _rotateKey();
        }
        continue;
      }

      if (quotaHit) {
        return null;
      }
    }

    return null;
  }

  static Future<String?> _translateWithFallback(String text) async {
    if (_translatorDisabled) {
      final wait = _translatorRetryAt;
      if (wait != null && DateTime.now().isBefore(wait)) {
        final diff = wait.difference(DateTime.now());
        print(
          '⏹️ translator fallback ถูกปิดชั่วคราว (${diff.inSeconds}s ที่เหลือ)',
        );
        return null;
      }
      if (wait != null && DateTime.now().isAfter(wait)) {
        _translatorDisabled = false;
        _translatorRetryAt = null;
        print('✅ translator fallback เปิดใช้อีกครั้งหลังพัก');
      } else if (wait == null) {
        return null;
      }
    }

    if (_translatorRetryAt != null && DateTime.now().isBefore(_translatorRetryAt!)) {
      final remaining = _translatorRetryAt!.difference(DateTime.now());
      print(
        '⏳ translator fallback รอคูลดาวน์อีก ${remaining.inSeconds}s',
      );
      return null;
    }

    try {
      final response = await _legacyTranslator.translate(
        text,
        from: 'en',
        to: 'th',
      );
      final result = response.text.trim();
      if (result.isEmpty) return null;
      await ApiUsageService.countTranslate();
      print('♻️ ใช้ translator fallback สำเร็จ');
      return result;
    } catch (e) {
      print('❌ Translation Error (fallback translator): $e');
      final lowered = e.toString().toLowerCase();
      if (lowered.contains('403')) {
        _translatorDisabled = true;
        final wait = DateTime.now().add(const Duration(minutes: 30));
        _translatorRetryAt = wait;
        print('⛔ translator fallback ได้รับ 403 → ปิดใช้งาน 30 นาที');
      } else if (lowered.contains('429') || lowered.contains('quota')) {
        final wait = DateTime.now().add(const Duration(minutes: 5));
        _translatorRetryAt = wait;
        print('⏳ translator fallback quota รอ 5 นาที (${wait.toIso8601String()})');
      }
      return null;
    }
  }

  static String _buildPrompt(String text) {
    return [
      'Translate the following text from English to Thai.',
      'Use concise, natural Thai suited for a cooking application.',
      'Respond with the translation only, without quotes or explanations.',
      'Text:',
      text,
    ].join('\n');
  }

  static Future<_HttpTranslationResult> _httpTranslate(
    String prompt,
    String apiKey,
  ) async {
    if (apiKey.isEmpty) return const _HttpTranslationResult();

    final payload = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.2,
        'topP': 0.9,
        'topK': 32,
        'maxOutputTokens': 256,
      },
    });

    const bases = [
      'https://generativelanguage.googleapis.com/v1beta',
      'https://generativelanguage.googleapis.com/v1',
    ];

    for (final base in bases) {
      final uri = Uri.parse(
        '$base/models/$_modelName:generateContent?key=$apiKey',
      );
      try {
        final res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: payload,
        );

        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          final text = _extractText(decoded);
          if (text != null && text.trim().isNotEmpty) {
            final cleaned = _sanitize(text) ?? text.trim();
            if (cleaned.isNotEmpty) {
              return _HttpTranslationResult(text: cleaned);
            }
          }
          return const _HttpTranslationResult();
        }

        final body = res.body.isNotEmpty ? res.body : '';
        print('⚠️ Translation REST error ${res.statusCode}: $body');

        var errorMessage = body;
        try {
          final json = jsonDecode(body);
          if (json is Map<String, dynamic>) {
            final err = json['error'];
            if (err is Map<String, dynamic>) {
              final msg = err['message'];
              if (msg is String && msg.trim().isNotEmpty) {
                errorMessage = msg;
              }
            }
          }
        } catch (_) {}

        final invalidKey =
            _looksLikeInvalidKey(errorMessage) ||
            res.statusCode == 401 ||
            res.statusCode == 403;
        final quotaHit = res.statusCode == 429 || _looksLikeQuota(errorMessage);
        final rotateKey = invalidKey || quotaHit;
        Duration? cooldown;

        final retryHeader = _parseRetryAfterHeader(res.headers);
        cooldown = retryHeader ?? _parseRetryAfter(errorMessage);

        if (quotaHit && cooldown == null) {
          cooldown = const Duration(seconds: 60);
        }

        return _HttpTranslationResult(
          quotaHit: quotaHit,
          rotateKey: rotateKey,
          cooldown: cooldown,
          invalidKey: invalidKey,
        );
      } catch (e) {
        print('❌ Translation REST exception: $e');
      }
    }

    return const _HttpTranslationResult();
  }

  static String? _sanitize(String? value) {
    if (value == null) return null;

    var output = value.trim();

    if (output.startsWith('```') && output.endsWith('```')) {
      final lines = output.split('\n');
      if (lines.length >= 2) {
        lines.removeAt(0);
        lines.removeLast();
        output = lines.join('\n').trim();
      }
    }

    output = output.replaceFirst(
      RegExp(r'^translation\s*:\s*', caseSensitive: false),
      '',
    );
    output = output.replaceFirst(
      RegExp(r'^thai\s*:\s*', caseSensitive: false),
      '',
    );
    output = output.replaceAll(RegExp(r"""^["'`]+"""), '');
    output = output.replaceAll(RegExp(r"""["'`]+$"""), '');

    return output.trim();
  }

  static String? _extractText(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final candidates = decoded['candidates'];
    if (candidates is! List) return null;

    for (final entry in candidates) {
      if (entry is! Map<String, dynamic>) continue;

      final content = entry['content'];
      if (content is Map<String, dynamic>) {
        final parts = content['parts'];
        if (parts is List) {
          for (final part in parts) {
            if (part is Map<String, dynamic>) {
              final text = part['text'];
              if (text is String) {
                return text;
              }
            }
          }
        }
      }

      final text = entry['text'];
      if (text is String) {
        return text;
      }
    }

    return null;
  }

  static bool _looksLikeInvalidKey(String message) {
    final lower = message.toLowerCase();
    return lower.contains('api key not valid') ||
        lower.contains('invalid api key') ||
        lower.contains('api_key_invalid') ||
        lower.contains('key is invalid') ||
        lower.contains('no api key');
  }

  static bool _looksLikeQuota(String message) {
    final lower = message.toLowerCase();
    return lower.contains('429') ||
        lower.contains('quota') ||
        lower.contains('exceeded') ||
        lower.contains('exhausted') ||
        lower.contains('retry in');
  }

  static bool _isSdkFormatBug(String message) {
    return message.toLowerCase().contains('unhandled format for content');
  }

  static Duration? _parseRetryAfter(String message) {
    final match = RegExp(
      r'in\s+([0-9.]+)s',
      caseSensitive: false,
    ).firstMatch(message);
    if (match == null) return null;
    final number = double.tryParse(match.group(1) ?? '');
    if (number == null) return null;
    final milliseconds = (number * 1000).round();
    if (milliseconds <= 0) return null;
    return Duration(milliseconds: milliseconds);
  }

  static Duration? _parseRetryAfterHeader(Map<String, String> headers) {
    final retry = headers.entries.firstWhere(
      (e) => e.key.toLowerCase() == 'retry-after',
      orElse: () => const MapEntry('', ''),
    );
    if (retry.key.isEmpty) return null;

    final value = retry.value.trim();
    if (value.isEmpty) return null;

    final seconds = double.tryParse(value);
    if (seconds != null) {
      final millis = (seconds * 1000).round();
      if (millis > 0) return Duration(milliseconds: millis);
    }

    // Retry-After can be HTTP date. Try to parse.
    final parsedDate = DateTime.tryParse(value);
    if (parsedDate != null) {
      final diff = parsedDate.difference(DateTime.now());
      if (diff > Duration.zero) return diff;
    }
    return null;
  }
}

class _HttpTranslationResult {
  final String? text;
  final bool quotaHit;
  final bool rotateKey;
  final Duration? cooldown;
  final bool invalidKey;

  const _HttpTranslationResult({
    this.text,
    this.quotaHit = false,
    this.rotateKey = false,
    this.cooldown,
    this.invalidKey = false,
  });
}
