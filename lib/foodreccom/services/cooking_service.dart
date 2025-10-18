// lib/foodreccom/services/cooking_service.dart
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app/common/smart_unit_converter.dart'
    as piece_converter; // 🍳 สำหรับหน่วยหัว/ลูก/ฟอง
import '../models/cooking_history_model.dart';
import '../models/recipe/recipe_model.dart';
import '../models/recipe/nutrition_info.dart';
import '../models/recipe/used_ingredient.dart';
import '../models/recipe/cooking_step.dart';
import '../utils/purchase_item_utils.dart' as qty;
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

  // ✅ ตรวจสอบก่อนทำอาหาร
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

  // ✅ เริ่มทำอาหาร (ลด stock + บันทึกประวัติ)
  Future<CookingResult> startCooking(
    RecipeModel recipe,
    int servingsToMake, {
    bool allowPartial = false,
    Map<String, double>? manualRequiredAmounts,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return const CookingResult(success: false);

    try {
      final check = await _checkIngredientAvailability(
        recipe,
        servingsToMake,
        manualRequiredAmounts: manualRequiredAmounts,
      );

      if (!check.isSufficient && !allowPartial) {
        return CookingResult(success: false, shortages: check.shortages);
      }

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

  // ✅ ตรวจสอบวัตถุดิบใน stock
  Future<IngredientCheckResult> _checkIngredientAvailability(
    RecipeModel recipe,
    int servingsToMake, {
    Map<String, double>? manualRequiredAmounts,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return const IngredientCheckResult(isSufficient: false);

    try {
      final shortages = <IngredientShortage>[];

      for (final ing in recipe.ingredients) {
        final baseServings = recipe.servings == 0 ? 1 : recipe.servings;
        final required = _scaledAmount(
          ing.numericAmount,
          servingsToMake,
          baseServings,
        );

        // ✅ แปลงสูตรอาหาร → กรัม
        final requiredGrams = piece_converter.SmartUnitConverter.roundGrams(
          piece_converter.SmartUnitConverter.toGramsIfPiece(
            required,
            ing.unit,
            ing.name,
          ),
        );

        double availableGrams = 0;
        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('raw_materials')
            .where('name_key', isEqualTo: _normalizeName(ing.name))
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final quantity = _toDouble(data['quantity']);
          final rawUnit = (data['unit'] ?? '').toString();
          final unit = rawUnit.toLowerCase().trim();

          double stockGrams;
          if (unit.contains('กิโล') ||
              unit == 'kg' ||
              unit == 'kgs' ||
              unit == 'kg.' ||
              unit == 'kilogram' ||
              unit == 'kilograms' ||
              unit == 'กก' ||
              unit == 'กก.') {
            stockGrams = quantity * 1000;
          } else if (unit.contains('กรัม') ||
              unit == 'g' ||
              unit == 'g.' ||
              unit == 'gram' ||
              unit == 'grams' ||
              unit == 'gm' ||
              unit == 'gms' ||
              unit == 'กรัม.') {
            stockGrams = quantity;
          } else {
            stockGrams = piece_converter.SmartUnitConverter.toGramsIfPiece(
              quantity,
              rawUnit,
              ing.name,
            );
          }

          availableGrams +=
              piece_converter.SmartUnitConverter.roundGrams(stockGrams);
        }

        final roundedAvailable =
            piece_converter.SmartUnitConverter.roundGrams(availableGrams);

        if (roundedAvailable + 1e-6 < requiredGrams) {
          shortages.add(
            IngredientShortage(
              name: ing.name,
              requiredAmount: requiredGrams,
              availableAmount: roundedAvailable,
              unit: 'กรัม',
            ),
          );
        }
      }

      return IngredientCheckResult(
        isSufficient: shortages.isEmpty,
        shortages: shortages,
      );
    } catch (e) {
      print('❌ Error check availability: $e');
      return const IngredientCheckResult(isSufficient: false);
    }
  }

  // ✅ ลดวัตถุดิบใน stock (หน่วยเป็นกรัมเสมอ)
  Future<List<UsedIngredient>> _reduceIngredientStock(
    RecipeModel recipe,
    int servingsToMake, {
    bool allowPartial = false,
    Map<String, double>? manualRequiredAmounts,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final used = <UsedIngredient>[];

    try {
      for (final ing in recipe.ingredients) {
        final baseServings = recipe.servings == 0 ? 1 : recipe.servings;
        final required = _scaledAmount(
          ing.numericAmount,
          servingsToMake,
          baseServings,
        );

        // ✅ สูตรอาหารเป็นกรัม
        final requiredGrams = piece_converter.SmartUnitConverter.roundGrams(
          piece_converter.SmartUnitConverter.toGramsIfPiece(
            required,
            ing.unit,
            ing.name,
          ),
        );

        double remaining = requiredGrams;

        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('raw_materials')
            .where('name_key', isEqualTo: _normalizeName(ing.name))
            .get();

        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final qtyLeft = _toDouble(data['quantity']);
          final rawUnit = (data['unit'] ?? '').toString();
          final unit = rawUnit.toLowerCase().trim();

          // ✅ แปลงสต็อกเป็นกรัม พร้อมปัดเป็นจำนวนเต็ม
          double stockGrams;
          if (unit.contains('กิโล') ||
              unit == 'kg' ||
              unit == 'kgs' ||
              unit == 'kg.' ||
              unit == 'kilogram' ||
              unit == 'kilograms' ||
              unit == 'กก' ||
              unit == 'กก.') {
            stockGrams = qtyLeft * 1000;
          } else if (unit.contains('กรัม') ||
              unit == 'g' ||
              unit == 'g.' ||
              unit == 'gram' ||
              unit == 'grams' ||
              unit == 'gm' ||
              unit == 'gms' ||
              unit == 'กรัม.') {
            stockGrams = qtyLeft;
          } else {
            stockGrams = piece_converter.SmartUnitConverter.toGramsIfPiece(
              qtyLeft,
              rawUnit,
              ing.name,
            );
          }
          stockGrams = piece_converter.SmartUnitConverter.roundGrams(stockGrams);

          if (stockGrams > 0) {
            final usedAmt = math.min(remaining, stockGrams);
            final usedRounded =
                piece_converter.SmartUnitConverter.roundGrams(usedAmt);
            final newStock = piece_converter.SmartUnitConverter.roundGrams(
              stockGrams - usedRounded,
            );
            remaining = math.max(0, remaining - usedRounded);

            // ✅ เก็บกลับเป็นกรัมเสมอ
            final double newQty = newStock;
            const String newUnit = 'กรัม';

            await doc.reference.update({
              'quantity': newQty,
              'unit': newUnit,
              'updated_at': FieldValue.serverTimestamp(),
            });

            used.add(
              UsedIngredient(
                name: ing.name,
                amount: usedRounded,
                unit: 'กรัม',
                category: data['category'] ?? '',
                cost: 0,
              ),
            );

            if (remaining <= 0) break;
          }
        }
      }
    } catch (e) {
      print('❌ Error reduce stock: $e');
    }
    return used;
  }

  // ✅ บันทึกประวัติการทำอาหาร
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

  // ✅ ดึงประวัติการทำอาหาร
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

  // ✅ คำนวณโภชนาการรวม
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

  // ------------------------------
  // 🔹 Helper Functions
  // ------------------------------
  List<HistoryIngredientPortion> _snapshotIngredientPortions(
    RecipeModel recipe,
    int servings,
    Map<String, double>? manualRequiredAmounts,
  ) {
    final statuses = qty.analyzeIngredientStatus(
      recipe,
      const [],
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

class IngredientCheckResult {
  final bool isSufficient;
  final List<IngredientShortage> shortages;
  const IngredientCheckResult({
    required this.isSufficient,
    this.shortages = const [],
  });
}
