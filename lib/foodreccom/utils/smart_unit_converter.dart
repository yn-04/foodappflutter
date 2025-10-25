// lib/foodreccom/utils/smart_unit_converter.dart
import 'dart:math' as math;

import 'package:my_app/common/measurement_constants.dart';
import 'package:my_app/common/smart_unit_converter.dart' as piece_converter;
import '../constants/unit_conversions.dart';
import '../services/unit_conversion_service.dart'; // การเรียก Spoonacular (ถ้ามี)
import 'ingredient_translator.dart';

class SmartUnitConverter {
  // ฟังก์ชัน toCanonicalQuantity เดิม
  static CanonicalQuantity toCanonicalQuantity(
    double amount,
    String unit,
    String ingredientName,
  ) {
    final lower = unit.trim().toLowerCase();

    if (weightUnits.containsKey(lower)) {
      return CanonicalQuantity(amount * weightUnits[lower]!, 'gram');
    }
    if (volumeUnits.containsKey(lower)) {
      return CanonicalQuantity(amount * volumeUnits[lower]!, 'milliliter');
    }
    if (pieceUnits.contains(lower)) {
      return CanonicalQuantity(amount, 'piece');
    }
    // ถ้าไม่รู้จักหน่วย ให้ถือว่าเป็น gram ไปก่อน (อาจปรับปรุงให้ดีขึ้นได้)
    return CanonicalQuantity(amount, 'gram');
  }

  /// ฟังก์ชันใหม่: แปลงหน่วยจากสูตรอาหารให้อยู่ในหน่วยของคลัง (กรัม หรือ มิลลิลิตร)
  /// โดยใช้ทั้งการคำนวณเบื้องต้นและเรียก API
  static Future<CanonicalQuantity?> convertRecipeUnitToInventoryUnit({
    required String ingredientName,
    required double recipeAmount,
    required String recipeUnit,
  }) async {
    final conversionService = UnitConversionService();
    final lowerRecipeUnit = recipeUnit.trim().toLowerCase();
    final lowerIngredientName = ingredientName.trim().toLowerCase();

    // 🥚 หน่วยแบบชิ้น – ใช้ rule จาก common smart converter (รองรับไข่/ฟอง)
    final pieceRule = piece_converter.SmartUnitConverter.pieceRuleFor(
      lowerIngredientName,
      lowerRecipeUnit,
    );

    if (pieceRule != null) {
      if (pieceRule.displayUnit.trim() == 'ฟอง') {
        // แปลงเป็นจำนวนฟองตรงๆ (ไม่ต้องเรียก API)
        return CanonicalQuantity(recipeAmount, 'ฟอง');
      }
      final grams = piece_converter.SmartUnitConverter.gramsFromPiece(
        recipeAmount,
        lowerRecipeUnit,
        lowerIngredientName,
      );
      if (grams != null && grams > 0) {
        return CanonicalQuantity(grams, 'gram');
      }
    }

    if (piece_converter.SmartUnitConverter.isPieceUnit(lowerRecipeUnit)) {
      // ถ้าเป็นหน่วยชิ้นแต่ไม่เจอ rule ให้ fallback เป็นกรัมตามค่าเฉลี่ย
      final grams = piece_converter.SmartUnitConverter.gramsFromPiece(
        recipeAmount,
        lowerRecipeUnit,
        lowerIngredientName,
      );
      if (grams != null && grams > 0) {
        return CanonicalQuantity(grams, 'gram');
      }
      // หากยังไม่ได้ ให้ถือว่าเป็นชิ้น โดยเทียบกับ 1 ชิ้น = 1 หน่วย
      return CanonicalQuantity(recipeAmount, 'piece');
    }

    // หน่วยที่มี mapping แบบกำหนดเอง (เช่น ช้อนแกง, กำมือ)
    final manualRule = _manualUnitRules[lowerRecipeUnit];
    if (manualRule != null) {
      return CanonicalQuantity(
        recipeAmount * manualRule.multiplier,
        manualRule.canonicalUnit,
      );
    }

    // กรณีหน่วยพื้นฐานที่แปลงได้โดยตรง (Weight to Weight, Volume to Volume)
    if (weightUnits.containsKey(lowerRecipeUnit)) {
      final grams = recipeAmount * weightUnits[lowerRecipeUnit]!;
      return CanonicalQuantity(grams, 'gram');
    }
    if (volumeUnits.containsKey(lowerRecipeUnit)) {
      final milliliters = recipeAmount * volumeUnits[lowerRecipeUnit]!;
      return CanonicalQuantity(milliliters, 'milliliter');
    }

    // กรณีหน่วยแบบ serving หรือคำอื่นๆ ที่ Spoonacular ใช้ แต่ไม่อยู่ในตาราง
    if (_servingLikeUnits.contains(lowerRecipeUnit)) {
      // พยายามใช้ API แปลงเป็นกรัมก่อน
      final converted = await conversionService.convertAmount(
        ingredientName: ingredientName,
        sourceAmount: recipeAmount,
        sourceUnit: recipeUnit,
        targetUnit: 'grams',
      );
      if (converted != null && converted > 0) {
        return CanonicalQuantity(converted, 'gram');
      }
    }

    if (_shouldSkipDynamicConversion(lowerIngredientName)) {
      return null;
    }

    // กรณีที่ต้องแปลงข้ามประเภท (เช่น cup -> gram) ต้องใช้ API
    // ลองพยายามแปลงเป็น 'gram' ก่อน (ถ้ามี network key)
    double? convertedAmount = await _safeConvert(
      service: conversionService,
      ingredientName: ingredientName,
      sourceAmount: recipeAmount,
      sourceUnit: recipeUnit,
      targetUnit: 'grams',
    );

    if (convertedAmount != null) {
      return CanonicalQuantity(convertedAmount, 'gram');
    }

    // ถ้าแปลงเป็น gram ไม่ได้ ลองแปลงเป็น 'ml'
    convertedAmount = await _safeConvert(
      service: conversionService,
      ingredientName: ingredientName,
      sourceAmount: recipeAmount,
      sourceUnit: recipeUnit,
      targetUnit: 'ml',
    );

    if (convertedAmount != null) {
      return CanonicalQuantity(convertedAmount, 'milliliter');
    }

    final fallback = toCanonicalQuantity(
      recipeAmount,
      recipeUnit,
      ingredientName,
    );
    if (fallback.amount > 0) {
      return fallback;
    }
    return null; // ไม่สามารถแปลงหน่วยได้ (กรณีปริมาณ 0)
  }

  // ฟังก์ชัน convertCanonicalToUnit เดิม
  static double convertCanonicalToUnit({
    required String canonicalUnit,
    required double canonicalAmount,
    required String targetUnit,
    required String ingredientName,
  }) {
    final lower = targetUnit.trim().toLowerCase();
    if (canonicalUnit == 'gram' && weightUnits.containsKey(lower)) {
      return canonicalAmount / weightUnits[lower]!;
    }
    if (canonicalUnit == 'milliliter' && volumeUnits.containsKey(lower)) {
      return canonicalAmount / volumeUnits[lower]!;
    }
    return canonicalAmount;
  }

  /// 🔢 ค่าความหนาแน่นโดยประมาณ (กรัม/มิลลิลิตร) สำหรับวัตถุดิบที่พบบ่อย
  static double? densityForIngredient(String ingredientName) {
    final normalized = _normalizeForDensity(ingredientName);
    final translated = _normalizeForDensity(
      IngredientTranslator.translate(ingredientName),
    );

    for (final entry in _densityTable.entries) {
      final key = entry.key;
      if (normalized.contains(key) || translated.contains(key)) {
        return entry.value;
      }
    }
    return _densityTable['default'];
  }
}

class CanonicalQuantity {
  final double amount;
  final String unit; // 'gram', 'milliliter', 'piece', 'ฟอง'
  const CanonicalQuantity(this.amount, this.unit);
}

/// 🧭 หน่วยที่มีความหมายคล้าย "เสิร์ฟ/ที่" ซึ่งมักต้องใช้ API ในการเทียบ
const Set<String> _servingLikeUnits = {
  'serving',
  'servings',
  'ที่',
  'portion',
  '份',
};

const Map<String, double> _densityTable = {
  'default': 1.0,
  'water': 1.0,
  'น้ำ': 1.0,
  'น้ำเปล่า': 1.0,
  'milk': 1.03,
  'นม': 1.03,
  'นมสด': 1.03,
  'coconut milk': 0.97,
  'กะทิ': 0.97,
  'condensed milk': 1.3,
  'นมข้นหวาน': 1.3,
  'sugar': 0.85,
  'น้ำตาล': 0.85,
  'น้ำตาลทราย': 0.85,
  'brown sugar': 0.75,
  'icing sugar': 0.6,
  'salt': 1.2,
  'sea salt': 1.2,
  'เกลือ': 1.2,
  'soy sauce': 1.1,
  'ซีอิ๊ว': 1.1,
  'fish sauce': 1.2,
  'น้ำปลา': 1.2,
  'oyster sauce': 1.09,
  'ซอสหอยนางรม': 1.09,
  'oil': 0.92,
  'vegetable oil': 0.92,
  'olive oil': 0.91,
  'น้ำมัน': 0.92,
  'น้ำมันพืช': 0.92,
  'น้ำมันมะกอก': 0.91,
  'butter': 0.95,
  'เนย': 0.95,
  'honey': 1.42,
  'น้ำผึ้ง': 1.42,
  'flour': 0.53,
  'แป้ง': 0.53,
  'แป้งสาลี': 0.53,
  'rice': 0.85,
  'ข้าวสาร': 0.85,
  'garlic': 0.6,
  'กระเทียม': 0.6,
  'onion': 0.85,
  'หอมหัวใหญ่': 0.85,
};

String _normalizeForDensity(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class _ManualUnitRule {
  final double multiplier;
  final String canonicalUnit;
  const _ManualUnitRule(this.multiplier, this.canonicalUnit);
}

const Map<String, _ManualUnitRule> _manualUnitRules = {
  'ช้อนแกง': _ManualUnitRule(
    MeasurementConstants.millilitersPerTablespoon,
    'milliliter',
  ),
  'ช้อนกินข้าว': _ManualUnitRule(
    MeasurementConstants.millilitersPerTablespoon,
    'milliliter',
  ),
  'ช้อนซุป': _ManualUnitRule(
    MeasurementConstants.millilitersPerTablespoon,
    'milliliter',
  ),
  'ช้อนกาแฟ': _ManualUnitRule(
    MeasurementConstants.millilitersPerTeaspoon,
    'milliliter',
  ),
  'ช้อนหวาน': _ManualUnitRule(
    MeasurementConstants.millilitersPerTeaspoon,
    'milliliter',
  ),
  'ช้อนชาเล็ก': _ManualUnitRule(
    MeasurementConstants.millilitersPerTeaspoon,
    'milliliter',
  ),
  'แก้ว': _ManualUnitRule(MeasurementConstants.millilitersPerCup, 'milliliter'),
  'แก้วน้ำ': _ManualUnitRule(
    MeasurementConstants.millilitersPerCup,
    'milliliter',
  ),
  'ถ้วยตวง': _ManualUnitRule(
    MeasurementConstants.millilitersPerCup,
    'milliliter',
  ),
  'ทัพพี': _ManualUnitRule(
    MeasurementConstants.millilitersPerCup / 2,
    'milliliter',
  ),
  'กำมือ': _ManualUnitRule(15, 'gram'),
  'หยิบมือ': _ManualUnitRule(5, 'gram'),
  'ซอง': _ManualUnitRule(12, 'gram'),
  'กระป๋อง': _ManualUnitRule(400, 'milliliter'),
};

bool _shouldSkipDynamicConversion(String lowerIngredientName) {
  if (lowerIngredientName.isEmpty) return true;
  if (lowerIngredientName.length > 80) return true;
  const ignoredKeywords = [
    'ตามความชอบ',
    'ที่ชอบ',
    'แนะนำให้',
    'optional',
    'กะพอประมาณ',
    'ตกแต่ง',
    'สำหรับเสิร์ฟ',
    'purefoods',
    'เลือกใช้',
    'ตามต้องการ',
    'ตามใจชอบ',
  ];
  for (final keyword in ignoredKeywords) {
    if (lowerIngredientName.contains(keyword)) {
      return true;
    }
  }
  return false;
}

Future<double?> _safeConvert({
  required UnitConversionService service,
  required String ingredientName,
  required double sourceAmount,
  required String sourceUnit,
  required String targetUnit,
}) async {
  try {
    final amount = await service.convertAmount(
      ingredientName: ingredientName,
      sourceAmount: sourceAmount,
      sourceUnit: sourceUnit,
      targetUnit: targetUnit,
    );
    if (amount == null) return null;
    if (!amount.isFinite) return null;
    if (amount <= 0) return null;
    if (targetUnit == 'grams') {
      return math.max(0, amount);
    }
    if (targetUnit == 'ml') {
      return math.max(0, amount);
    }
    return amount;
  } catch (e) {
    return null;
  }
}
