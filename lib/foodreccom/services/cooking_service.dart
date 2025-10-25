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
import '../utils/smart_unit_converter.dart'; // 🚀 Import ตัวแปลงหน่วยตัวใหม่
import '../utils/ingredient_translator.dart';

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

  // ✅ ตรวจสอบก่อนทำอาหาร (เหมือนเดิม)
  Future<IngredientCheckResult> previewCooking(
    RecipeModel recipe,
    int servingsToMake, {
    Map<String, double>? manualRequiredAmounts,
  }) async {
    return _checkIngredientAvailability(
      recipe,
      servingsToMake,
      manualRequiredAmounts: manualRequiredAmounts,
    );
  }

  // ✅ เริ่มทำอาหาร (ปรับปรุงให้รองรับ async)
  Future<CookingResult> startCooking(
    RecipeModel recipe,
    int servingsToMake, {
    bool allowPartial = false,
    Map<String, double>? manualRequiredAmounts,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return const CookingResult(success: false);

    try {
      // การตรวจสอบวัตถุดิบตอนนี้เป็น async เต็มรูปแบบ
      final check = await _checkIngredientAvailability(
        recipe,
        servingsToMake,
        manualRequiredAmounts: manualRequiredAmounts,
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
      );

      final ingredientPortions = _snapshotIngredientPortions(
        recipe,
        servingsToMake,
        manualRequiredAmounts,
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

  // ⭐️ [ปรับปรุง] ตรวจสอบวัตถุดิบใน stock (ใช้ SmartUnitConverter ใหม่)
  Future<IngredientCheckResult> _checkIngredientAvailability(
    RecipeModel recipe,
    int servingsToMake, {
    Map<String, double>? manualRequiredAmounts,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return const IngredientCheckResult(isSufficient: false);

    final shortages = <IngredientShortage>[];

    // ใช้ Future.wait เพื่อให้การตรวจสอบวัตถุดิบแต่ละชนิดทำงานพร้อมกัน
    await Future.wait(
      recipe.ingredients.map((ing) async {
        final baseServings = recipe.servings == 0 ? 1 : recipe.servings;
        final requiredAmount = _scaledAmount(
          ing.numericAmount,
          servingsToMake,
          baseServings,
        );

        // ✅ [ใหม่] แปลงหน่วยสูตรอาหาร -> หน่วย Canonical (gram/ml) ผ่าน API
        final requiredCanonical =
            await SmartUnitConverter.convertRecipeUnitToInventoryUnit(
              ingredientName: ing.name,
              recipeAmount: requiredAmount,
              recipeUnit: ing.unit,
            );

        if (requiredCanonical == null) {
          print('⚠️ ไม่สามารถแปลงหน่วยสำหรับ ${ing.name} (${ing.unit}) ได้');
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
            requiredCanonical.unit,
          );
        }

        if (availableCanonicalAmount < requiredCanonical.amount) {
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

    return IngredientCheckResult(
      isSufficient: shortages.isEmpty,
      shortages: shortages,
    );
  }

  // ⭐️ [ปรับปรุง] ลดวัตถุดิบใน stock (ใช้ SmartUnitConverter ใหม่)
  Future<List<UsedIngredient>> _reduceIngredientStock(
    RecipeModel recipe,
    int servingsToMake, {
    bool allowPartial = false,
    Map<String, double>? manualRequiredAmounts,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final usedIngredients = <UsedIngredient>[];

    for (final ing in recipe.ingredients) {
      final baseServings = recipe.servings == 0 ? 1 : recipe.servings;
      final requiredAmount = _scaledAmount(
        ing.numericAmount,
        servingsToMake,
        baseServings,
      );

      // ✅ [ใหม่] แปลงหน่วยสูตรอาหาร -> หน่วย Canonical (gram/ml) ผ่าน API
      final requiredCanonical =
          await SmartUnitConverter.convertRecipeUnitToInventoryUnit(
            ingredientName: ing.name,
            recipeAmount: requiredAmount,
            recipeUnit: ing.unit,
          );

      if (requiredCanonical == null) {
        print(
          '⚠️ ไม่สามารถแปลงหน่วยสำหรับ ${ing.name} (${ing.unit}) เพื่อตัดสต็อกได้',
        );
        continue; // ข้ามไปถ้าแปลงหน่วยไม่ได้
      }

      // ดึงรายการวัตถุดิบทั้งหมดที่ชื่อตรงกัน (รวมกรณีชื่อคล้าย)
      final inventoryDocs = await _findInventoryDocs(user.uid, ing.name);
      double amountRemaining = requiredCanonical.amount;
      double consumedCanonical = 0;
      String? usedCategory;

      for (final doc in inventoryDocs) {
        if (amountRemaining <= 0) break;

        final data = doc.data();
        final currentQty = _toDouble(data['quantity']);
        final currentUnit = (data['unit'] ?? '').toString();

        final availableCanonical = _convertStockToCanonical(
          ing.name,
          currentQty,
          currentUnit,
          requiredCanonical.unit,
        );

        if (availableCanonical <= 0) continue;

        final deduction = math.min(amountRemaining, availableCanonical);
        if (deduction <= 0) continue;

        final remainingCanonical = availableCanonical - deduction;
        final stockUpdate = _canonicalToStockQuantity(
          ing.name,
          remainingCanonical,
          currentUnit,
          requiredCanonical.unit,
        );

        await doc.reference.update({
          'quantity': stockUpdate.quantity,
          'unit': stockUpdate.unit,
          'updated_at': FieldValue.serverTimestamp(),
        });

        consumedCanonical += deduction;
        amountRemaining -= deduction;
        usedCategory ??= (data['category'] ?? '').toString();
      }

      if (consumedCanonical > 0) {
        final usedUnit = _mapCanonicalUnitToDisplayUnit(requiredCanonical.unit);
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
    return usedIngredients;
  }

  // ------------------------------
  // 🔹 Helper Functions (ปรับปรุงเล็กน้อย)
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
      final rounded = grams.round();
      if (rounded == 0) {
        return _StockQuantity(0, StockConverter.UnitConverter.gram);
      }
      if (_isKilogramUnit(normalizedOriginal) &&
          rounded % MeasurementConstants.gramsPerKilogram == 0) {
        return _StockQuantity(
          rounded ~/ MeasurementConstants.gramsPerKilogram,
          StockConverter.UnitConverter.kilogram,
        );
      }
      return _StockQuantity(rounded, StockConverter.UnitConverter.gram);
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
      final rounded = milliliters.round();
      if (rounded == 0) {
        return _StockQuantity(0, StockConverter.UnitConverter.milliliter);
      }
      if (_isLiterUnit(normalizedOriginal) &&
          rounded % MeasurementConstants.millilitersPerLiter == 0) {
        return _StockQuantity(
          rounded ~/ MeasurementConstants.millilitersPerLiter,
          StockConverter.UnitConverter.liter,
        );
      }
      return _StockQuantity(rounded, StockConverter.UnitConverter.milliliter);
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
      return _StockQuantity(pieces.round(), resolvedUnit);
    }

    return _StockQuantity(
      safeAmount.round(),
      _mapCanonicalUnitToStockUnit(canonicalUnit),
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

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _findInventoryDocs(
    String userId,
    String ingredientName,
  ) async {
    final aliases = _buildNameAliases(ingredientName);
    final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>> results = {};
    final collection = _firestore
        .collection('users')
        .doc(userId)
        .collection('raw_materials');

    for (final alias in aliases) {
      final snapshot = await collection
          .where('name_key', isEqualTo: alias)
          .get();
      for (final doc in snapshot.docs) {
        results[doc.id] = doc;
      }
    }

    if (results.isNotEmpty) {
      return results.values.toList();
    }

    final fallbackSnapshot = await collection.get();
    for (final doc in fallbackSnapshot.docs) {
      if (_matchesAlias(doc.data(), aliases)) {
        results[doc.id] = doc;
      }
    }
    return results.values.toList();
  }

  Set<String> _buildNameAliases(String name) {
    final aliases = <String>{};
    final normalized = _normalizeName(name);
    aliases.add(normalized);

    final translated = _normalizeName(IngredientTranslator.translate(name));
    aliases.add(translated);

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
  ) {
    // Note: analyzeIngredientStatus might need to be async now if it
    // also starts using the new async unit conversion.
    // For now, assuming it uses a synchronous estimation.
    final statuses = qty.analyzeIngredientStatus(
      recipe,
      const [], // Assuming this is a list of available ingredients.
      servings: servings,
      manualRequiredAmounts: manualRequiredAmounts,
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

  String _normalizeName(String v) => v
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
  const _StockQuantity(this.quantity, this.unit);
}

class IngredientCheckResult {
  final bool isSufficient;
  final List<IngredientShortage> shortages;
  const IngredientCheckResult({
    required this.isSufficient,
    this.shortages = const [],
  });
}
