// lib/foodreccom/utils/smart_unit_converter.dart
import 'dart:math' as math;

import 'package:my_app/common/measurement_constants.dart';
import 'package:my_app/common/smart_unit_converter.dart' as piece_converter;
import '../constants/unit_conversions.dart';
import '../services/unit_conversion_service.dart'; // การเรียก Spoonacular (แผน A.2)
// ✅ [ใหม่] Import แผน B (Gemini)
import '../services/ai_unit_conversion_service.dart';
import 'ingredient_translator.dart';

class SmartUnitConverter {
  // ✅ [ใหม่] สร้าง Instance ของ Service ทั้งสอง
  static final _spoonacularService = UnitConversionService();
  static final _aiService = AiUnitConversionService();

  // ฟังก์ชัน toCanonicalQuantity เดิม (ยังคงอยู่เผื่อการใช้งานอื่น)
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

  /// ⭐️ [อัปเกรด] ฟังก์ชันหลักที่ใช้ตรรกะแบบไฮบริด (Hybrid Logic) ⭐️
  static Future<CanonicalQuantity?> convertRecipeUnitToInventoryUnit({
    required String ingredientName,
    required double recipeAmount,
    required String recipeUnit,
  }) async {
    final lowerRecipeUnit = recipeUnit.trim().toLowerCase();
    final lowerIngredientName = ingredientName.trim().toLowerCase();
    final unitCandidates = _expandUnitCandidates(lowerRecipeUnit);
    final translatedIngredientName =
        IngredientTranslator.translate(ingredientName)
            .trim()
            .toLowerCase();
    final gramsPerPieceHint =
        piece_converter.SmartUnitConverter.gramsPerPiece(ingredientName);
    final ingredientCategory = _classifyIngredientForAi(
      lowerIngredientName,
      translatedIngredientName,
      gramsPerPieceHint,
    );

    // 0. ตรวจสอบเงื่อนไขที่ควรข้าม
    if (_shouldSkipDynamicConversion(lowerIngredientName)) {
      return null;
    }

    // === แผน A.1: "กฎ" ภายในแอป (เร็วที่สุด) ===

    // 🥚 1. กฎสำหรับ "ชิ้น" (ไข่/ฟอง, ฯลฯ)
    piece_converter.PieceUnitInfo? pieceRule;
    String? pieceUnitCandidate;
    for (final candidate in unitCandidates) {
      final rule = piece_converter.SmartUnitConverter.pieceRuleFor(
        lowerIngredientName,
        candidate,
      );
      if (rule != null) {
        pieceRule = rule;
        pieceUnitCandidate = candidate;
        break;
      }
    }
    pieceRule ??= piece_converter.SmartUnitConverter.pieceRuleFor(
      lowerIngredientName,
      lowerRecipeUnit,
    );

    if (pieceRule != null) {
      if (pieceRule.displayUnit.trim() == 'ฟอง') {
        return CanonicalQuantity(recipeAmount, 'ฟอง');
      }
      final grams = piece_converter.SmartUnitConverter.gramsFromPiece(
        recipeAmount,
        pieceUnitCandidate ?? lowerRecipeUnit,
        lowerIngredientName,
      );
      if (grams != null && grams > 0) {
        return CanonicalQuantity(grams, 'gram');
      }
    }
    final isPieceUnit = unitCandidates.any(
      (candidate) => piece_converter.SmartUnitConverter.isPieceUnit(candidate),
    );
    if (isPieceUnit) {
      final pieceUnit = unitCandidates.firstWhere(
        (candidate) => piece_converter.SmartUnitConverter.isPieceUnit(candidate),
        orElse: () => lowerRecipeUnit,
      );
      final grams = piece_converter.SmartUnitConverter.gramsFromPiece(
        recipeAmount,
        pieceUnit,
        lowerIngredientName,
      );
      if (grams != null && grams > 0) {
        return CanonicalQuantity(grams, 'gram');
      }
      return CanonicalQuantity(recipeAmount, 'piece');
    }

    // 📜 2. กฎสำหรับ "หน่วยตวงไทย" (ช้อนแกง, กำมือ, ฯลฯ)
    for (final candidate in unitCandidates) {
      final manualRule = _manualUnitRules[candidate];
      if (manualRule != null) {
        final manualAmount = recipeAmount * manualRule.multiplier;
        if (manualRule.canonicalUnit == 'milliliter') {
          final density = densityForIngredient(ingredientName);
          if (_shouldConvertVolumeToMass(ingredientCategory, density)) {
            final grams = density != null ? manualAmount * density : manualAmount;
            if (grams > 0) {
              return CanonicalQuantity(grams, 'gram');
            }
          }
        }
        return CanonicalQuantity(
          manualAmount,
          manualRule.canonicalUnit,
        );
      }
    }

    // ⚖️ 3. กฎสำหรับ "หน่วยมาตรฐาน" (g -> g, ml -> ml)
    for (final candidate in unitCandidates) {
      final factor = weightUnits[candidate];
      if (factor != null) {
        final grams = recipeAmount * factor;
        return CanonicalQuantity(grams, 'gram');
      }
    }
    for (final candidate in unitCandidates) {
      final factor = volumeUnits[candidate];
      if (factor != null) {
        final milliliters = recipeAmount * factor;
        return CanonicalQuantity(milliliters, 'milliliter');
      }
    }

    // === แผน A.2: "Spoonacular API" (แผนสำรองที่ 1) ===

    // 🌐 4. กฎสำหรับหน่วย 'serving' (ต้องใช้ API)
    if (_servingLikeUnits.contains(lowerRecipeUnit)) {
      final converted = await _safeConvert(
        service: _spoonacularService,
        ingredientName: ingredientName,
        sourceAmount: recipeAmount,
        sourceUnit: recipeUnit,
        targetUnit: 'grams',
      );
      if (converted != null && converted > 0) {
        return CanonicalQuantity(converted, 'gram');
      }
    }

    // 🌐 5. ลองแปลงข้ามประเภท (เช่น cup -> gram) ด้วย Spoonacular
    double? convertedAmount = await _safeConvert(
      service: _spoonacularService,
      ingredientName: ingredientName,
      sourceAmount: recipeAmount,
      sourceUnit: recipeUnit,
      targetUnit: 'grams',
    );

    if (convertedAmount != null) {
      return CanonicalQuantity(convertedAmount, 'gram');
    }

    convertedAmount = await _safeConvert(
      service: _spoonacularService,
      ingredientName: ingredientName,
      sourceAmount: recipeAmount,
      sourceUnit: recipeUnit,
      targetUnit: 'ml',
    );

    if (convertedAmount != null) {
      return CanonicalQuantity(convertedAmount, 'milliliter');
    }

    // === ✅ [ใหม่] แผน B: "Gemini AI" (แผนสำรองสุดท้าย) ===
    print('⚠️ "กฎ" และ "Spoonacular" แปลงไม่ได้. ลองใช้ AI (Fallback)...');

    // 🤖 6. เรียก AI (Gemini)
    final aiResult = await _aiService.convertWithAi(
      ingredientName: ingredientName,
      recipeAmount: recipeAmount,
      recipeUnit: recipeUnit,
    );

    if (aiResult != null) {
      return aiResult; // AI ช่วยแปลงได้สำเร็จ
    }

    // === ล้มเหลวทั้งหมด ===
    print(
      '❌ "กฎ", "Spoonacular" และ "AI" ล้มเหลวทั้งหมดสำหรับ: $ingredientName ($recipeUnit)',
    );

    // 7. ใช้ Fallback ตัวเก่าตัวสุดท้าย (เผื่อไว้)
    final fallback = toCanonicalQuantity(
      recipeAmount,
      recipeUnit,
      ingredientName,
    );
    if (fallback.amount > 0) {
      return fallback;
    }

    return null; // ไม่สามารถแปลงหน่วยได้จริงๆ
  }

  // (ฟังก์ชันที่เหลือเหมือนเดิมทั้งหมด)
  // ...
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

  /// 🔍 สร้าง context สำหรับ AI prompt เพื่อช่วยให้โมเดลเข้าใจวัตถุดิบมากขึ้น
  static AiIngredientContext buildAiIngredientContext(String ingredientName) {
    final normalized = _normalizeForDensity(ingredientName);
    final translated = _normalizeForDensity(
      IngredientTranslator.translate(ingredientName),
    );
    final gramsPerPiece =
        piece_converter.SmartUnitConverter.gramsPerPiece(ingredientName);
    final density = densityForIngredient(ingredientName);
    final category = _classifyIngredientForAi(
      normalized,
      translated,
      gramsPerPiece,
    );

    final aliases = <String>{
      ingredientName.trim(),
      IngredientTranslator.translate(ingredientName).trim(),
      normalized,
      translated,
    }..removeWhere((value) => value.isEmpty);

    return AiIngredientContext(
      category: category,
      density: density,
      gramsPerPiece: gramsPerPiece,
      aliases: aliases.take(_maxAliasesForAi).toList(),
    );
  }

  /// 🔁 คืนตัวอย่างการแปลงหน่วยที่มักเจอ เพื่อแนบบอก AI
  static List<String> aiSampleConversions() =>
      List<String>.from(_aiSampleConversions);

  static String _classifyIngredientForAi(
    String normalized,
    String translated,
    double? gramsPerPiece,
  ) {
    final corpus = '$normalized $translated';
    if (gramsPerPiece != null) return 'piece-produce';
    if (_containsKeyword(corpus, _liquidKeywords)) return 'liquid';
    if (_containsKeyword(corpus, _sauceKeywords)) return 'sauce';
    if (_containsKeyword(corpus, _powderKeywords)) return 'dry-solid';
    if (_containsKeyword(corpus, _herbKeywords)) return 'fresh-herb';
    if (_containsKeyword(corpus, _proteinKeywords)) return 'protein';
    return 'solid';
  }

  static bool _containsKeyword(String corpus, Set<String> keywords) {
    for (final keyword in keywords) {
      if (keyword.isEmpty) continue;
      if (corpus.contains(keyword)) return true;
    }
    return false;
  }
}

class AiIngredientContext {
  final String category;
  final double? density;
  final double? gramsPerPiece;
  final List<String> aliases;

  const AiIngredientContext({
    required this.category,
    required this.density,
    required this.gramsPerPiece,
    required this.aliases,
  });

  Map<String, dynamic> toPromptMap() {
    return {
      'category': category,
      if (density != null) 'density_g_per_ml': density,
      if (gramsPerPiece != null) 'grams_per_piece': gramsPerPiece,
      if (aliases.isNotEmpty) 'aliases': aliases,
    };
  }
}

// ⭐️ [สำคัญ] นี่คือ Class ที่ CookingService ต้องใช้
// (เราย้ายมันมาไว้ที่นี่เพื่อให้ไฟล์อื่น import ได้)
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
  'น้ำซุป': 1.01,
  'broth': 1.01,
  'milk': 1.03,
  'นม': 1.03,
  'นมสด': 1.03,
  'evaporated milk': 1.06,
  'condensed milk': 1.3,
  'นมข้น': 1.3,
  'นมข้นหวาน': 1.3,
  'coconut milk': 0.97,
  'กะทิ': 0.97,
  'coconut water': 1.02,
  'น้ำมะพร้าว': 1.02,
  'sugar': 0.85,
  'น้ำตาล': 0.85,
  'น้ำตาลทราย': 0.85,
  'brown sugar': 0.75,
  'icing sugar': 0.6,
  'palm sugar': 1.32,
  'น้ำตาลปี๊บ': 1.32,
  'coconut sugar': 1.3,
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
  'chili paste': 1.05,
  'น้ำพริกเผา': 1.05,
  'butter': 0.95,
  'เนย': 0.95,
  'margarine': 0.95,
  'honey': 1.42,
  'น้ำผึ้ง': 1.42,
  'flour': 0.53,
  'แป้ง': 0.53,
  'แป้งสาลี': 0.53,
  'rice flour': 0.57,
  'แป้งข้าวเจ้า': 0.57,
  'glutinous rice flour': 0.55,
  'แป้งข้าวเหนียว': 0.55,
  'cornstarch': 0.54,
  'แป้งข้าวโพด': 0.54,
  'rice': 0.85,
  'ข้าวสาร': 0.85,
  'jasmine rice': 0.83,
  'ข้าวหอมมะลิ': 0.83,
  'garlic': 0.6,
  'กระเทียม': 0.6,
  'onion': 0.85,
  'หอมหัวใหญ่': 0.85,
  'shallot': 0.75,
  'หอมแดง': 0.75,
  'ginger': 0.74,
  'ขิง': 0.74,
  'galangal': 0.72,
  'ข่า': 0.72,
  'lemongrass': 0.6,
  'ตะไคร้': 0.6,
  'holy basil': 0.2,
  'กะเพรา': 0.2,
  'โหระพา': 0.2,
  'coriander': 0.21,
  'ผักชี': 0.21,
  'spring onion': 0.25,
  'ต้นหอม': 0.25,
  'carrot': 0.64,
  'แครอท': 0.64,
  'potato': 0.75,
  'มันฝรั่ง': 0.75,
  'cabbage': 0.65,
  'กะหล่ำปลี': 0.65,
  'bell pepper': 0.35,
  'พริกหวาน': 0.35,
  'chicken': 1.03,
  'ไก่': 1.03,
  'pork': 1.05,
  'หมู': 1.05,
  'beef': 1.04,
  'เนื้อวัว': 1.04,
  'shrimp': 1.05,
  'กุ้ง': 1.05,
  'squid': 1.02,
  'ปลาหมึก': 1.02,
  'fish': 1.03,
  'ปลา': 1.03,
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
  'ช้อนโต๊ะ': _ManualUnitRule(
    MeasurementConstants.millilitersPerTablespoon,
    'milliliter',
  ),
  'ช้อนโต๊ะพูน': _ManualUnitRule(18, 'milliliter'),
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
  'ช้อนชา': _ManualUnitRule(
    MeasurementConstants.millilitersPerTeaspoon,
    'milliliter',
  ),
  'ช้อนชาเล็ก': _ManualUnitRule(
    MeasurementConstants.millilitersPerTeaspoon,
    'milliliter',
  ),
  'ช้อนชาเล็กพูน': _ManualUnitRule(7, 'milliliter'),
  'แก้ว': _ManualUnitRule(MeasurementConstants.millilitersPerCup, 'milliliter'),
  'แก้วน้ำ': _ManualUnitRule(
    MeasurementConstants.millilitersPerCup,
    'milliliter',
  ),
  'ถ้วยตวง': _ManualUnitRule(
    MeasurementConstants.millilitersPerCup,
    'milliliter',
  ),
  'ถ้วย': _ManualUnitRule(
    MeasurementConstants.millilitersPerCup,
    'milliliter',
  ),
  'ถ้วยชา': _ManualUnitRule(180, 'milliliter'),
  'ถ้วยเล็ก': _ManualUnitRule(120, 'milliliter'),
  'ทัพพี': _ManualUnitRule(
    MeasurementConstants.millilitersPerCup / 2,
    'milliliter',
  ),
  'กำมือ': _ManualUnitRule(15, 'gram'),
  'หยิบมือ': _ManualUnitRule(5, 'gram'),
  'ซอง': _ManualUnitRule(12, 'gram'),
  'กระป๋อง': _ManualUnitRule(400, 'milliliter'),
  'กระป๋องนม': _ManualUnitRule(385, 'gram'),
  'กระป๋องนมข้น': _ManualUnitRule(385, 'gram'),
  'กระป๋องนมข้นหวาน': _ManualUnitRule(385, 'gram'),
  'ขวด': _ManualUnitRule(500, 'milliliter'),
  'ขวดเล็ก': _ManualUnitRule(330, 'milliliter'),
  'ขีด': _ManualUnitRule(100, 'gram'),
  'ครึ่งขีด': _ManualUnitRule(50, 'gram'),
  'เสี้ยวขีด': _ManualUnitRule(25, 'gram'),
  'แพ็ค': _ManualUnitRule(200, 'gram'),
};

const int _maxAliasesForAi = 10;

const List<String> _aiSampleConversions = [
  '1 ถ้วยตวง ข้าวหอมมะลิ (ดิบ) ≈ 160 gram',
  '2 ช้อนโต๊ะ น้ำปลา ≈ 30 milliliter',
  '1 กระป๋องนมข้นหวาน ≈ 385 gram',
  '3 กลีบ กระเทียมสด ≈ 15 gram',
  '1 กำ โหระพา ≈ 25 gram',
  '200 milliliter น้ำกะทิ ≈ 200 gram',
  '1 ตัว ปลากะพงขาว (ขนาดกลาง) ≈ 300 gram',
];

const Set<String> _liquidKeywords = {
  'น้ำ',
  'ซุป',
  'น้ำซุป',
  'milk',
  'cream',
  'creamery',
  'oil',
  'น้ำมัน',
  'vinegar',
  'ซีอิ๊ว',
  'น้ำปลา',
  'น้ำสต๊อก',
  'broth',
  'stock',
  'น้ำซอส',
  'coconut milk',
  'coconut water',
  'น้ำมะพร้าว',
  'น้ำมะนาว',
  'น้ำส้ม',
};

const Set<String> _sauceKeywords = {
  'sauce',
  'ซอส',
  'น้ำพริก',
  'น้ำพริกเผา',
  'paste',
  'condensed milk',
  'oyster',
  'fish sauce',
  'soy sauce',
  'ketchup',
  'mayonnaise',
};

const Set<String> _powderKeywords = {
  'ผง',
  'powder',
  'flour',
  'starch',
  'แป้ง',
  'seasoning',
  'เกลือ',
  'salt',
  'sugar',
  'ผงฟู',
  'baking powder',
};

const Set<String> _herbKeywords = {
  'โหระพา',
  'กะเพรา',
  'ใบกะเพรา',
  'basil',
  'holy basil',
  'sweet basil',
  'coriander',
  'cilantro',
  'ผักชี',
  'spring onion',
  'ต้นหอม',
  'พริก',
  'sliced chili',
  'mint',
  'สะระแหน่',
  'kaffir lime leaf',
  'ใบมะกรูด',
  'lemongrass',
  'ตะไคร้',
};

const Set<String> _proteinKeywords = {
  'หมู',
  'pork',
  'ไก่',
  'chicken',
  'beef',
  'เนื้อวัว',
  'ปลา',
  'fish',
  'shrimp',
  'กุ้ง',
  'ปลาหมึก',
  'squid',
  'ไข่',
  'egg',
  'duck',
  'เป็ด',
};

Set<String> _expandUnitCandidates(String unit) {
  final trimmed = unit.trim();
  if (trimmed.isEmpty) return const <String>{};

  final candidates = <String>{};
  void addCandidate(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isNotEmpty) candidates.add(normalized);
  }

  addCandidate(trimmed);

  final withoutParens =
      trimmed.replaceAll(RegExp(r'[\(\)\[\]\{\}]'), ' ');
  addCandidate(withoutParens);

  final strippedSymbols =
      withoutParens.replaceAll(RegExp(r'[^a-zA-Zก-๙\.]'), ' ');
  addCandidate(strippedSymbols);

  for (final token in withoutParens
      .split(RegExp(r'[\/\s]+'))
      .where((t) => t.isNotEmpty)) {
    addCandidate(token);
  }

  final compactAlpha =
      withoutParens.replaceAll(RegExp(r'[^a-zA-Zก-๙]'), '');
  addCandidate(compactAlpha);

  return candidates;
}

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

bool _shouldConvertVolumeToMass(String ingredientCategory, double? density) {
  if (density == null || density <= 0) return false;
  if (ingredientCategory == 'liquid' || ingredientCategory == 'sauce') {
    return false;
  }
  return true;
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
