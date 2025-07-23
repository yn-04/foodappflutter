// lib/services/cooking_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/recipe_model.dart';
import '../models/cooking_history_model.dart';

class CookingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // เริ่มทำอาหาร - ลดสต็อกและบันทึกประวัติ
  Future<bool> startCooking(RecipeModel recipe, int servingsToMake) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      // 1. ตรวจสอบสต็อกก่อน
      final canCook = await _checkIngredientAvailability(
        recipe,
        servingsToMake,
      );
      if (!canCook) {
        throw Exception('วัตถุดิบไม่เพียงพอ');
      }

      // 2. ลดสต็อกวัตถุดิบ
      final usedIngredients = await _reduceIngredientStock(
        recipe,
        servingsToMake,
      );

      // 3. บันทึกประวัติการทำอาหาร
      await _recordCookingHistory(
        recipe,
        servingsToMade: servingsToMake,
        usedIngredients: usedIngredients,
      );

      return true;
    } catch (e) {
      print('Error starting cooking: $e');
      return false;
    }
  }

  // ตรวจสอบว่าวัตถุดิบเพียงพอไหม
  Future<bool> _checkIngredientAvailability(
    RecipeModel recipe,
    int servingsToMake,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      for (final recipeIngredient in recipe.ingredients) {
        final requiredAmount =
            recipeIngredient.amount * (servingsToMake / recipe.servings);

        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('raw_materials')
            .where('name', isEqualTo: recipeIngredient.name)
            .get();

        if (snapshot.docs.isEmpty) {
          print('Missing ingredient: ${recipeIngredient.name}');
          return false;
        }

        final availableAmount =
            snapshot.docs.first.data()['quantity']?.toDouble() ?? 0;
        if (availableAmount < requiredAmount) {
          print(
            'Not enough ${recipeIngredient.name}: need $requiredAmount, have $availableAmount',
          );
          return false;
        }
      }
      return true;
    } catch (e) {
      print('Error checking availability: $e');
      return false;
    }
  }

  // ลดสต็อกวัตถุดิบ
  Future<List<UsedIngredient>> _reduceIngredientStock(
    RecipeModel recipe,
    int servingsToMake,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    List<UsedIngredient> usedIngredients = [];

    try {
      for (final recipeIngredient in recipe.ingredients) {
        final requiredAmount =
            recipeIngredient.amount * (servingsToMake / recipe.servings);

        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('raw_materials')
            .where('name', isEqualTo: recipeIngredient.name)
            .get();

        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          final data = doc.data();
          final currentAmount = data['quantity']?.toDouble() ?? 0;
          final newAmount = currentAmount - requiredAmount;

          // อัปเดตสต็อก
          if (newAmount <= 0) {
            // ลบรายการถ้าหมด
            await doc.reference.delete();
          } else {
            // ลดจำนวน
            await doc.reference.update({
              'quantity': newAmount,
              'updated_at': DateTime.now().toIso8601String(),
            });
          }

          // บันทึกการใช้งาน
          usedIngredients.add(
            UsedIngredient(
              name: recipeIngredient.name,
              amount: requiredAmount,
              unit: recipeIngredient.unit,
              category: data['category'] ?? '',
              cost: _calculateIngredientCost(data, requiredAmount),
            ),
          );
        }
      }
      return usedIngredients;
    } catch (e) {
      print('Error reducing stock: $e');
      return [];
    }
  }

  double _calculateIngredientCost(
    Map<String, dynamic> ingredientData,
    double usedAmount,
  ) {
    final price = ingredientData['price']?.toDouble() ?? 0;
    final totalQuantity = ingredientData['quantity']?.toDouble() ?? 1;
    return (price / totalQuantity) * usedAmount;
  }

  // บันทึกประวัติการทำอาหาร
  Future<void> _recordCookingHistory(
    RecipeModel recipe, {
    required int servingsToMade,
    required List<UsedIngredient> usedIngredients,
    int rating = 0,
    String? notes,
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
        servingsMade: servingsToMade,
        usedIngredients: usedIngredients,
        totalNutrition: _calculateTotalNutrition(
          recipe.nutrition,
          servingsToMade,
          recipe.servings,
        ),
        rating: rating,
        notes: notes,
        userId: user.uid,
      );

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cooking_history')
          .doc(history.id)
          .set(history.toFirestore());

      print('✅ Cooking history recorded');
    } catch (e) {
      print('Error recording history: $e');
    }
  }

  NutritionInfo _calculateTotalNutrition(
    NutritionInfo perRecipe,
    int servingsMade,
    int originalServings,
  ) {
    final multiplier = servingsMade / originalServings;
    return NutritionInfo(
      calories: perRecipe.calories * multiplier,
      protein: perRecipe.protein * multiplier,
      carbs: perRecipe.carbs * multiplier,
      fat: perRecipe.fat * multiplier,
      fiber: perRecipe.fiber * multiplier,
      sodium: perRecipe.sodium * multiplier,
    );
  }

  // ดึงประวัติการทำอาหาร
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
        query = query.where(
          'cooked_at',
          isGreaterThan: startDate.toIso8601String(),
        );
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map(
            (doc) => CookingHistory.fromFirestore(
              doc.data() as Map<String, dynamic>,
            ),
          )
          .toList();
    } catch (e) {
      print('Error getting cooking history: $e');
      return [];
    }
  }

  // สถิติการใช้วัตถุดิบรายสัปดาห์
  Future<Map<String, Map<String, double>>> getWeeklyIngredientUsage() async {
    final user = _auth.currentUser;
    if (user == null) return {};

    try {
      final oneWeekAgo = DateTime.now().subtract(Duration(days: 7));

      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cooking_history')
          .where('cooked_at', isGreaterThan: oneWeekAgo.toIso8601String())
          .get();

      Map<String, Map<String, double>> categoryUsage = {};

      for (final doc in snapshot.docs) {
        final history = CookingHistory.fromFirestore(doc.data());

        for (final ingredient in history.usedIngredients) {
          final category = ingredient.category;

          if (!categoryUsage.containsKey(category)) {
            categoryUsage[category] = {
              'totalAmount': 0,
              'totalCost': 0,
              'itemCount': 0,
            };
          }

          categoryUsage[category]!['totalAmount'] =
              (categoryUsage[category]!['totalAmount']! + ingredient.amount);
          categoryUsage[category]!['totalCost'] =
              (categoryUsage[category]!['totalCost']! + ingredient.cost);
          categoryUsage[category]!['itemCount'] =
              (categoryUsage[category]!['itemCount']! + 1);
        }
      }

      return categoryUsage;
    } catch (e) {
      print('Error getting weekly usage: $e');
      return {};
    }
  }
}
