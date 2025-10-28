// lib/foodreccom/services/cooking_service.dart
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app/common/measurement_constants.dart';
import 'package:my_app/common/smart_unit_converter.dart' as PieceUnitConverter;
import 'package:my_app/rawmaterial/utils/unit_converter.dart'
    as StockConverter; // 📦 ใช้สำหรับจัดการสต็อกโดยเฉพาะ
import 'package:my_app/foodreccom/models/recipe/recipe_ingredient.dart'; // ตรวจสอบ Path ให้ถูกต้อง

import '../models/cooking_history_model.dart';
import '../models/recipe/recipe_model.dart';
import '../models/recipe/nutrition_info.dart';
import '../models/recipe/used_ingredient.dart';
import '../models/recipe/cooking_step.dart';
import '../utils/purchase_item_utils.dart' as qty;
// 🚀 Import ตัวแปลงหน่วย (ซึ่งตอนนี้เป็น "ไฮบริด" แล้ว)
import '../utils/smart_unit_converter.dart';
import '../utils/ingredient_translator.dart';

const Map<String, List<String>> _canonicalNameSeeds = {
  'pork': [
    'หมู',
    'หมูบด',
    'หมูสับ',
    'หมูชิ้น',
    'หมูสไลซ์',
    'เนื้อหมู',
    'เนื้อหมูบด',
    'หมูสามชั้น',
    'หมูสันนอก',
    'pork',
    'pork meat',
    'ground pork',
    'minced pork',
    'pork mince',
    'pork belly',
    'pork loin',
  ],
  'soy sauce': ['ซีอิ๊วขาว', 'ซีอิ๊ว', 'ซอสถั่วเหลือง', 'light soy sauce'],
  'fish sauce': ['น้ำปลา', 'น้ำปลาไทย', 'nam pla', 'thai fish sauce'],
  'oyster sauce': ['ซอสหอยนางรม'],
  'palm sugar': ['น้ำตาลปี๊บ', 'น้ำตาลปึก', 'coconut sugar'],
  'sugar': [
    'น้ำตาล',
    'น้ำตาลทราย',
    'น้ำตาลทรายขาว',
    'granulated sugar',
    'white sugar',
    'sugar',
  ],
  'coconut milk': ['กะทิ', 'coconut cream', 'หัวกะทิ'],
  'shrimp': [
    'กุ้ง',
    'กุ้งสด',
    'กุ้งขาว',
    'กุ้งแชบ๊วย',
    'กุ้งกุลาดำ',
    'พุงกุ้ง',
    'prawn',
    'prawns',
    'shrimp',
  ],
  'squid': ['ปลาหมึก', 'หมึก', 'squid'],
  'shrimp paste': ['กะปิ', 'กะปิไทย', 'shrimp paste'],
  'tomato': ['มะเขือเทศ', 'มะเขือเทศสด', 'tomato', 'tomatoes'],
  'fish': ['ปลา', 'ปลากะพง', 'ปลาทู', 'ปลาดอลลี่', 'ปลานิล'],
  'pork shoulder': ['สันคอหมู', 'คอหมู', 'pork collar'],
  'pork loin': ['หมูสันนอก', 'pork sirloin'],
  'pork belly': ['หมูสามชั้น', 'streaky pork'],
  'chicken breast': ['อกไก่', 'chicken fillet'],
  'chicken thigh': ['น่องไก่', 'chicken drumstick', 'chicken thigh'],
  'chicken wing': ['ปีกไก่', 'chicken wing'],
  'holy basil': ['กะเพรา', 'ใบกะเพรา', 'holy basil', 'thai holy basil'],
  'thai basil': ['โหระพา', 'ใบโหระพา', 'sweet basil', 'bai horapa'],
  'lime': ['มะนาว', 'lime', 'lemon'],
  'bird chili': ['พริกขี้หนู', "bird's eye chili", 'bird eye chili'],
  'garlic': ['กระเทียม', 'garlic clove'],
  'shallot': ['หอมแดง', 'shallot'],
  'onion': ['หอมหัวใหญ่', 'หอมใหญ่', 'หัวหอม', 'onion', 'onions'],
  'spring onion': ['ต้นหอม', 'scallion', 'green onion'],
  'coriander': ['ผักชี', 'cilantro'],
  'jasmine rice': ['ข้าวหอมมะลิ', 'ข้าวสารหอมมะลิ', 'jasmine rice'],
  'sticky rice': ['ข้าวเหนียว', 'glutinous rice', 'sticky rice'],
  'cabbage': ['กะหล่ำปลี', 'cabbage'],
  'carrot': ['แครอท', 'carrot'],
  'potato': ['มันฝรั่ง', 'potato'],
};

const Map<String, double> _canonicalLossFactorSeeds = {
  'fish': 0.12,
  'shrimp': 0.1,
  'squid': 0.08,
  'pork shoulder': 0.08,
  'pork belly': 0.05,
  'pork loin': 0.05,
  'chicken breast': 0.05,
  'chicken thigh': 0.08,
  'chicken wing': 0.07,
  'holy basil': 0.15,
  'thai basil': 0.15,
  'spring onion': 0.1,
  'coriander': 0.1,
  'cabbage': 0.15,
  'carrot': 0.08,
  'potato': 0.08,
  'jasmine rice': 0.03,
  'sticky rice': 0.04,
};

class IngredientShortage {
  final String name;
  final double requiredAmount;
  final double availableAmount;
  final String unit;

  const IngredientShortage({
    required this.name,
    required this.requiredAmount,
    required this.availableAmount,
    required this.unit,
  });

  double get missingAmount => math.max(0, requiredAmount - availableAmount);
}

class CookingResult {
  final bool success;
  final bool partial;
  final List<IngredientShortage> shortages;

  const CookingResult({
    required this.success,
    this.partial = false,
    this.shortages = const [],
  });
}

class CookingService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  static final Map<String, Set<String>> _canonicalToAliases =
      _buildCanonicalAliasMap();
  static final Map<String, String> _synonymToCanonical = _buildSynonymLookup();
  static final Map<String, double> _canonicalLossFactors =
      _buildCanonicalLossFactors();

  // ✅ ตรวจสอบก่อนทำอาหาร (โค้ดเดิมของคุณ)
  Future<IngredientCheckResult> previewCooking(
    RecipeModel recipe,
    int servingsToMake, {
    Map<String, double>? manualRequiredAmounts,
    List<qty.ManualCustomIngredient>? manualCustomIngredients,
  }) async {
    return _checkIngredientAvailability(
      recipe,
      servingsToMake,
      manualRequiredAmounts: manualRequiredAmounts,
      manualCustomIngredients: manualCustomIngredients,
    );
  }

  // ✅ เริ่มทำอาหาร (โค้ดเดิมของคุณ)
  Future<CookingResult> startCooking(
    RecipeModel recipe,
    int servingsToMake, {
    bool allowPartial = false,
    Map<String, double>? manualRequiredAmounts,
    List<qty.ManualCustomIngredient>? manualCustomIngredients,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return const CookingResult(success: false);

    try {
      // การตรวจสอบวัตถุดิบตอนนี้เป็น async เต็มรูปแบบ
      final check = await _checkIngredientAvailability(
        recipe,
        servingsToMake,
        manualRequiredAmounts: manualRequiredAmounts,
        manualCustomIngredients: manualCustomIngredients,
      );

      if (!check.isSufficient && !allowPartial) {
        return CookingResult(success: false, shortages: check.shortages);
      }

      // การลดสต็อกก็เป็น async เช่นกัน
      final used = await _reduceIngredientStock(
        recipe,
        servingsToMake,
        allowPartial: allowPartial || !check.isSufficient,
        manualRequiredAmounts: manualRequiredAmounts,
        manualCustomIngredients: manualCustomIngredients,
      );

      final ingredientPortions = _snapshotIngredientPortions(
        recipe,
        servingsToMake,
        manualRequiredAmounts,
        manualCustomIngredients,
      );

      await _recordCookingHistory(
        recipe,
        servingsMade: servingsToMake,
        usedIngredients: used,
        ingredientPortions: ingredientPortions,
        recipeNutritionPerServing: recipe.nutrition,
        recipeStepsSnapshot: recipe.steps,
      );

      return CookingResult(
        success: true,
        partial: !check.isSufficient,
        shortages: check.shortages,
      );
    } catch (e) {
      print('❌ Error starting cooking: $e');
      return const CookingResult(success: false);
    }
  }

  // ⭐️ [โค้ดเดิมของคุณ] ตรวจสอบวัตถุดิบ
  Future<IngredientCheckResult> _checkIngredientAvailability(
    RecipeModel recipe,
    int servingsToMake, {
    Map<String, double>? manualRequiredAmounts,
    List<qty.ManualCustomIngredient>? manualCustomIngredients,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return const IngredientCheckResult(isSufficient: false);

    final shortages = <IngredientShortage>[];
    final manualMap =
        (manualRequiredAmounts == null || manualRequiredAmounts.isEmpty)
        ? null
        : manualRequiredAmounts.map(
            (key, value) => MapEntry(qty.normalizeName(key), value),
          );

    final manualExtras =
        (manualCustomIngredients ?? const <qty.ManualCustomIngredient>[])
            .map((item) => item.sanitize())
            .where((item) => item.isValid)
            .toList();

    final checks = <Future<void>>[];

    checks.addAll(
      recipe.ingredients.map((ing) async {
        final baseServings = recipe.servings == 0 ? 1 : recipe.servings;
        final requiredAmount = _scaledAmount(
          ing.numericAmount,
          servingsToMake,
          baseServings,
        );

        final normalizedIngredientName = qty.normalizeName(ing.name);
        final manualRaw = manualMap?[normalizedIngredientName];
        double effectiveRequired = requiredAmount;
        if (manualRaw != null && manualRaw.isFinite) {
          effectiveRequired = manualRaw < 0 ? 0 : manualRaw;
        }
        if (effectiveRequired <= 0) {
          return;
        }

        // ✅ [จุดสำคัญ] เรียก "ไฮบริดคอนเวอร์เตอร์" (ซึ่งจะคืนค่า CanonicalQuantity? หรือ null)
        final requiredCanonical =
            await SmartUnitConverter.convertRecipeUnitToInventoryUnit(
              ingredientName: ing.name,
              recipeAmount: effectiveRequired,
              recipeUnit: ing.unit,
            );

        if (requiredCanonical == null) {
          print(
            '⚠️ (CookingService) ไม่สามารถแปลงหน่วยสำหรับ ${ing.name} (${ing.unit}) ได้ (ข้ามการตรวจสอบ)',
          );
          return; // ข้ามวัตถุดิบนี้ไปถ้าแปลงหน่วยไม่ได้
        }

        // รวมปริมาณวัตถุดิบทั้งหมดที่มีในคลังให้เป็นหน่วย Canonical เดียวกัน
        double availableCanonicalAmount = 0;
        final inventoryDocs = await _findInventoryDocs(user.uid, ing.name);

        for (final doc in inventoryDocs) {
          final data = doc.data();
          final quantity = _toDouble(data['quantity']);
          final unit = (data['unit'] ?? '').toString();

          availableCanonicalAmount += _convertStockToCanonical(
            ing.name,
            quantity,
            unit,
            requiredCanonical.unit, // <-- ใช้ .unit จาก CanonicalQuantity
          );
        }

        if (availableCanonicalAmount < requiredCanonical.amount) {
          // <-- ใช้ .amount จาก CanonicalQuantity
          shortages.add(
            IngredientShortage(
              name: ing.name,
              requiredAmount: requiredCanonical.amount,
              availableAmount: availableCanonicalAmount,
              unit: _mapCanonicalUnitToDisplayUnit(requiredCanonical.unit),
            ),
          );
        }
      }),
    );

    for (final custom in manualExtras) {
      checks.add(() async {
        final normalizedUnit = custom.unit.trim().isEmpty
            ? 'ชิ้น'
            : custom.unit.trim();
        qty.CanonicalQuantity? requiredCanonical;
        try {
          final converted =
              await SmartUnitConverter.convertRecipeUnitToInventoryUnit(
                ingredientName: custom.name,
                recipeAmount: custom.amount,
                recipeUnit: normalizedUnit,
              );
          if (converted != null) {
            requiredCanonical = qty.CanonicalQuantity(
              converted.amount,
              converted.unit,
            );
          }
        } catch (_) {
          requiredCanonical = null;
        }
        requiredCanonical ??= qty.toCanonicalQuantity(
          custom.amount,
          normalizedUnit,
          custom.name,
        );

        double availableCanonicalAmount = 0;
        final inventoryDocs = await _findInventoryDocs(user.uid, custom.name);

        for (final doc in inventoryDocs) {
          final data = doc.data();
          final quantity = _toDouble(data['quantity']);
          final unit = (data['unit'] ?? '').toString();

          availableCanonicalAmount += _convertStockToCanonical(
            custom.name,
            quantity,
            unit,
            requiredCanonical.unit,
          );
        }

        if (availableCanonicalAmount < requiredCanonical.amount) {
          shortages.add(
            IngredientShortage(
              name: custom.name,
              requiredAmount: requiredCanonical.amount,
              availableAmount: availableCanonicalAmount,
              unit: _mapCanonicalUnitToDisplayUnit(requiredCanonical.unit),
            ),
          );
        }
      }());
    }

    await Future.wait(checks);

    return IngredientCheckResult(
      isSufficient: shortages.isEmpty,
      shortages: shortages,
    );
  }

  // ⭐️ [โค้ดเดิมของคุณ] ลดวัตถุดิบใน stock
  Future<List<UsedIngredient>> _reduceIngredientStock(
    RecipeModel recipe,
    int servingsToMake, {
    bool allowPartial = false,
    Map<String, double>? manualRequiredAmounts,
    List<qty.ManualCustomIngredient>? manualCustomIngredients,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final usedIngredients = <UsedIngredient>[];
    final manualMap =
        (manualRequiredAmounts == null || manualRequiredAmounts.isEmpty)
        ? null
        : manualRequiredAmounts.map(
            (key, value) => MapEntry(qty.normalizeName(key), value),
          );
    final manualExtras =
        (manualCustomIngredients ?? const <qty.ManualCustomIngredient>[])
            .map((item) => item.sanitize())
            .where((item) => item.isValid)
            .toList();
    final effectiveServings = servingsToMake <= 0
        ? 1.0
        : servingsToMake.toDouble();

    for (final ing in recipe.ingredients) {
      final baseServings = recipe.servings == 0 ? 1 : recipe.servings;
      final scaledAmount = _scaledAmount(
        ing.numericAmount,
        servingsToMake,
        baseServings,
      );

      final normalizedIngredientName = qty.normalizeName(ing.name);
      final manualRaw = manualMap?[normalizedIngredientName];
      double? manualAmount;
      if (manualRaw != null && manualRaw.isFinite) {
        manualAmount = manualRaw < 0 ? 0 : manualRaw;
      }

      final effectiveRecipeAmount = manualAmount ?? scaledAmount;
      if (effectiveRecipeAmount <= 0) {
        continue;
      }

      // ✅ [จุดสำคัญ] เรียก "ไฮบริดคอนเวอร์เตอร์" (ซึ่งจะคืนค่า CanonicalQuantity? หรือ null)
      final requiredCanonical =
          await SmartUnitConverter.convertRecipeUnitToInventoryUnit(
            ingredientName: ing.name,
            recipeAmount: effectiveRecipeAmount,
            recipeUnit: ing.unit,
          );

      if (requiredCanonical == null) {
        print(
          '⚠️ (CookingService) ไม่สามารถแปลงหน่วยสำหรับ ${ing.name} (${ing.unit}) เพื่อตัดสต็อกได้ (ข้าม)',
        );
        continue; // ข้ามไปถ้าแปลงหน่วยไม่ได้
      }

      double canonicalTarget = requiredCanonical.amount;
      if (manualAmount == null) {
        final minimumCanonical = qty.minimumCanonicalRequirementForCooking(
          ingredientName: ing.name,
          canonicalUnit: requiredCanonical.unit,
          servings: effectiveServings,
        );
        if (minimumCanonical > canonicalTarget) {
          canonicalTarget = minimumCanonical;
        }
        final lossFactor = _preparationLossFactor(
          ing.name,
          requiredCanonical.unit,
        );
        if (lossFactor > 0) {
          canonicalTarget *= (1 + lossFactor);
        }
      }

      if (canonicalTarget <= 0) {
        continue;
      }

      // ดึงรายการวัตถุดิบทั้งหมดที่ชื่อตรงกัน (รวมกรณีชื่อคล้าย)
      final inventoryDocs = await _findInventoryDocs(user.uid, ing.name);
      final sortedInventoryDocs = _orderInventoryByExpiry(
        inventoryDocs,
      ); // ใช้ของที่ใกล้หมดก่อน
      double amountRemaining =
          canonicalTarget; // <-- ปริมาณที่ต้องการตัดตามเกณฑ์ขั้นต่ำ
      double consumedCanonical = 0;
      String? usedCategory;

      for (final doc in sortedInventoryDocs) {
        if (amountRemaining <= 0) break;

        final data = doc.data();
        final currentQty = _toDouble(data['quantity']);
        final currentUnit = (data['unit'] ?? '').toString();

        final availableCanonical = _convertStockToCanonical(
          ing.name,
          currentQty,
          currentUnit,
          requiredCanonical.unit, // <-- ใช้ .unit
        );

        if (availableCanonical <= 0) continue;

        final targetDeduction = math.min(amountRemaining, availableCanonical);
        if (targetDeduction <= 0) continue;

        final provisionalRemaining = availableCanonical - targetDeduction;
        final stockUpdate = _canonicalToStockQuantity(
          ing.name,
          provisionalRemaining,
          currentUnit,
          requiredCanonical.unit, // <-- ใช้ .unit
        );

        final adjustedRemainingCanonical = stockUpdate.canonicalAmount;
        final actualDeduction = availableCanonical - adjustedRemainingCanonical;
        if (actualDeduction <= 0) {
          continue;
        }

        await doc.reference.update({
          'quantity': stockUpdate.quantity,
          'unit': stockUpdate.unit,
          'updated_at': FieldValue.serverTimestamp(),
        });

        consumedCanonical += actualDeduction;
        amountRemaining -= actualDeduction;
        if (amountRemaining < 0) amountRemaining = 0;
        usedCategory ??= (data['category'] ?? '').toString();
      }

      if (consumedCanonical > 0) {
        final usedUnit = _mapCanonicalUnitToDisplayUnit(
          requiredCanonical.unit,
        ); // <-- ใช้ .unit
        usedIngredients.add(
          UsedIngredient(
            name: ing.name,
            amount: _roundDouble(consumedCanonical),
            unit: usedUnit,
            category: usedCategory ?? '',
            cost: 0,
          ),
        );
      }
    }

    for (final custom in manualExtras) {
      final normalizedUnit = custom.unit.trim().isEmpty
          ? 'ชิ้น'
          : custom.unit.trim();
      qty.CanonicalQuantity? requiredCanonical;
      try {
        final converted =
            await SmartUnitConverter.convertRecipeUnitToInventoryUnit(
              ingredientName: custom.name,
              recipeAmount: custom.amount,
              recipeUnit: normalizedUnit,
            );
        if (converted != null) {
          requiredCanonical = qty.CanonicalQuantity(
            converted.amount,
            converted.unit,
          );
        }
      } catch (_) {
        requiredCanonical = null;
      }
      requiredCanonical ??= qty.toCanonicalQuantity(
        custom.amount,
        normalizedUnit,
        custom.name,
      );

      double canonicalTarget = requiredCanonical.amount;
      if (canonicalTarget <= 0) continue;

      final inventoryDocs = await _findInventoryDocs(user.uid, custom.name);
      final sortedInventoryDocs = _orderInventoryByExpiry(inventoryDocs);
      double amountRemaining = canonicalTarget;
      double consumedCanonical = 0;
      String? usedCategory;

      for (final doc in sortedInventoryDocs) {
        if (amountRemaining <= 0) break;

        final data = doc.data();
        final currentQty = _toDouble(data['quantity']);
        final currentUnit = (data['unit'] ?? '').toString();

        final availableCanonical = _convertStockToCanonical(
          custom.name,
          currentQty,
          currentUnit,
          requiredCanonical.unit,
        );

        if (availableCanonical <= 0) continue;

        final targetDeduction = math.min(amountRemaining, availableCanonical);
        if (targetDeduction <= 0) continue;

        final provisionalRemaining = availableCanonical - targetDeduction;
        final stockUpdate = _canonicalToStockQuantity(
          custom.name,
          provisionalRemaining,
          currentUnit,
          requiredCanonical.unit,
        );

        final adjustedRemainingCanonical = stockUpdate.canonicalAmount;
        final actualDeduction = availableCanonical - adjustedRemainingCanonical;
        if (actualDeduction <= 0) continue;

        await doc.reference.update({
          'quantity': stockUpdate.quantity,
          'unit': stockUpdate.unit,
          'updated_at': FieldValue.serverTimestamp(),
        });

        consumedCanonical += actualDeduction;
        amountRemaining -= actualDeduction;
        if (amountRemaining < 0) amountRemaining = 0;
        usedCategory ??= (data['category'] ?? '').toString();
      }

      if (consumedCanonical > 0) {
        final usedUnit = _mapCanonicalUnitToDisplayUnit(requiredCanonical.unit);
        usedIngredients.add(
          UsedIngredient(
            name: custom.name,
            amount: _roundDouble(consumedCanonical),
            unit: usedUnit,
            category: usedCategory ?? '',
            cost: 0,
          ),
        );
      }
    }
    return usedIngredients;
  }

  // ------------------------------
  // 🔹 Helper Functions (โค้ดเดิมของคุณ)
  // ------------------------------

  // ฟังก์ชัน Helper เพื่อ map ชื่อหน่วย canonical ให้ตรงกับใน UnitConverter ของคลัง
  String _mapCanonicalUnitToStockUnit(String canonicalUnit) {
    if (canonicalUnit == 'gram') return StockConverter.UnitConverter.gram;
    if (canonicalUnit == 'milliliter')
      return StockConverter.UnitConverter.milliliter;
    if (canonicalUnit == 'ฟอง') return 'ฟอง';
    if (canonicalUnit == 'piece') return 'ชิ้น';
    return StockConverter.UnitConverter.gram; // fallback
  }

  // ฟังก์ชัน Helper เพื่อแสดงผลหน่วยให้ผู้ใช้เข้าใจง่าย
  String _mapCanonicalUnitToDisplayUnit(String canonicalUnit) {
    if (canonicalUnit == 'gram') return 'กรัม';
    if (canonicalUnit == 'milliliter') return 'มิลลิลิตร';
    if (canonicalUnit == 'ฟอง') return 'ฟอง';
    if (canonicalUnit == 'piece') return 'ชิ้น';
    return canonicalUnit;
  }

  double _convertStockToCanonical(
    String ingredientName,
    num quantity,
    String unit,
    String canonicalUnit,
  ) {
    final normalized = unit.trim();
    final value = quantity.toDouble();
    if (value <= 0) return 0;

    bool _isGramUnit(String u) =>
        u == StockConverter.UnitConverter.gram ||
        u.toLowerCase() == 'gram' ||
        u.toLowerCase() == 'grams';
    bool _isKilogramUnit(String u) =>
        u == StockConverter.UnitConverter.kilogram ||
        u.toLowerCase() == 'kilogram' ||
        u.toLowerCase() == 'kilograms';
    bool _isMilliliterUnit(String u) =>
        u == StockConverter.UnitConverter.milliliter ||
        u.toLowerCase() == 'milliliter' ||
        u.toLowerCase() == 'milliliters';
    bool _isLiterUnit(String u) =>
        u == StockConverter.UnitConverter.liter ||
        u.toLowerCase() == 'liter' ||
        u.toLowerCase() == 'liters';
    bool _isPieceUnit(String u) =>
        PieceUnitConverter.SmartUnitConverter.isPieceUnit(u.toLowerCase());

    if (canonicalUnit == 'gram') {
      if (_isGramUnit(normalized)) return value;
      if (_isKilogramUnit(normalized)) {
        return value * MeasurementConstants.gramsPerKilogram;
      }
      if (_isPieceUnit(normalized)) {
        final grams = PieceUnitConverter.SmartUnitConverter.gramsFromPiece(
          value,
          normalized,
          ingredientName,
        );
        if (grams != null) return grams;
      }
      if (_isMilliliterUnit(normalized) || _isLiterUnit(normalized)) {
        final milliliters = _isLiterUnit(normalized)
            ? value * MeasurementConstants.millilitersPerLiter
            : value;
        final grams = _gramsFromVolume(ingredientName, milliliters);
        return grams ?? milliliters;
      }
      if (normalized == 'ฟอง') {
        final grams = PieceUnitConverter.SmartUnitConverter.gramsFromPiece(
          value,
          normalized,
          ingredientName,
        );
        if (grams != null) return grams;
      }
      return 0;
    }

    if (canonicalUnit == 'milliliter') {
      if (_isMilliliterUnit(normalized)) return value;
      if (_isLiterUnit(normalized)) {
        return value * MeasurementConstants.millilitersPerLiter;
      }
      if (_isPieceUnit(normalized)) {
        final grams = PieceUnitConverter.SmartUnitConverter.gramsFromPiece(
          value,
          normalized,
          ingredientName,
        );
        if (grams != null) {
          final ml = _volumeFromGrams(ingredientName, grams);
          if (ml != null) return ml;
        }
      }
      if (_isGramUnit(normalized) || _isKilogramUnit(normalized)) {
        final grams = _isKilogramUnit(normalized)
            ? value * MeasurementConstants.gramsPerKilogram
            : value;
        final milliliters = _volumeFromGrams(ingredientName, grams);
        return milliliters ?? grams;
      }
      return 0;
    }

    if (canonicalUnit == 'ฟอง' || canonicalUnit == 'piece') {
      if (_isPieceUnit(normalized)) {
        if (canonicalUnit == 'ฟอง' && normalized == 'ฟอง') {
          return value;
        }
        final grams = PieceUnitConverter.SmartUnitConverter.gramsFromPiece(
          value,
          normalized,
          ingredientName,
        );
        if (grams != null) {
          final targetUnit = canonicalUnit == 'ฟอง' ? 'ฟอง' : 'ชิ้น';
          final pieces =
              PieceUnitConverter.SmartUnitConverter.convertGramsToPiece(
                grams,
                targetUnit,
                ingredientName,
              );
          if (pieces != null) return pieces;
        }
        return value;
      }
      if (_isGramUnit(normalized) || _isKilogramUnit(normalized)) {
        final grams = _isKilogramUnit(normalized)
            ? value * MeasurementConstants.gramsPerKilogram
            : value;
        final targetUnit = canonicalUnit == 'ฟอง' ? 'ฟอง' : 'ชิ้น';
        final pieces =
            PieceUnitConverter.SmartUnitConverter.convertGramsToPiece(
              grams,
              targetUnit,
              ingredientName,
            );
        if (pieces != null) return pieces;
      }
    }

    return 0;
  }

  _StockQuantity _canonicalToStockQuantity(
    String ingredientName,
    double canonicalAmount,
    String originalUnit,
    String canonicalUnit,
  ) {
    final safeAmount = canonicalAmount <= 0 ? 0 : canonicalAmount;
    final normalizedOriginal = originalUnit.trim();

    bool _isGramUnit(String u) =>
        u == StockConverter.UnitConverter.gram ||
        u.toLowerCase() == 'gram' ||
        u.toLowerCase() == 'grams';
    bool _isKilogramUnit(String u) =>
        u == StockConverter.UnitConverter.kilogram ||
        u.toLowerCase() == 'kilogram' ||
        u.toLowerCase() == 'kilograms';
    bool _isMilliliterUnit(String u) =>
        u == StockConverter.UnitConverter.milliliter ||
        u.toLowerCase() == 'milliliter' ||
        u.toLowerCase() == 'milliliters';
    bool _isLiterUnit(String u) =>
        u == StockConverter.UnitConverter.liter ||
        u.toLowerCase() == 'liter' ||
        u.toLowerCase() == 'liters';

    if (_isGramUnit(normalizedOriginal) ||
        _isKilogramUnit(normalizedOriginal)) {
      double grams = 0;
      if (canonicalUnit == 'gram') {
        grams = safeAmount.toDouble();
      } else if (canonicalUnit == 'milliliter') {
        grams =
            (_gramsFromVolume(ingredientName, safeAmount.toDouble()) ??
            safeAmount.toDouble());
      } else {
        grams = safeAmount.toDouble();
      }
      if (grams <= 0) {
        return _StockQuantity(0, StockConverter.UnitConverter.gram, 0);
      }
      final rounded = grams.floor();
      final canonicalRounded = rounded.toDouble();
      if (rounded == 0) {
        return _StockQuantity(0, StockConverter.UnitConverter.gram, 0);
      }
      if (_isKilogramUnit(normalizedOriginal) &&
          rounded % MeasurementConstants.gramsPerKilogram == 0) {
        final kilograms = rounded ~/ MeasurementConstants.gramsPerKilogram;
        return _StockQuantity(
          kilograms,
          StockConverter.UnitConverter.kilogram,
          kilograms * MeasurementConstants.gramsPerKilogram.toDouble(),
        );
      }
      return _StockQuantity(
        rounded,
        StockConverter.UnitConverter.gram,
        canonicalRounded,
      );
    }

    if (_isMilliliterUnit(normalizedOriginal) ||
        _isLiterUnit(normalizedOriginal)) {
      double milliliters = 0;
      if (canonicalUnit == 'milliliter') {
        milliliters = safeAmount.toDouble();
      } else if (canonicalUnit == 'gram') {
        milliliters =
            (_volumeFromGrams(ingredientName, safeAmount.toDouble()) ??
            safeAmount.toDouble());
      } else {
        milliliters = safeAmount.toDouble();
      }
      if (milliliters <= 0) {
        return _StockQuantity(0, StockConverter.UnitConverter.milliliter, 0);
      }
      final rounded = milliliters.floor();
      final canonicalRounded = rounded.toDouble();
      if (rounded == 0) {
        return _StockQuantity(0, StockConverter.UnitConverter.milliliter, 0);
      }
      if (_isLiterUnit(normalizedOriginal) &&
          rounded % MeasurementConstants.millilitersPerLiter == 0) {
        final liters = rounded ~/ MeasurementConstants.millilitersPerLiter;
        return _StockQuantity(
          liters,
          StockConverter.UnitConverter.liter,
          liters * MeasurementConstants.millilitersPerLiter.toDouble(),
        );
      }
      return _StockQuantity(
        rounded,
        StockConverter.UnitConverter.milliliter,
        canonicalRounded,
      );
    }

    if (PieceUnitConverter.SmartUnitConverter.isPieceUnit(
      normalizedOriginal.toLowerCase(),
    )) {
      double pieces = safeAmount.toDouble();
      final resolvedUnit = normalizedOriginal.isEmpty
          ? _mapCanonicalUnitToStockUnit('piece')
          : normalizedOriginal;

      double? _convertFromGrams(double grams, String targetUnit) {
        return PieceUnitConverter.SmartUnitConverter.convertGramsToPiece(
          grams,
          targetUnit,
          ingredientName,
        );
      }

      if (canonicalUnit == 'gram') {
        final converted = _convertFromGrams(
          safeAmount.toDouble(),
          resolvedUnit,
        );
        if (converted != null) pieces = converted;
      } else if (canonicalUnit == 'milliliter') {
        final grams =
            _gramsFromVolume(ingredientName, safeAmount.toDouble()) ??
            safeAmount.toDouble();
        final converted = _convertFromGrams(grams, resolvedUnit);
        if (converted != null) pieces = converted;
      } else if (canonicalUnit == 'ฟอง') {
        final grams = PieceUnitConverter.SmartUnitConverter.gramsFromPiece(
          safeAmount.toDouble(),
          resolvedUnit,
          ingredientName,
        );
        if (grams != null) {
          final converted = _convertFromGrams(grams, 'ฟอง');
          if (converted != null) pieces = converted;
        }
      } else if (canonicalUnit == 'piece') {
        final grams = PieceUnitConverter.SmartUnitConverter.gramsFromPiece(
          safeAmount.toDouble(),
          resolvedUnit,
          ingredientName,
        );
        if (grams != null) {
          final converted = _convertFromGrams(grams, resolvedUnit);
          if (converted != null) pieces = converted;
        }
      }
      final roundedPieces = pieces.round();
      return _StockQuantity(
        roundedPieces,
        resolvedUnit,
        roundedPieces.toDouble(),
      );
    }

    final fallbackRounded = safeAmount.floor();
    final fallbackCanonical = fallbackRounded.toDouble();
    return _StockQuantity(
      fallbackRounded,
      _mapCanonicalUnitToStockUnit(canonicalUnit),
      fallbackCanonical,
    );
  }

  double? _gramsFromVolume(String ingredientName, double milliliters) {
    final density = _densityForIngredient(ingredientName);
    if (density == null) return null;
    return milliliters * density;
  }

  double? _volumeFromGrams(String ingredientName, double grams) {
    final density = _densityForIngredient(ingredientName);
    if (density == null || density == 0) return null;
    return grams / density;
  }

  double? _densityForIngredient(String ingredientName) {
    return SmartUnitConverter.densityForIngredient(ingredientName) ?? 1.0;
  }

  double _preparationLossFactor(String ingredientName, String canonicalUnit) {
    if (canonicalUnit == 'piece' || canonicalUnit == 'ฟอง') {
      return 0;
    }
    final canonical = _canonicalizeName(ingredientName);
    final factor = _canonicalLossFactors[canonical];
    if (factor != null) return factor;

    final normalized = _normalizeName(ingredientName);
    if (normalized.contains('ผัก') ||
        normalized.contains('ใบ') ||
        normalized.contains('leaf')) {
      return 0.1;
    }
    if (normalized.contains('กระดูก') || normalized.contains('bone')) {
      return 0.08;
    }
    if (normalized.contains('ปลา')) {
      return 0.1;
    }
    return 0;
  }

  static Set<String> _aliasesForCanonical(String canonical) {
    return _canonicalToAliases[canonical] ?? const <String>{};
  }

  static Map<String, Set<String>> _buildCanonicalAliasMap() {
    final map = <String, Set<String>>{};
    for (final entry in _canonicalNameSeeds.entries) {
      final canonical = _normalizeName(entry.key);
      if (canonical.isEmpty) continue;
      final bucket = map.putIfAbsent(canonical, () => <String>{});
      bucket.add(canonical);
      for (final synonym in entry.value) {
        final normalizedSyn = _normalizeName(synonym);
        if (normalizedSyn.isNotEmpty) {
          bucket.add(normalizedSyn);
        }
      }
    }
    return map;
  }

  static Map<String, String> _buildSynonymLookup() {
    final map = <String, String>{};
    for (final entry in _canonicalNameSeeds.entries) {
      final canonical = _normalizeName(entry.key);
      if (canonical.isEmpty) continue;
      map[canonical] = canonical;
      for (final synonym in entry.value) {
        final normalizedSyn = _normalizeName(synonym);
        if (normalizedSyn.isNotEmpty) {
          map[normalizedSyn] = canonical;
        }
      }
    }
    return map;
  }

  static Map<String, double> _buildCanonicalLossFactors() {
    final map = <String, double>{};
    _canonicalLossFactorSeeds.forEach((key, value) {
      final canonical = _normalizeName(key);
      if (canonical.isEmpty) return;
      map[canonical] = value;
    });
    return map;
  }

  static String _canonicalizeName(String name) {
    final normalized = _normalizeName(name);
    if (normalized.isEmpty) return normalized;
    final translated = _normalizeName(IngredientTranslator.translate(name));
    return _synonymToCanonical[normalized] ??
        _synonymToCanonical[translated] ??
        normalized;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _orderInventoryByExpiry(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (docs.length <= 1) return docs;
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    sorted.sort((a, b) {
      final expiryA = _extractExpiryDate(a);
      final expiryB = _extractExpiryDate(b);
      if (expiryA == null && expiryB == null) {
        final createdA = _extractCreatedDate(a);
        final createdB = _extractCreatedDate(b);
        if (createdA == null && createdB == null) {
          return a.id.compareTo(b.id);
        }
        if (createdA == null) return 1;
        if (createdB == null) return -1;
        final createdComparison = createdA.compareTo(createdB);
        if (createdComparison != 0) return createdComparison;
        return a.id.compareTo(b.id);
      }
      if (expiryA == null) return 1;
      if (expiryB == null) return -1;
      final expiryComparison = expiryA.compareTo(expiryB);
      if (expiryComparison != 0) return expiryComparison;
      final createdA = _extractCreatedDate(a);
      final createdB = _extractCreatedDate(b);
      if (createdA == null && createdB == null) {
        return a.id.compareTo(b.id);
      }
      if (createdA == null) return 1;
      if (createdB == null) return -1;
      final createdComparison = createdA.compareTo(createdB);
      if (createdComparison != 0) return createdComparison;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  DateTime? _extractExpiryDate(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _parseFirestoreDate(data['expiry_date']);
  }

  DateTime? _extractCreatedDate(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final candidates = [
      data['created_at'],
      data['created_at_local'],
      data['added_at'],
      data['added_date'],
      data['added_at_local'],
      data['updated_at'],
    ];
    for (final value in candidates) {
      final parsed = _parseFirestoreDate(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _parseFirestoreDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      return value.toDate().toLocal();
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final parsed = DateTime.tryParse(trimmed);
      if (parsed != null) return parsed.isUtc ? parsed.toLocal() : parsed;
    }
    return null;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _findInventoryDocs(
    String userId,
    String ingredientName,
  ) async {
    final aliasQueue = <String>[];
    void pushAlias(String candidate) {
      final normalized = _normalizeName(candidate);
      if (normalized.isEmpty) return;
      if (!aliasQueue.contains(normalized)) aliasQueue.add(normalized);
      final collapsed = normalized.replaceAll(' ', '');
      if (collapsed.isNotEmpty && !aliasQueue.contains(collapsed)) {
        aliasQueue.add(collapsed);
      }
    }

    void addAlias(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      pushAlias(trimmed);

      for (final token in trimmed.split(RegExp(r'[\s,/-]+'))) {
        final t = token.trim();
        if (t.length >= 2) pushAlias(t);
      }

      final translated = IngredientTranslator.translate(trimmed).trim();
      if (translated.isNotEmpty) {
        pushAlias(translated);
        for (final token in translated.split(RegExp(r'[\s,/-]+'))) {
          final t = token.trim();
          if (t.length >= 2) pushAlias(t);
        }
      }
    }

    final canonical = _canonicalizeName(ingredientName);
    addAlias(canonical);
    for (final alias in _aliasesForCanonical(canonical)) {
      addAlias(alias);
    }
    for (final alias in _buildNameAliases(ingredientName)) {
      addAlias(alias);
    }

    final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> results = {};
    final collection = _firestore
        .collection('users')
        .doc(userId)
        .collection('raw_materials');

    for (final alias in aliasQueue) {
      Query<Map<String, dynamic>> query = collection.where(
        'name_key',
        isEqualTo: alias,
      );
      bool orderedFetched = false;
      try {
        final orderedSnapshot = await query
            .orderBy('expiry_date')
            .orderBy('created_at')
            .get();
        orderedFetched = true;
        for (final doc in orderedSnapshot.docs) {
          results[doc.id] = doc;
        }
      } catch (_) {
        // อาจไม่มี composite index ให้ fallback เป็น query ปกติ
      }
      if (!orderedFetched) {
        final snapshot = await query.get();
        for (final doc in snapshot.docs) {
          results[doc.id] = doc;
        }
      }
    }

    if (results.isNotEmpty) {
      return _orderInventoryByExpiry(results.values.toList());
    }

    final fallbackSnapshot = await collection.get();
    for (final doc in fallbackSnapshot.docs) {
      if (_matchesAlias(doc.data(), aliasQueue.toSet())) {
        results[doc.id] = doc;
      }
    }
    return _orderInventoryByExpiry(results.values.toList());
  }

  Set<String> _buildNameAliases(String name) {
    final aliases = <String>{};
    final normalized = _normalizeName(name);
    final translated = _normalizeName(IngredientTranslator.translate(name));
    final canonical = _canonicalizeName(name);

    aliases.add(normalized);
    aliases.add(translated);
    aliases.add(canonical);
    aliases.addAll(_aliasesForCanonical(canonical));

    aliases.addAll(_tokenize(normalized));
    aliases.addAll(_tokenize(translated));

    final collapsed = normalized.replaceAll(' ', '');
    if (collapsed.isNotEmpty) aliases.add(collapsed);

    return aliases..removeWhere((value) => value.isEmpty);
  }

  bool _matchesAlias(Map<String, dynamic> data, Set<String> aliases) {
    if (aliases.isEmpty) return false;
    final rawName = data['name']?.toString() ?? '';
    final rawKey = data['name_key']?.toString() ?? '';
    final normalizedName = _normalizeName(rawName);
    final normalizedKey = _normalizeName(rawKey);
    final translatedName = _normalizeName(
      IngredientTranslator.translate(rawName),
    );
    final canonicalName = _canonicalizeName(rawName);

    for (final alias in aliases) {
      if (alias.isEmpty) continue;
      final aliasCollapsed = alias.replaceAll(' ', '');
      if (normalizedName.contains(alias) || alias.contains(normalizedName)) {
        return true;
      }
      if (normalizedKey.contains(alias) || alias.contains(normalizedKey)) {
        return true;
      }
      if (translatedName.contains(alias) || alias.contains(translatedName)) {
        return true;
      }
      if (alias == canonicalName) {
        return true;
      }
      if (aliasCollapsed.isNotEmpty &&
          (normalizedName.replaceAll(' ', '').contains(aliasCollapsed) ||
              aliasCollapsed.contains(normalizedName.replaceAll(' ', '')))) {
        return true;
      }

      final aliasTokens = _tokenize(alias);
      if (aliasTokens.isNotEmpty) {
        final nameTokens = [
          ..._tokenize(normalizedName),
          ..._tokenize(translatedName),
        ];
        final matches = aliasTokens.every(
          (token) =>
              nameTokens.any((nt) => nt.contains(token)) ||
              normalizedName.contains(token),
        );
        if (matches) return true;
      }
    }
    return false;
  }

  List<String> _tokenize(String value) {
    return value
        .split(RegExp(r'[\s,_\-]+'))
        .map((e) => e.trim())
        .where((element) => element.isNotEmpty)
        .toList();
  }

  double _roundDouble(double value) {
    if (!value.isFinite) return 0;
    return (value * 100).roundToDouble() / 100.0;
  }

  // (ส่วนที่เหลือของ Class เหมือนเดิม)
  // ... _recordCookingHistory, getCookingHistory, _calculateTotalNutrition, etc. ...
  Future<void> _recordCookingHistory(
    RecipeModel recipe, {
    required int servingsMade,
    required List<UsedIngredient> usedIngredients,
    required List<HistoryIngredientPortion> ingredientPortions,
    NutritionInfo? recipeNutritionPerServing,
    required List<CookingStep> recipeStepsSnapshot,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final history = CookingHistory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        recipeId: recipe.id,
        recipeName: recipe.name,
        recipeCategory: recipe.category,
        cookedAt: DateTime.now(),
        servingsMade: servingsMade,
        usedIngredients: usedIngredients,
        totalNutrition: _calculateTotalNutrition(
          recipe.nutrition,
          servingsMade,
          recipe.servings,
        ),
        rating: 0,
        notes: '',
        userId: user.uid,
        recipeIngredientPortions: List<HistoryIngredientPortion>.from(
          ingredientPortions,
        ),
        recipeNutritionPerServing: recipeNutritionPerServing,
        recipeSteps: _cloneSteps(recipeStepsSnapshot),
      );

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cooking_history')
          .doc(history.id)
          .set({
            ...history.toFirestore(),
            'cooked_at': FieldValue.serverTimestamp(),
          });

      print('✅ Cooking history recorded');
    } catch (e) {
      print('❌ Error record history: $e');
    }
  }

  Future<List<CookingHistory>> getCookingHistory({int? limitDays}) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      Query query = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cooking_history')
          .orderBy('cooked_at', descending: true);

      if (limitDays != null) {
        final startDate = DateTime.now().subtract(Duration(days: limitDays));
        query = query.where('cooked_at', isGreaterThan: startDate);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map(
            (d) =>
                CookingHistory.fromFirestore(d.data() as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      print('❌ Error get history: $e');
      return [];
    }
  }

  NutritionInfo _calculateTotalNutrition(
    NutritionInfo perRecipe,
    int servingsMade,
    int originalServings,
  ) {
    final mul = servingsMade / (originalServings == 0 ? 1 : originalServings);
    return NutritionInfo(
      calories: perRecipe.calories * mul,
      protein: perRecipe.protein * mul,
      carbs: perRecipe.carbs * mul,
      fat: perRecipe.fat * mul,
      fiber: perRecipe.fiber * mul,
      sodium: perRecipe.sodium * mul,
    );
  }

  List<HistoryIngredientPortion> _snapshotIngredientPortions(
    RecipeModel recipe,
    int servings,
    Map<String, double>? manualRequiredAmounts,
    List<qty.ManualCustomIngredient>? manualCustomIngredients,
  ) {
    // Note: analyzeIngredientStatus might need to be async now if it
    // also starts using the new async unit conversion.
    // For now, assuming it uses a synchronous estimation.
    final statuses = qty.analyzeIngredientStatus(
      recipe,
      const [], // Assuming this is a list of available ingredients.
      servings: servings,
      manualRequiredAmounts: manualRequiredAmounts,
      manualCustomIngredients: manualCustomIngredients,
    );
    return statuses
        .map(
          (status) => HistoryIngredientPortion(
            name: status.name,
            amount: status.requiredAmount,
            unit: status.unit,
            canonicalAmount: status.canonicalRequiredAmount,
            canonicalUnit: status.canonicalUnit,
            isOptional: status.isOptional,
          ),
        )
        .toList();
  }

  List<CookingStep> _cloneSteps(List<CookingStep> steps) {
    return steps
        .map(
          (step) => CookingStep(
            stepNumber: step.stepNumber,
            instruction: step.instruction,
            timeMinutes: step.timeMinutes,
            imageUrl: step.imageUrl,
            tips: List<String>.from(step.tips),
          ),
        )
        .toList();
  }

  double _toDouble(dynamic v) =>
      (v is num) ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;

  static String _normalizeName(String v) => v
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[\(\)\[\]【】]'), '');

  double _scaledAmount(double base, int make, int baseServings) =>
      base * (make / (baseServings == 0 ? 1 : baseServings));
}

class _StockQuantity {
  final int quantity;
  final String unit;
  final double canonicalAmount;
  const _StockQuantity(this.quantity, this.unit, this.canonicalAmount);
}

class IngredientCheckResult {
  final bool isSufficient;
  final List<IngredientShortage> shortages;
  const IngredientCheckResult({
    required this.isSufficient,
    this.shortages = const [],
  });
}
