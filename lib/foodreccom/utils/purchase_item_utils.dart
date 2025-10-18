//lib/foodreccom/utils/purchase_item_utils.dart
import 'package:my_app/common/measurement_constants.dart';
import 'package:my_app/common/smart_unit_converter.dart';
import 'package:my_app/foodreccom/constants/nutrition_thresholds.dart';
import '../models/ingredient_model.dart';
import '../models/purchase_item.dart';
import '../models/recipe/recipe.dart';

class CanonicalQuantity {
  final double amount;
  final String unit; // 'gram' | 'milliliter' | 'piece'

  const CanonicalQuantity(this.amount, this.unit);

  CanonicalQuantity operator +(CanonicalQuantity other) {
    if (unit != other.unit) {
      throw ArgumentError(
        'Cannot add quantities with different units: $unit vs ${other.unit}',
      );
    }
    return CanonicalQuantity(amount + other.amount, unit);
  }

  CanonicalQuantity subtract(CanonicalQuantity other) {
    if (unit != other.unit) {
      throw ArgumentError(
        'Cannot subtract quantities with different units: $unit vs ${other.unit}',
      );
    }
    return CanonicalQuantity(amount - other.amount, unit);
  }
}

class _IngredientProfile {
  final List<String> keywords;
  final double? minGramPerServing;
  final double? minMlPerServing;
  final double? minPiecePerServing;
  final double? density; // g per milliliter
  final double? cupToGram;
  final double? cupToMilliliter;

  const _IngredientProfile({
    required this.keywords,
    this.minGramPerServing,
    this.minMlPerServing,
    this.minPiecePerServing,
    this.density,
    this.cupToGram,
    this.cupToMilliliter,
  });

  bool matches(String lowerName) => keywords.any(lowerName.contains);
}

const _defaultMinGramPerServing = 2.0;
const _defaultMinMlPerServing = 2.0;
const _defaultMinPiecePerServing = 1.0;

const List<_IngredientProfile> _ingredientProfiles = [
  _IngredientProfile(
    keywords: ['ข้าวเหนียว', 'sticky rice', 'glutinous rice'],
    minGramPerServing: 100,
    density: 0.8,
    cupToGram: 185,
  ),
  _IngredientProfile(
    keywords: [
      'ข้าวหอมมะลิ',
      'ข้าวสาร',
      'ข้าวเจ้า',
      'ข้าว',
      'jasmine rice',
      'white rice',
      'rice',
    ],
    minGramPerServing: 100,
    density: 0.75,
    cupToGram: 180,
  ),
  _IngredientProfile(
    keywords: [
      'หมูสับ',
      'หมูบด',
      'หมูชิ้น',
      'หมูสไลซ์',
      'หมูสามชั้น',
      'เนื้อหมู',
      'pork',
    ],
    minGramPerServing: 130,
  ),
  _IngredientProfile(
    keywords: ['เนื้อวัว', 'วัวบด', 'สเต็ก', 'beef', 'steak'],
    minGramPerServing: 140,
  ),
  _IngredientProfile(
    keywords: [
      'ไก่สับ',
      'ไก่บด',
      'อกไก่',
      'สะโพกไก่',
      'เนื้อไก่',
      'น่องไก่',
      'chicken',
    ],
    minGramPerServing: 120,
  ),
  _IngredientProfile(
    keywords: ['ปลา', 'fillet', 'fish'],
    minGramPerServing: 120,
  ),
  _IngredientProfile(
    keywords: ['กุ้ง', 'shrimp', 'prawn'],
    minGramPerServing: 90,
  ),
  _IngredientProfile(
    keywords: ['ปลาหมึก', 'หมึก', 'squid', 'octopus'],
    minGramPerServing: 90,
  ),
  _IngredientProfile(
    keywords: ['อาหารทะเล', 'seafood'],
    minGramPerServing: 100,
  ),
  _IngredientProfile(keywords: ['ไข่', 'egg', 'eggs'], minPiecePerServing: 1),
  _IngredientProfile(
    keywords: ['fish sauce', 'น้ำปลา'],
    minMlPerServing: 5,
    density: 1.2,
  ),
  _IngredientProfile(
    keywords: ['soy sauce', 'ซีอิ๊ว'],
    minMlPerServing: 5,
    density: 1.18,
  ),
  _IngredientProfile(
    keywords: ['oyster sauce', 'ซอสหอยนางรม'],
    minMlPerServing: 5,
    density: 1.25,
  ),
  _IngredientProfile(
    keywords: ['coconut milk', 'กะทิ'],
    minMlPerServing: 30,
    density: 1.02,
  ),
  _IngredientProfile(
    keywords: [
      'น้ำตาลทราย',
      'น้ำตาลขาว',
      'น้ำตาล',
      'sugar',
      'granulated sugar',
    ],
    minGramPerServing: 10,
    density: 0.85,
    cupToGram: 200,
  ),
  _IngredientProfile(
    keywords: ['น้ำตาลทรายแดง', 'brown sugar'],
    minGramPerServing: 10,
    density: 0.75,
    cupToGram: 195,
  ),
  _IngredientProfile(
    keywords: ['olive oil', 'น้ำมันมะกอก'],
    minMlPerServing: 5,
    density: 0.915,
  ),
  _IngredientProfile(
    keywords: ['vegetable oil', 'น้ำมันพืช', 'น้ำมัน'],
    minMlPerServing: 5,
    density: 0.92,
  ),
  _IngredientProfile(
    keywords: ['ถั่วลิสง', 'peanut', 'peanuts'],
    minGramPerServing: 30,
    density: 0.61,
    cupToGram: 146,
  ),
  _IngredientProfile(
    keywords: ['stock', 'broth', 'น้ำสต็อก', 'น้ำซุป', 'ซุป'],
    minMlPerServing: 50,
    density: 1.0,
  ),
  _IngredientProfile(
    keywords: ['milk', 'นม'],
    minMlPerServing: 30,
    density: 1.03,
  ),
  _IngredientProfile(
    keywords: ['cream', 'ครีม'],
    minMlPerServing: 20,
    density: 1.01,
  ),
  _IngredientProfile(
    keywords: ['water', 'น้ำเปล่า', 'น้ำสะอาด', 'น้ำ'],
    minMlPerServing: 10,
    density: 1.0,
    cupToMilliliter: MeasurementConstants.millilitersPerCup,
  ),
];

_IngredientProfile? _profileForName(String lowerName) {
  for (final profile in _ingredientProfiles) {
    if (profile.matches(lowerName)) return profile;
  }
  return null;
}

List<PurchaseItem> computePurchaseItems(
  RecipeModel recipe,
  List<IngredientModel> inventory, {
  int? servings,
  Map<String, double>? manualRequiredAmounts,
}) {
  final statuses = analyzeIngredientStatus(
    recipe,
    inventory,
    servings: servings,
    manualRequiredAmounts: manualRequiredAmounts,
  );

  final items = statuses.where((status) => status.missingAmount > 0.01).map((
    status,
  ) {
    final baseQty = _strictCeil(status.missingAmount).clamp(1, 999999);
    final adjustedQty = _adjustQuantityForFrequency(status, baseQty);
    return PurchaseItem(
      name: status.name,
      quantity: adjustedQty,
      unit: status.unit,
      category: guessCategory(status.name),
      requiredAmount: status.requiredAmount,
      availableAmount: status.availableAmount,
      canonicalUnit: status.canonicalUnit,
      consumptionFrequency: status.consumptionFrequency,
      frequencyReason: status.frequencyReason,
    );
  }).toList();

  for (final name in recipe.missingIngredients) {
    final normalized = normalizeName(name);
    final already = items.any((e) => normalizeName(e.name) == normalized);
    if (already) continue;

    final hasStock = inventory.any((inv) {
      if (_isExpired(inv)) return false;
      if (inv.quantity <= 0) return false;
      return _matches(name, inv.name);
    });
    if (hasStock) continue;

    items.add(
      PurchaseItem(
        name: name,
        quantity: 1,
        unit: displayUnitForCanonical('piece', name),
        category: guessCategory(name),
        requiredAmount: 1,
        availableAmount: 0,
        canonicalUnit: 'piece',
        consumptionFrequency: null,
        frequencyReason: null,
      ),
    );
  }

  return items;
}

// ปัดเศษขึ้น (ceil) แต่ถ้าเกือบเป็นจำนวนเต็มอยู่แล้วจะคงค่าเดิมไว้
int _strictCeil(double value) {
  if (!value.isFinite) return 0;
  final nearest = value.round();
  if ((value - nearest).abs() < 1e-3) return nearest;
  return value.ceil();
}

int _frequencySeverity(ConsumptionFrequency frequency) {
  switch (frequency) {
    case ConsumptionFrequency.daily:
      return 0;
    case ConsumptionFrequency.oncePerDay:
      return 1;
    case ConsumptionFrequency.weekly:
      return 2;
    case ConsumptionFrequency.occasional:
      return 3;
  }
}

int _adjustQuantityForFrequency(IngredientNeedStatus status, int baseQuantity) {
  final freq = status.consumptionFrequency;
  if (freq == null) return baseQuantity;
  switch (freq) {
    case ConsumptionFrequency.daily:
      return baseQuantity;
    case ConsumptionFrequency.oncePerDay:
      return baseQuantity;
    case ConsumptionFrequency.weekly:
      final adjusted = (baseQuantity * 0.75).ceil();
      final lower = adjusted < 1 ? 1 : adjusted;
      return lower > baseQuantity ? baseQuantity : lower;
    case ConsumptionFrequency.occasional:
      final adjusted = (baseQuantity * 0.5).ceil();
      final lower = adjusted < 1 ? 1 : adjusted;
      return lower > baseQuantity ? baseQuantity : lower;
  }
}

class IngredientNeedStatus {
  final String name;
  final double requiredAmount;
  final double availableAmount;
  final double missingAmount;
  final String unit;
  final String canonicalUnit;
  final double canonicalRequiredAmount;
  final double canonicalAvailableAmount;
  final bool hasAnyStock;
  final bool isOptional;
  final ConsumptionFrequency? consumptionFrequency;
  final String? frequencyReason;

  const IngredientNeedStatus({
    required this.name,
    required this.requiredAmount,
    required this.availableAmount,
    required this.missingAmount,
    required this.unit,
    required this.canonicalUnit,
    required this.canonicalRequiredAmount,
    required this.canonicalAvailableAmount,
    required this.hasAnyStock,
    required this.isOptional,
    this.consumptionFrequency,
    this.frequencyReason,
  });

  bool get isMissing => missingAmount > 0.01;

  double get completionRatio {
    if (requiredAmount <= 0) return 1.0;
    return (availableAmount / requiredAmount).clamp(0.0, 1.0);
  }
}

List<IngredientNeedStatus> analyzeIngredientStatus(
  RecipeModel recipe,
  List<IngredientModel> inventory, {
  int? servings,
  Map<String, double>? manualRequiredAmounts,
}) {
  final baseServings = recipe.servings == 0 ? (servings ?? 1) : recipe.servings;
  final resolvedBase = baseServings == 0 ? 1 : baseServings;
  final effectiveServings = (servings == null || servings <= 0)
      ? resolvedBase
      : servings;
  final multiplier = effectiveServings / resolvedBase;
  final targetServings = effectiveServings.toDouble();
  final statuses = <IngredientNeedStatus>[];
  final manualMap =
      (manualRequiredAmounts == null || manualRequiredAmounts.isEmpty)
      ? null
      : manualRequiredAmounts.map(
          (key, value) => MapEntry(key.trim().toLowerCase(), value),
        );

  for (final ri in recipe.ingredients) {
    final needName = ri.name.trim();
    if (needName.isEmpty) continue;

    final baseAmt = ri.numericAmount;
    final scaledAmt = baseAmt * multiplier;
    final manualRaw = manualMap?[needName.toLowerCase()];
    double? manualAmount;
    if (manualRaw != null && manualRaw.isFinite) {
      manualAmount = manualRaw < 0 ? 0 : manualRaw;
    }
    final targetAmount = manualAmount ?? scaledAmt;
    final targetNeed = toCanonicalQuantity(targetAmount, ri.unit, needName);
    final canonicalUnit = targetNeed.unit;
    final profile = _profileForName(needName.toLowerCase());

    ConsumptionFrequency? matchedFrequency;
    String? matchedReason;

    double haveCanonical = 0;
    bool hasAnyStock = false;
    for (final inv in inventory) {
      if (_isExpired(inv)) continue;
      if (_matches(needName, inv.name)) {
        if (inv.quantity > 0) hasAnyStock = true;
        final hv = toCanonicalQuantity(
          inv.quantity.toDouble(),
          inv.unit,
          inv.name,
        );
        final reconciled = _coerceToTargetUnit(
          targetUnit: canonicalUnit,
          sourceQuantity: hv,
          ingredientName: needName,
        );
        if (reconciled != null) {
          haveCanonical += reconciled;
        }
        final freq = inv.consumptionFrequency;
        if (freq != null) {
          if (matchedFrequency == null ||
              _frequencySeverity(freq) >
                  _frequencySeverity(matchedFrequency!)) {
            matchedFrequency = freq;
            matchedReason = inv.consumptionReason;
          } else if (_frequencySeverity(freq) ==
                  _frequencySeverity(matchedFrequency!) &&
              (matchedReason == null || matchedReason!.trim().isEmpty) &&
              (inv.consumptionReason?.trim().isNotEmpty ?? false)) {
            matchedReason = inv.consumptionReason;
          }
        }
      }
    }

    final minReq = manualAmount != null
        ? null
        : _minimumCanonicalRequirement(
            profile: profile,
            canonicalUnit: canonicalUnit,
            servings: targetServings,
          );
    final canonicalRequired = (minReq != null && minReq > targetNeed.amount)
        ? minReq
        : targetNeed.amount;
    final preferred = _convertToPreferredQuantity(
      canonicalUnit: canonicalUnit,
      canonicalAmount: canonicalRequired,
      ingredientName: needName,
    );
    final availableDisplay = _convertCanonicalToUnit(
      canonicalUnit: canonicalUnit,
      canonicalAmount: haveCanonical,
      targetUnit: preferred.unit,
      ingredientName: needName,
    );
    final missingDisplay = preferred.amount - availableDisplay;

    statuses.add(
      IngredientNeedStatus(
        name: needName,
        requiredAmount: preferred.amount,
        availableAmount: availableDisplay,
        missingAmount: missingDisplay > 0 ? missingDisplay : 0.0,
        unit: preferred.unit,
        canonicalUnit: canonicalUnit,
        canonicalRequiredAmount: canonicalRequired,
        canonicalAvailableAmount: haveCanonical,
        hasAnyStock: hasAnyStock,
        isOptional: ri.isOptional,
        consumptionFrequency: matchedFrequency,
        frequencyReason: matchedReason,
      ),
    );
  }

  return statuses;
}

double? _minimumCanonicalRequirement({
  required _IngredientProfile? profile,
  required String canonicalUnit,
  required double servings,
}) {
  if (servings <= 0) return null;
  switch (canonicalUnit) {
    case 'gram':
      if (profile?.minGramPerServing != null)
        return profile!.minGramPerServing! * servings;
      return _defaultMinGramPerServing * servings;
    case 'milliliter':
      if (profile?.minMlPerServing != null)
        return profile!.minMlPerServing! * servings;
      return _defaultMinMlPerServing * servings;
    case 'piece':
      if (profile?.minPiecePerServing != null)
        return profile!.minPiecePerServing! * servings;
      return _defaultMinPiecePerServing * servings;
  }
  return null;
}

CanonicalQuantity toCanonicalQuantity(
  double amount,
  String unit,
  String ingredientName,
) {
  final normalizedUnit = unit.trim().toLowerCase();
  final normalizedName = normalizeName(ingredientName);
  final profile = _profileForName(normalizedName);

  final pieceAsGram = SmartUnitConverter.gramsFromPiece(
    amount,
    normalizedUnit,
    ingredientName,
  );
  if (pieceAsGram != null) {
    return CanonicalQuantity(pieceAsGram, 'gram');
  }
  if (SmartUnitConverter.isPieceUnit(normalizedUnit)) {
    final ruleForUnit = SmartUnitConverter.pieceRuleFor(ingredientName, unit);
    final fallbackRule = SmartUnitConverter.pieceRuleFor(
      ingredientName,
      'ชิ้น',
    );
    final ruleByName = SmartUnitConverter.pieceRuleFor(ingredientName);
    final gramsPerPiece =
        ruleForUnit?.gramsPerUnit ??
        ruleByName?.gramsPerUnit ??
        fallbackRule?.gramsPerUnit ??
        SmartUnitConverter.gramsPerPiece(normalizedName);
    if (gramsPerPiece != null && gramsPerPiece > 0) {
      return CanonicalQuantity(amount * gramsPerPiece, 'gram');
    }
    return CanonicalQuantity(amount, 'piece');
  }

  if (_matchesAny(normalizedUnit, const [
    'kg',
    'kgs',
    'kilogram',
    'kilograms',
    'กิโลกรัม',
    'กก',
    'กก.',
    'กิโล',
    'คิโลกรัม',
  ])) {
    return CanonicalQuantity(
      amount * MeasurementConstants.gramsPerKilogram,
      'gram',
    );
  }
  if (_matchesAny(normalizedUnit, const [
    'g',
    'g.',
    'gram',
    'grams',
    'gm',
    'gms',
    'กรัม',
    'กรัม.',
    'gms.',
  ])) {
    return CanonicalQuantity(amount, 'gram');
  }
  if (_matchesAny(normalizedUnit, const [
    'oz',
    'ounce',
    'ounces',
    'ออนซ์',
    'ออนซ',
  ])) {
    return CanonicalQuantity(
      amount * MeasurementConstants.gramsPerOunce,
      'gram',
    );
  }
  if (_matchesAny(normalizedUnit, const [
    'lb',
    'lbs',
    'pound',
    'pounds',
    'ปอนด์',
  ])) {
    return CanonicalQuantity(
      amount * MeasurementConstants.gramsPerPound,
      'gram',
    );
  }
  if (_matchesAny(normalizedUnit, const [
    'l',
    'liter',
    'litre',
    'liters',
    'ลิตร',
    'ลิตร.',
    'lt',
  ])) {
    return CanonicalQuantity(
      amount * MeasurementConstants.millilitersPerLiter,
      'milliliter',
    );
  }
  if (_matchesAny(normalizedUnit, const [
    'ml',
    'ml.',
    'milliliter',
    'milliliters',
    'มิลลิลิตร',
    'มล',
    'มล.',
    'cc',
    'cm3',
  ])) {
    return CanonicalQuantity(amount, 'milliliter');
  }
  if (_matchesAny(normalizedUnit, const [
    'tablespoon',
    'tablespoons',
    'tbsp',
    'tbsp.',
    'ช้อนโต๊ะ',
    'ชต',
    'ช.ต.',
    'ช้อนแกง',
  ])) {
    return CanonicalQuantity(
      amount * MeasurementConstants.millilitersPerTablespoon,
      'milliliter',
    );
  }
  if (_matchesAny(normalizedUnit, const [
    'teaspoon',
    'teaspoons',
    'tsp',
    'tsp.',
    'ช้อนชา',
    'ชช',
    'ช.ช.',
  ])) {
    return CanonicalQuantity(
      amount * MeasurementConstants.millilitersPerTeaspoon,
      'milliliter',
    );
  }
  if (_matchesAny(normalizedUnit, const [
    'cup',
    'cups',
    'ถ้วย',
    'แก้ว',
    'ถ้วยตวง',
  ])) {
    if (profile?.cupToGram != null) {
      return CanonicalQuantity(amount * profile!.cupToGram!, 'gram');
    }
    if (profile?.cupToMilliliter != null) {
      return CanonicalQuantity(
        amount * profile!.cupToMilliliter!,
        'milliliter',
      );
    }
    if (profile?.density != null &&
        !(profile?.minGramPerServing == null &&
            profile?.minMlPerServing != null)) {
      return CanonicalQuantity(
        amount *
            MeasurementConstants.millilitersPerCup *
            (profile?.density ?? 1.0),
        'gram',
      );
    }
    return CanonicalQuantity(
      amount * MeasurementConstants.millilitersPerCup,
      'milliliter',
    );
  }
  if (_matchesAny(normalizedUnit, const ['ช้อนกาแฟ'])) {
    return CanonicalQuantity(
      amount * MeasurementConstants.millilitersPerTeaspoon,
      'milliliter',
    );
  }
  if (_matchesAny(normalizedUnit, const ['ช้อน', 'ช้อนโตะ', 'ช้อนกาแฟ'])) {
    return CanonicalQuantity(
      amount * MeasurementConstants.millilitersPerTeaspoon,
      'milliliter',
    );
  }

  if (profile?.density != null &&
      (profile?.minMlPerServing != null || _isLikelyLiquid(normalizedName))) {
    return CanonicalQuantity(amount * profile!.density!, 'gram');
  }

  if (normalizedUnit.isEmpty) {
    final gramsPerPiece = SmartUnitConverter.gramsPerPiece(normalizedName);
    if (gramsPerPiece != null) {
      return CanonicalQuantity(amount * gramsPerPiece, 'gram');
    }
  }

  return CanonicalQuantity(amount, 'gram');
}

class _ConvertedQuantity {
  final double amount;
  final String unit;
  const _ConvertedQuantity(this.amount, this.unit);
}

double? _coerceToTargetUnit({
  required String targetUnit,
  required CanonicalQuantity sourceQuantity,
  required String ingredientName,
}) {
  if (targetUnit == sourceQuantity.unit) return sourceQuantity.amount;

  final lower = normalizeName(ingredientName);
  final liquid = _isLikelyLiquid(lower);
  final density = _densityForIngredient(lower) ?? (liquid ? 1.0 : null);

  if (density != null) {
    if (targetUnit == 'milliliter' && sourceQuantity.unit == 'gram') {
      // ml = g / (g/ml)
      return sourceQuantity.amount / density;
    }
    if (targetUnit == 'gram' && sourceQuantity.unit == 'milliliter') {
      // g = ml * (g/ml)
      return sourceQuantity.amount * density;
    }
  }

  return null;
}

_ConvertedQuantity _convertToPreferredQuantity({
  required String canonicalUnit,
  required double canonicalAmount,
  required String ingredientName,
}) {
  switch (canonicalUnit) {
    case 'gram':
      final lowerName = normalizeName(ingredientName);
      final density = _densityForIngredient(lowerName);
      if (density != null && _isLikelyLiquid(lowerName)) {
        final milliliters = canonicalAmount / density;
        final smartLiquid = SmartUnitConverter.millilitersToPreferred(
          milliliters,
          ingredientName,
        );
        return _ConvertedQuantity(smartLiquid.amount, smartLiquid.unit);
      }
      final smart = SmartUnitConverter.gramsToPreferred(
        canonicalAmount,
        ingredientName,
      );
      return _ConvertedQuantity(smart.amount, smart.unit);
    case 'milliliter':
      final smart = SmartUnitConverter.millilitersToPreferred(
        canonicalAmount,
        ingredientName,
      );
      return _ConvertedQuantity(smart.amount, smart.unit);
    case 'piece':
    default:
      final rule = SmartUnitConverter.pieceRuleFor(ingredientName);
      if (rule != null) {
        return _ConvertedQuantity(canonicalAmount, rule.displayUnit);
      }
      return _ConvertedQuantity(canonicalAmount, 'ชิ้น');
  }
}

double _convertCanonicalToUnit({
  required String canonicalUnit,
  required double canonicalAmount,
  required String targetUnit,
  required String ingredientName,
}) {
  switch (canonicalUnit) {
    case 'gram':
      final lowerTarget = targetUnit.trim().toLowerCase();
      const kilogramUnits = {
        'กิโลกรัม',
        'kg',
        'kgs',
        'kilogram',
        'kilograms',
        'กก',
        'กก.',
      };
      const gramUnits = {
        'กรัม',
        'g',
        'g.',
        'gram',
        'grams',
        'gm',
        'gms',
        'กรัม.',
      };
      const tablespoonUnits = {
        'ช้อนโต๊ะ',
        'tablespoon',
        'tablespoons',
        'tbsp',
        'tbsp.',
      };
      const teaspoonUnits = {'ช้อนชา', 'teaspoon', 'teaspoons', 'tsp', 'tsp.'};
      const milliliterUnits = {
        'มิลลิลิตร',
        'ml',
        'ml.',
        'milliliter',
        'milliliters',
        'millilitre',
        'millilitres',
        'มล',
        'มล.',
        'cc',
        'cm3',
      };
      const literUnits = {
        'ลิตร',
        'liter',
        'litre',
        'liters',
        'litres',
        'l',
        'lt',
        'ltr',
      };
      final lowerName = normalizeName(ingredientName);
      final density = _densityForIngredient(lowerName);
      final pieceValue = SmartUnitConverter.convertGramsToPiece(
        canonicalAmount,
        targetUnit,
        ingredientName,
      );
      if (pieceValue != null) {
        return pieceValue;
      }
      if (kilogramUnits.contains(lowerTarget)) {
        return canonicalAmount / MeasurementConstants.gramsPerKilogram;
      }
      if (gramUnits.contains(lowerTarget) || lowerTarget.isEmpty) {
        return canonicalAmount;
      }
      if (density != null) {
        final milliliters = canonicalAmount / density;
        if (literUnits.contains(lowerTarget)) {
          return milliliters / MeasurementConstants.millilitersPerLiter;
        }
        if (milliliterUnits.contains(lowerTarget)) {
          return milliliters;
        }
        if (tablespoonUnits.contains(lowerTarget)) {
          return milliliters / MeasurementConstants.millilitersPerTablespoon;
        }
        if (teaspoonUnits.contains(lowerTarget)) {
          return milliliters / MeasurementConstants.millilitersPerTeaspoon;
        }
      }
      return canonicalAmount;
    case 'milliliter':
      final lowerTarget = targetUnit.trim().toLowerCase();
      const literUnits = {
        'ลิตร',
        'liter',
        'litre',
        'liters',
        'litres',
        'l',
        'lt',
        'ltr',
      };
      const milliliterUnits = {
        'มิลลิลิตร',
        'ml',
        'ml.',
        'milliliter',
        'milliliters',
        'millilitre',
        'millilitres',
        'มล',
        'มล.',
        'cc',
        'cm3',
      };
      if (literUnits.contains(lowerTarget)) {
        return canonicalAmount / MeasurementConstants.millilitersPerLiter;
      }
      if (lowerTarget == 'ช้อนโต๊ะ' ||
          lowerTarget == 'tablespoon' ||
          lowerTarget == 'tbsp' ||
          lowerTarget == 'tbsp.') {
        return canonicalAmount / MeasurementConstants.millilitersPerTablespoon;
      }
      if (lowerTarget == 'ช้อนชา' ||
          lowerTarget == 'teaspoon' ||
          lowerTarget == 'tsp' ||
          lowerTarget == 'tsp.') {
        return canonicalAmount / MeasurementConstants.millilitersPerTeaspoon;
      }
      if (milliliterUnits.contains(lowerTarget) || lowerTarget.isEmpty) {
        return canonicalAmount;
      }
      return canonicalAmount;
    case 'piece':
    default:
      final lowerTarget = targetUnit.trim().toLowerCase();
      final ruleForTarget = SmartUnitConverter.pieceRuleFor(
        ingredientName,
        targetUnit,
      );
      final ruleByName = SmartUnitConverter.pieceRuleFor(ingredientName);
      final fallbackRule = SmartUnitConverter.pieceRuleFor(
        ingredientName,
        'ชิ้น',
      );
      final rule = ruleForTarget ?? ruleByName ?? fallbackRule;
      if (rule != null &&
          SmartUnitConverter.unitMatchesRule(targetUnit, rule)) {
        return canonicalAmount;
      }
      if (rule != null) {
        const kilogramUnits = {
          'กิโลกรัม',
          'kg',
          'kgs',
          'kilogram',
          'kilograms',
          'กก',
          'กก.',
        };
        const gramUnits = {
          'กรัม',
          'g',
          'g.',
          'gram',
          'grams',
          'gm',
          'gms',
          'กรัม.',
        };
        if (kilogramUnits.contains(lowerTarget)) {
          return (canonicalAmount * rule.gramsPerUnit) /
              MeasurementConstants.gramsPerKilogram;
        }
        if (gramUnits.contains(lowerTarget) || lowerTarget.isEmpty) {
          return canonicalAmount * rule.gramsPerUnit;
        }
      }
      if (lowerTarget == 'ชิ้น') {
        return canonicalAmount;
      }
      return canonicalAmount;
  }
}

double convertCanonicalToUnit({
  required String canonicalUnit,
  required double canonicalAmount,
  required String targetUnit,
  required String ingredientName,
}) {
  return _convertCanonicalToUnit(
    canonicalUnit: canonicalUnit,
    canonicalAmount: canonicalAmount,
    targetUnit: targetUnit,
    ingredientName: ingredientName,
  );
}

bool _isLikelyLiquid(String lowerName) {
  const keywords = [
    'น้ำ',
    'น้ํา',
    'ซอส',
    'นม',
    'ครีม',
    'ซุป',
    'stock',
    'broth',
    'sauce',
    'oil',
    'vinegar',
    'juice',
    'milk',
    'cream',
    'syrup',
    'กะทิ',
    'ไข่ขาวเหลว',
    'ไข่แดงเหลว',
    'coconut milk',
    'fish sauce',
    'soy sauce',
    'น้ำปลา',
    'น้ำมัน',
    'น้ำส้ม',
    'น้ำตาลทรายแดงเหลว',
  ];
  for (final keyword in keywords) {
    if (lowerName.contains(keyword)) return true;
  }
  return false;
}

// Return density in g/ml for common liquids. If null → unknown
double? _densityForIngredient(String lowerName) {
  final profile = _profileForName(lowerName);
  if (profile?.density != null) return profile!.density;
  // Order matters: first match wins
  final entries = <List<dynamic>>[
    // pairs: [keyword, density]
    ['น้ำมันมะกอก', 0.915],
    ['olive oil', 0.915],
    ['น้ำมันพืช', 0.92],
    ['vegetable oil', 0.92],
    ['น้ำมัน', 0.92],
    ['fish sauce', 1.20],
    ['น้ำปลา', 1.20],
    ['soy sauce', 1.18],
    ['ซีอิ๊ว', 1.18],
    ['oyster sauce', 1.25],
    ['ซอสหอยนางรม', 1.25],
    ['vinegar', 1.01],
    ['น้ำส้มสายชู', 1.01],
    ['coconut milk', 1.02],
    ['กะทิ', 1.02],
    ['milk', 1.03],
    ['นม', 1.03],
    ['cream', 1.01],
    ['ครีม', 1.01],
    ['น้ำตาลทรายแดงเหลว', 1.30],
    ['syrup', 1.30],
    ['น้ำเชื่อม', 1.30],
    ['water', 1.00],
    ['น้ำเปล่า', 1.00],
    ['น้ำ', 1.00],
  ];
  for (final e in entries) {
    final kw = e[0] as String;
    if (lowerName.contains(kw)) return (e[1] as num).toDouble();
  }
  return null;
}

bool _matchesAny(String value, List<String> candidates) {
  for (final c in candidates) {
    if (value == c) return true;
  }
  return false;
}

String displayUnitForCanonical(String canonicalUnit, String ingredientName) {
  final normalizedName = normalizeName(ingredientName);
  if (normalizedName.contains('ไข่') || normalizedName.contains('egg')) {
    return 'ฟอง';
  }

  switch (canonicalUnit) {
    case 'gram':
      return 'กรัม';
    case 'milliliter':
      return 'มิลลิลิตร';
    default:
      return 'กรัม';
  }
}

bool _isPieceLikeUnit(String unit, String ingredientName) {
  final normalizedUnit = unit.trim().toLowerCase();
  final normalizedName = ingredientName.trim();
  if (normalizedUnit.isEmpty) {
    return SmartUnitConverter.pieceRuleFor(normalizedName) != null;
  }
  if (SmartUnitConverter.isPieceUnit(normalizedUnit)) return true;
  const pieceUnits = {
    'ชิ้น',
    'หัว',
    'ลูก',
    'ฟอง',
    'ต้น',
    'กลีบ',
    'เม็ด',
    'ก้อน',
    'กำ',
    'ดอก',
    'ใบ',
    'ฝัก',
    'ขา',
    'ขวด',
    'แพ็ค',
    'แพค',
    'แพ็ก',
    'pack',
    'package',
    'packet',
    'bag',
    'bundle',
    'bunch',
    'stick',
    'sticks',
    'piece',
    'pieces',
    'pc',
    'pcs',
  };
  if (pieceUnits.contains(normalizedUnit)) return true;
  return SmartUnitConverter.pieceRuleFor(normalizedName, normalizedUnit) !=
      null;
}

String formatQuantityNumber(
  num value, {
  String unit = '',
  String ingredientName = '',
}) {
  if (!value.isFinite) return '0';
  final amount = value.toDouble();
  if (amount == 0) return '0';
  if (_isPieceLikeUnit(unit, ingredientName)) {
    if (amount <= 0) return '0';
    var ceiled = amount.ceil();
    if (ceiled <= 0 && amount > 0) {
      ceiled = 1;
    }
    return ceiled.toString();
  }
  if ((amount - amount.roundToDouble()).abs() < 1e-3) {
    return amount.round().toString();
  }

  final absValue = amount.abs();
  if (absValue >= 1) {
    final ceiled = amount.isNegative ? amount.floor() : amount.ceil();
    return ceiled.toInt().toString();
  }

  final factor = 10.0; // one decimal place for sub-unit measurements
  var scaled = (absValue * factor).ceil();
  if (scaled == 0 && amount > 0) {
    scaled = 1;
  }
  final rounded = scaled / factor;
  final signed = amount.isNegative ? -rounded : rounded;
  return _stripTrailingZeros(signed.toStringAsFixed(1));
}

String _stripTrailingZeros(String input) {
  return input.replaceFirst(RegExp(r'\.?0+$'), '');
}

String guessCategory(String ingredientName) {
  final name = normalizeName(ingredientName);
  const meat = [
    'ไก่',
    'หมู',
    'เนื้อ',
    'วัว',
    'ปลา',
    'กุ้ง',
    'หมึก',
    'เป็ด',
    'แฮม',
    'เบคอน',
    'pork',
    'beef',
    'chicken',
    'fish',
    'shrimp',
    'squid',
  ];
  const egg = ['ไข่', 'egg'];
  const veg = [
    'ผัก',
    'หอม',
    'หัวหอม',
    'ต้นหอม',
    'กระเทียม',
    'พริก',
    'มะเขือเทศ',
    'คะน้า',
    'กะหล่ำ',
    'แครอท',
    'แตง',
    'เห็ด',
    'ขิง',
    'ข่า',
    'ตะไคร้',
    'ใบมะกรูด',
    'onion',
    'garlic',
    'chili',
    'tomato',
    'cabbage',
    'carrot',
    'mushroom',
    'ginger',
    'lemongrass',
    'lime leaf',
  ];
  const fruit = [
    'ผลไม้',
    'กล้วย',
    'ส้ม',
    'แอปเปิ้ล',
    'สตรอ',
    'มะม่วง',
    'สับปะรด',
    'องุ่น',
    'banana',
    'orange',
    'apple',
    'strawberry',
    'mango',
    'pineapple',
    'grape',
    'lemon',
    'lime',
  ];
  const dairy = [
    'นม',
    'ชีส',
    'โยเกิร์ต',
    'ครีม',
    'เนย',
    'milk',
    'cheese',
    'yogurt',
    'butter',
    'cream',
  ];
  const rice = ['ข้าว', 'ข้าวสาร', 'rice', 'ข้าวหอมมะลิ'];
  const spice = [
    'เครื่องเทศ',
    'ยี่หร่า',
    'อบเชย',
    'ผงกะหรี่',
    'ซินนามอน',
    'cumin',
    'curry powder',
    'cinnamon',
    'peppercorn',
  ];
  const condiment = [
    'ซอส',
    'น้ำปลา',
    'ซีอิ๊ว',
    'เกลือ',
    'น้ำตาล',
    'ผงชูรส',
    'เต้าเจี้ยว',
    'ซอสมะเขือเทศ',
    'มายองเนส',
    'ซอสหอยนางรม',
    'sauce',
    'fish sauce',
    'soy',
    'salt',
    'sugar',
    'ketchup',
    'mayonnaise',
    'oyster sauce',
  ];
  const flour = [
    'แป้ง',
    'ขนมปัง',
    'เส้น',
    'พาสต้า',
    'noodle',
    'pasta',
    'flour',
    'bread',
  ];
  const oil = ['น้ำมัน', 'olive oil', 'vegetable oil', 'oil'];
  const drink = [
    'น้ำอัดลม',
    'โซดา',
    'กาแฟ',
    'ชา',
    'juice',
    'soda',
    'coffee',
    'tea',
  ];
  const frozen = ['แช่แข็ง', 'frozen'];

  bool containsAny(List<String> keywords) =>
      keywords.any((keyword) => name.contains(keyword));

  if (containsAny(meat)) return 'เนื้อสัตว์';
  if (containsAny(egg)) return 'ไข่';
  if (containsAny(dairy)) return 'ผลิตภัณฑ์จากนม';
  if (containsAny(rice)) return 'ข้าว';
  if (containsAny(spice)) return 'เครื่องเทศ';
  if (containsAny(condiment)) return 'เครื่องปรุง';
  if (containsAny(flour)) return 'แป้ง';
  if (containsAny(oil)) return 'น้ำมัน';
  if (containsAny(drink)) return 'เครื่องดื่ม';
  if (containsAny(frozen)) return 'ของแช่แข็ง';
  if (containsAny(veg)) return 'ผัก';
  if (containsAny(fruit)) return 'ผลไม้';
  return 'ของแห้ง';
}

String normalizeName(String value) => value.trim().toLowerCase();

bool _matches(String need, String have) {
  final n = _normalizeForMatch(need);
  final h = _normalizeForMatch(have);
  return h.contains(n) || n.contains(h);
}

bool _isExpired(IngredientModel ingredient) {
  try {
    return ingredient.isExpired;
  } catch (_) {
    if (ingredient.expiryDate == null) return false;
    final today = DateTime.now();
    return ingredient.expiryDate!.isBefore(
      DateTime(today.year, today.month, today.day),
    );
  }
}

String _normalizeForMatch(String value) {
  var normalized = normalizeName(value)
      .replaceAll('-', ' ')
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\(.*?\)'), ' ')
      .replaceAll(RegExp(r'\[.*?\]'), ' ')
      .replaceAll(RegExp(r'【.*?】'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  const replacements = {
    'ไข่ดาว': 'ไข่',
    'ไข่ต้ม': 'ไข่',
    'ไข่เจียว': 'ไข่',
    'ไข่คน': 'ไข่',
    'ไข่ลวก': 'ไข่',
    'fried egg': 'egg',
    'boiled egg': 'egg',
    'scrambled egg': 'egg',
    'sunny side up egg': 'egg',
    'ไข่ไก่': 'ไข่',
    'ไข่แดง': 'ไข่',
    'ไข่ขาว': 'ไข่',
    'egg yolk': 'egg',
    'egg white': 'egg',
    'ฟองไข่': 'ไข่',
    'ไข่ไก่สด': 'ไข่',
    'ไข่ไก่อนามัย': 'ไข่',
    'ข้าวหอมมะลิ': 'ข้าว',
    'ข้าวสารหอมมะลิ': 'ข้าว',
    'ข้าวสาร': 'ข้าว',
    'ข้าวเจ้าหอมมะลิ': 'ข้าว',
    'ข้าวสารเจ้า': 'ข้าว',
    'ข้าวสารเหนียว': 'ข้าวเหนียว',
    'ข้าวเหนียว': 'ข้าวเหนียว',
    'ข้าวเหนียวมูล': 'ข้าวเหนียว',
    'rice grain': 'rice',
    'jasmine rice': 'rice',
    'sticky rice': 'rice',
    'glutinous rice': 'rice',
    'หมูบด': 'หมู',
    'หมูสับ': 'หมู',
    'หมูสไลซ์': 'หมู',
    'หมูสามชั้น': 'หมู',
    'หมูชิ้น': 'หมู',
    'เนื้อหมู': 'หมู',
    'หมูติดมัน': 'หมู',
    'หมูหั่นเต๋า': 'หมู',
    'หมูหั่นบาง': 'หมู',
    'หมูยอ': 'หมู',
    'เนื้อวัว': 'วัว',
    'เนื้อวัวสไลซ์': 'วัว',
    'เนื้อวัวหั่นเต๋า': 'วัว',
    'วัวบด': 'วัว',
    'ไก่สับ': 'ไก่',
    'อกไก่': 'ไก่',
    'สะโพกไก่': 'ไก่',
    'เนื้อไก่': 'ไก่',
    'น่องไก่': 'ไก่',
    'ปีกไก่': 'ไก่',
    'ปลาหมึกกล้วย': 'ปลาหมึก',
    'ปลาหมึกสด': 'ปลาหมึก',
    'หมึกสด': 'ปลาหมึก',
    'กะเพรา': 'โหระพา',
    'ใบกะเพรา': 'โหระพา',
    'holy basil': 'basil',
    'thai basil': 'basil',
    'โหระพาไทย': 'โหระพา',
    'โหระพาสด': 'โหระพา',
    'ใบโหระพา': 'โหระพา',
    'น้ำปลาแท้': 'น้ำปลา',
    'น้ำปลาตรา': 'น้ำปลา',
    'fish sauce': 'น้ำปลา',
    'น้ำตาลทราย': 'น้ำตาล',
    'น้ำตาลทรายแดง': 'น้ำตาลแดง',
    'น้ำตาลปี๊บ': 'น้ำตาล',
    'น้ำตาลมะพร้าว': 'น้ำตาล',
    'น้ำตาลก้อน': 'น้ำตาล',
    'น้ำตาลทรายขาว': 'น้ำตาล',
    'น้ำมันพืช': 'น้ำมัน',
    'น้ำมันถั่วเหลือง': 'น้ำมัน',
    'น้ำมันปาล์ม': 'น้ำมัน',
    'น้ำมันรำข้าว': 'น้ำมัน',
    'น้ำมันงา': 'น้ำมัน',
    'น้ำมันมะกอก': 'น้ำมัน',
    'หอมใหญ่': 'หัวหอมใหญ่',
    'หัวหอม': 'หัวหอมใหญ่',
    'หอมใหญ่ซอย': 'หัวหอมใหญ่',
    'หอมหัวใหญ่': 'หัวหอมใหญ่',
    'หอมแดง': 'หัวหอมแดง',
    'shallot': 'หัวหอมแดง',
    'ต้นหอม': 'ต้นหอม',
    'ต้นหอมซอย': 'ต้นหอม',
    'ผักชีฝรั่ง': 'ผักชี',
    'ผักชีไทย': 'ผักชี',
    'cilantro': 'ผักชี',
    'lemongrass': 'ตะไคร้',
    'galangal': 'ข่า',
    'kaffir lime leaf': 'ใบมะกรูด',
    'lime leaf': 'ใบมะกรูด',
    'pandan leaf': 'ใบเตย',
    'ใบเตยหอม': 'ใบเตย',
    'coconut milk': 'กะทิ',
    'coconut cream': 'กะทิ',
    'กะทิกล่อง': 'กะทิ',
    'กะทิสด': 'กะทิ',
    'นมสด': 'นม',
    'นมข้นจืด': 'นม',
    'evaporated milk': 'นม',
    'condensed milk': 'นมข้นหวาน',
    'นมข้นหวาน': 'นมข้นหวาน',
    'soy sauce': 'ซีอิ๊ว',
    'ซีอิ๊วขาว': 'ซีอิ๊ว',
    'ซีอิ๊วดำ': 'ซีอิ๊ว',
    'oyster sauce': 'ซอสหอยนางรม',
    'ซอสปรุงรส': 'ซอส',
    'ซอสเห็ดหอม': 'ซอส',
    'mushroom sauce': 'ซอส',
    'fish': 'ปลา',
    'shrimp': 'กุ้ง',
    'prawn': 'กุ้ง',
    'squid': 'ปลาหมึก',
    'octopus': 'ปลาหมึก',
    'beef': 'วัว',
    'pork': 'หมู',
    'chicken': 'ไก่',
    'duck': 'เป็ด',
    'basil': 'โหระพา',
    'thai chilli': 'พริก',
    'chili pepper': 'พริก',
    'bird eye chili': 'พริก',
    'kaffir lime leaves': 'ใบมะกรูด',
    'ginger': 'ขิง',
    'garlic clove': 'กระเทียม',
    'garlic': 'กระเทียม',
    'shallots': 'หัวหอมแดง',
    'onion': 'หัวหอมใหญ่',
  };

  for (final entry in replacements.entries) {
    if (normalized.contains(entry.key)) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
  }

  return normalized.replaceAll(' ', '');
}
