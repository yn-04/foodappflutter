import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class UnitConversionService {
  static bool _warnedMissingKey = false;
  static bool _warnedUnauthorized = false;

  final String _apiKey;

  UnitConversionService({String? apiKey})
      : _apiKey = (apiKey ??
                (dotenv.isInitialized
                    ? (dotenv.env['SPOONACULAR_API_KEY'] ?? '')
                    : ''))
            .trim();

  bool get _hasValidKey =>
      _apiKey.isNotEmpty && _apiKey != 'YOUR_SPOONACULAR_API_KEY';

  Future<double?> convertAmount({
    required String ingredientName,
    required double sourceAmount,
    required String sourceUnit,
    required String targetUnit,
  }) async {
    if (!_hasValidKey) {
      if (!_warnedMissingKey) {
        debugPrint(
          '⚠️ Spoonacular API key ไม่ได้ตั้งค่า (SPOONACULAR_API_KEY) — ข้ามการแปลงหน่วยภายนอก',
        );
        _warnedMissingKey = true;
      }
      return null;
    }

    final url = Uri.https(
      'api.spoonacular.com',
      '/recipes/convert',
      {
        'ingredientName': ingredientName,
        'sourceAmount': sourceAmount.toString(),
        'sourceUnit': sourceUnit,
        'targetUnit': targetUnit,
        'apiKey': _apiKey,
      },
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final target = data['targetAmount'];
        if (target is num) {
          return target.toDouble();
        }
        return null;
      }

      if (response.statusCode == 401) {
        if (!_warnedUnauthorized) {
          debugPrint(
            '⚠️ Spoonacular API unauthorized (401) — ตรวจสอบค่า SPOONACULAR_API_KEY',
          );
          _warnedUnauthorized = true;
        }
        return null;
      }

      debugPrint(
        'Spoonacular API Error (${response.statusCode}): ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('Error calling Spoonacular API: $e');
      return null;
    }
  }
}
