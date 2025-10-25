// lib/common/smart_unit_converter.dart
import 'measurement_constants.dart';

class PieceUnitInfo {
  final List<String> keywords;
  final String displayUnit;
  final double gramsPerUnit;
  final List<String> unitSynonyms;

  const PieceUnitInfo({
    required this.keywords,
    required this.displayUnit,
    required this.gramsPerUnit,
    this.unitSynonyms = const [],
  });

  bool matchesName(String lowerName) =>
      keywords.any((keyword) => lowerName.contains(keyword));

  bool matchesUnit(String lowerUnit) {
    final syns = <String>{
      displayUnit,
      ...unitSynonyms,
    }.map((s) => s.trim().toLowerCase()).toSet();
    return syns.contains(lowerUnit);
  }
}

class SmartUnitConverter {
  // 🔹 กำหนด rule สำหรับวัตถุดิบที่มีหน่วยเป็น "ชิ้น"
  static final List<PieceUnitInfo> _pieceRules = [
    const PieceUnitInfo(
      keywords: ['ไข่', 'egg'],
      displayUnit: 'ฟอง',
      gramsPerUnit: 50,
      unitSynonyms: ['egg', 'eggs'],
    ),
    const PieceUnitInfo(
      keywords: ['กระเทียม', 'garlic'],
      displayUnit: 'กลีบ',
      gramsPerUnit: 5,
      unitSynonyms: ['clove', 'cloves'],
    ),
    const PieceUnitInfo(
      keywords: ['ต้นหอม', 'scallion', 'spring onion', 'green onion'],
      displayUnit: 'ต้น',
      gramsPerUnit: 15,
      unitSynonyms: ['stalk', 'stalks'],
    ),
    const PieceUnitInfo(
      keywords: ['หอมใหญ่', 'หัวหอม', 'หอมแดง', 'onion', 'shallot'],
      displayUnit: 'หัว',
      gramsPerUnit: 167,
      unitSynonyms: ['onions', 'shallots'],
    ),
    const PieceUnitInfo(
      keywords: ['มะเขือเทศ', 'tomato'],
      displayUnit: 'ลูก',
      gramsPerUnit: 125,
      unitSynonyms: ['tomatoes', 'ผล'],
    ),
    const PieceUnitInfo(
      keywords: ['มะนาว', 'lime', 'lemon'],
      displayUnit: 'ลูก',
      gramsPerUnit: 60,
      unitSynonyms: ['limes', 'lemons', 'ผล'],
    ),
    const PieceUnitInfo(
      keywords: ['พริก', 'chili', 'chilli', 'pepper'],
      displayUnit: 'เม็ด',
      gramsPerUnit: 4,
      unitSynonyms: ['chilies', 'chiles', 'เมล็ด'],
    ),
    const PieceUnitInfo(
      keywords: ['แครอท', 'carrot'],
      displayUnit: 'หัว',
      gramsPerUnit: 130,
      unitSynonyms: ['carrots', 'ผล'],
    ),
    const PieceUnitInfo(
      keywords: ['กล้วย', 'banana'],
      displayUnit: 'ลูก',
      gramsPerUnit: 120,
      unitSynonyms: ['bananas', 'ผล'],
    ),
    const PieceUnitInfo(
      keywords: ['แอปเปิ้ล', 'apple'],
      displayUnit: 'ลูก',
      gramsPerUnit: 180,
      unitSynonyms: ['apples', 'ผล'],
    ),
    const PieceUnitInfo(
      keywords: ['กุ้ง', 'shrimp', 'prawn'],
      displayUnit: 'ตัว',
      gramsPerUnit: 15,
      unitSynonyms: ['shrimps', 'prawns'],
    ),
    const PieceUnitInfo(
      keywords: ['เห็ด', 'mushroom'],
      displayUnit: 'ดอก',
      gramsPerUnit: 20,
      unitSynonyms: ['mushrooms'],
    ),
  ];

  // 🔸 Rule สำรอง (ถ้าไม่เจอ keyword)
  static const PieceUnitInfo _fallbackPieceRule = PieceUnitInfo(
    keywords: [],
    displayUnit: 'ชิ้น',
    gramsPerUnit: 50,
    unitSynonyms: ['piece', 'pieces', 'pc', 'pcs', 'slice', 'slices'],
  );

  // 🔸 หน่วยชิ้นที่อาจเจอ
  static final Set<String> _genericPieceUnits = {
    'ชิ้น',
    'pcs',
    'pc',
    'piece',
    'pieces',
    'unit',
    'ลูก',
    'ผล',
    'หัว',
    'กลีบ',
    'เม็ด',
    'ใบ',
    'ต้น',
    'ก้าน',
    'ดอก',
    'ตัว',
    'ฟอง',
    'slice',
    'slices',
    'egg',
    'eggs',
  };

  static String _normalize(String value) => value.trim().toLowerCase();

  static PieceUnitInfo? _ruleForName(String lowerName) {
    for (final rule in _pieceRules) {
      if (rule.matchesName(lowerName)) return rule;
    }
    return null;
  }

  static PieceUnitInfo? _ruleForUnit(String lowerUnit, String lowerName) {
    for (final rule in _pieceRules) {
      if (rule.matchesUnit(lowerUnit)) return rule;
    }
    final byName = _ruleForName(lowerName);
    final isGenericPiece =
        lowerUnit.isEmpty || _genericPieceUnits.contains(lowerUnit);
    if (!isGenericPiece) {
      // ไม่ใช่หน่วยแบบชิ้น ให้ปล่อยให้ logic ฝั่งกรัม/มล จัดการต่อ
      return null;
    }
    if (byName != null) {
      return byName;
    }
    return _fallbackPieceRule;
  }

  /// ✅ แปลงจำนวนชิ้นเป็นกรัม (ตาม rule)
  static double? gramsFromPiece(
    double amount,
    String unit,
    String ingredientName,
  ) {
    final lowerUnit = _normalize(unit);
    final lowerName = _normalize(ingredientName);
    final rule = _ruleForUnit(lowerUnit, lowerName);
    if (rule == null || rule.gramsPerUnit <= 0) return null;
    final grams = amount * rule.gramsPerUnit;
    return roundGrams(grams);
  }

  /// ✅ ตรวจว่าเป็นหน่วย "ชิ้น" หรือไม่
  static bool isPieceUnit(String unit) =>
      _genericPieceUnits.contains(_normalize(unit)) ||
      _pieceRules.any((rule) => rule.matchesUnit(_normalize(unit)));

  /// ✅ คืนค่ากรัมต่อชิ้น
  static double? gramsPerPiece(String ingredientName) {
    final rule = _ruleForName(_normalize(ingredientName));
    return rule?.gramsPerUnit;
  }

  /// ✅ หา rule ของวัตถุดิบจากชื่อหรือหน่วย
  static PieceUnitInfo? pieceRuleFor(String ingredientName, [String? unit]) {
    final lowerName = _normalize(ingredientName);
    if (unit != null) {
      final byUnit = _ruleForUnit(_normalize(unit), lowerName);
      if (byUnit != null) return byUnit;
    }
    return _ruleForName(lowerName);
  }

  /// ✅ แปลงกรัม → หน่วยที่เหมาะสม
  static SmartUnitResult gramsToPreferred(double grams, String ingredientName) {
    final rule = pieceRuleFor(ingredientName);
    if (rule != null) {
      final pieces = grams / rule.gramsPerUnit;
      if (pieces <= 50) {
        return SmartUnitResult(pieces, rule.displayUnit);
      }
    }
    if (grams >= MeasurementConstants.gramsPerKilogram) {
      return SmartUnitResult(
        grams / MeasurementConstants.gramsPerKilogram,
        'กิโลกรัม',
      );
    }
    return SmartUnitResult(roundGrams(grams), 'กรัม');
  }

  /// ✅ แปลงมิลลิลิตร → หน่วยเหมาะสม
  static SmartUnitResult millilitersToPreferred(
    double ml,
    String ingredientName,
  ) {
    if (ml >= 1000) {
      return SmartUnitResult(ml / 1000, 'ลิตร');
    } else if (ml >= 15) {
      final tbsp = ml / 15;
      if (tbsp <= 50) return SmartUnitResult(tbsp, 'ช้อนโต๊ะ');
    } else if (ml >= 5) {
      final tsp = ml / 5;
      if (tsp <= 50) return SmartUnitResult(tsp, 'ช้อนชา');
    }
    return SmartUnitResult(ml, 'มิลลิลิตร');
  }

  /// ✅ แปลงกรัม → ชิ้น (ถ้ามี rule)
  static double? convertGramsToPiece(
    double grams,
    String targetUnit,
    String ingredientName,
  ) {
    final lowerUnit = _normalize(targetUnit);
    final lowerName = _normalize(ingredientName);
    final rule = pieceRuleFor(lowerName, lowerUnit);
    if (rule == null || rule.gramsPerUnit <= 0) return null;
    if (isPieceUnit(lowerUnit)) {
      return grams / rule.gramsPerUnit;
    }
    return null;
  }

  /// ✅ ตรวจว่า unit ตรงกับ rule หรือไม่
  static bool unitMatchesRule(String unit, PieceUnitInfo rule) {
    final lowerUnit = _normalize(unit);
    return rule.matchesUnit(lowerUnit) ||
        rule.displayUnit.trim().toLowerCase() == lowerUnit;
  }

  /// ✅ ใช้ก่อนลด stock — ถ้าเป็นหน่วยชิ้น (หัว, ลูก, ฟอง) ให้แปลงเป็นกรัมอัตโนมัติ
  /// 🔥 Normalize หน่วยน้ำหนักให้เป็นกรัม และแปลงชิ้นเป็นกรัมอัตโนมัติ
  static double toGramsIfPiece(
    double amount,
    String unit,
    String ingredientName,
  ) {
    final lowerUnit = _normalize(unit);

    // ❌ หน่วยน้ำหนัก → แปลงเป็นกรัมเสมอ
    if (lowerUnit.contains('กิโล') ||
        lowerUnit == 'kg' ||
        lowerUnit == 'kgs' ||
        lowerUnit == 'kg.' ||
        lowerUnit == 'kilogram' ||
        lowerUnit == 'kilograms' ||
        lowerUnit == 'กก' ||
        lowerUnit == 'กก.') {
      return roundGrams(amount * MeasurementConstants.gramsPerKilogram);
    }
    if (lowerUnit.contains('กรัม') ||
        lowerUnit == 'g' ||
        lowerUnit == 'g.' ||
        lowerUnit == 'gram' ||
        lowerUnit == 'grams' ||
        lowerUnit == 'gm' ||
        lowerUnit == 'gms' ||
        lowerUnit == 'กรัม.') {
      return roundGrams(amount);
    }
    if (lowerUnit == 'mg' ||
        lowerUnit == 'mg.' ||
        lowerUnit == 'milligram' ||
        lowerUnit == 'milligrams' ||
        lowerUnit == 'มิลลิกรัม') {
      return roundGrams(amount / MeasurementConstants.milligramsPerGram);
    }

    // ✅ ถ้าเป็นหน่วยชิ้น → แปลงเป็นกรัม
    if (isPieceUnit(unit)) {
      final grams = gramsFromPiece(amount, unit, ingredientName);
      if (grams != null && grams > 0) return grams;
    }

    return amount;
  }

  /// ✅ ปัดค่ากรัมให้เป็นจำนวนเต็ม (ไม่มีทศนิยม)
  static double roundGrams(double grams) {
    if (!grams.isFinite) return grams;
    final rounded = grams.round();
    return rounded.toDouble();
  }
}

class SmartUnitResult {
  final double amount;
  final String unit;
  const SmartUnitResult(this.amount, this.unit);
}
