// lib/foodreccom/services/ingredient_analytics_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/ingredient_model.dart';
import '../models/cooking_history_model.dart';
import '../utils/date_utils.dart';
import '../models/recipe/used_ingredient.dart';

class IngredientAnalyticsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// อัพเดท usage statistics หลังจากทำอาหาร
  Future<void> updateIngredientUsageStats(
    List<UsedIngredient> usedIngredients,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final batch = _firestore.batch();

      for (final usedIngredient in usedIngredients) {
        final snapshot = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('raw_materials')
            .where('name', isEqualTo: usedIngredient.name)
            .get();

        if (snapshot.docs.isNotEmpty) {
          final doc = snapshot.docs.first;
          final data = doc.data();

          final currentUsageCount = data['usage_count'] ?? 0;
          final currentUtilizationRate = (data['utilization_rate'] ?? 0.0)
              .toDouble();
          final totalQuantity = data['total_added'] ?? data['quantity'] ?? 1;

          final newUtilizationRate = _calculateNewUtilizationRate(
            currentUtilizationRate,
            usedIngredient.amount,
            (totalQuantity as num).toDouble(),
          );

          batch.update(doc.reference, {
            'usage_count': currentUsageCount + 1,
            'last_used_date': DateTime.now().toIso8601String(),
            'utilization_rate': newUtilizationRate,
            'updated_at': DateTime.now().toIso8601String(),
          });
        }
      }

      await batch.commit();
      debugPrint('✅ Updated ingredient usage statistics');
    } catch (e) {
      debugPrint('Error updating usage stats: $e');
    }
  }

  /// คำนวณ utilization rate ใหม่
  double _calculateNewUtilizationRate(
    double currentRate,
    double usedAmount,
    double totalQuantity,
  ) {
    final usageRatio = usedAmount / totalQuantity;
    return ((currentRate * 0.8) + (usageRatio * 0.2)).clamp(0.0, 1.0);
  }

  /// วิเคราะห์แนวโน้มการใช้วัตถุดิบ (30 วันล่าสุด)
  Future<Map<String, dynamic>> analyzeIngredientTrends() async {
    final user = _auth.currentUser;
    if (user == null) return {};

    try {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

      final historySnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cooking_history')
          .where(
            'cooked_at',
            isGreaterThan: thirtyDaysAgo,
          ) // ✅ ใช้ DateTime ตรง ๆ
          .get();

      final ingredientUsage = <String, Map<String, dynamic>>{};
      final categoryUsage = <String, int>{};
      double totalCost = 0;

      for (final doc in historySnapshot.docs) {
        final history = CookingHistory.fromFirestore(doc.data());

        for (final ingredient in history.usedIngredients) {
          ingredientUsage.putIfAbsent(ingredient.name, () {
            return {
              'total_used': 0.0,
              'usage_count': 0,
              'total_cost': 0.0,
              'category': ingredient.category,
              'last_used': history.cookedAt,
            };
          });

          ingredientUsage[ingredient.name]!['total_used'] += ingredient.amount;
          ingredientUsage[ingredient.name]!['usage_count'] += 1;
          ingredientUsage[ingredient.name]!['total_cost'] += ingredient.cost;

          if (history.cookedAt.isAfter(
            ingredientUsage[ingredient.name]!['last_used'],
          )) {
            ingredientUsage[ingredient.name]!['last_used'] = history.cookedAt;
          }

          categoryUsage[ingredient.category] =
              (categoryUsage[ingredient.category] ?? 0) + 1;
          totalCost += ingredient.cost;
        }
      }

      final mostUsed = ingredientUsage.entries.toList()
        ..sort(
          (a, b) => b.value['usage_count'].compareTo(a.value['usage_count']),
        );

      final currentIngredients = await _getCurrentIngredients();
      final underutilized = currentIngredients.where((ing) {
        return !ingredientUsage.containsKey(ing.name) ||
            ingredientUsage[ing.name]!['usage_count'] < 2;
      }).toList();

      return {
        'total_recipes_cooked': historySnapshot.docs.length,
        'total_cost': totalCost,
        'most_used_ingredients': mostUsed.take(5).map((e) {
          return {
            'name': e.key,
            'usage_count': e.value['usage_count'],
            'total_cost': e.value['total_cost'],
          };
        }).toList(),
        'underutilized_ingredients': underutilized.map((ing) {
          return {
            'name': ing.name,
            'quantity': ing.quantity,
            'days_since_added': DateTime.now().difference(ing.addedDate).inDays,
            'estimated_value': ing.price ?? 0,
          };
        }).toList(),
        'category_preference': categoryUsage.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)),
        'waste_risk_items': underutilized.where((ing) => ing.isNearExpiry).map((
          ing,
        ) {
          return {
            'name': ing.name,
            'days_to_expiry': ing.daysToExpiry,
            'estimated_loss': ing.price ?? 0,
          };
        }).toList(),
      };
    } catch (e) {
      debugPrint('Error analyzing trends: $e');
      return {};
    }
  }

  /// แนะนำการจัดการสต็อก
  Future<Map<String, List<String>>> getStockManagementSuggestions() async {
    final trends = await analyzeIngredientTrends();

    final suggestions = <String, List<String>>{
      'buy_more': [],
      'use_urgent': [],
      'avoid_waste': [],
      'cost_optimization': [],
    };

    try {
      // 🛒 วัตถุดิบที่ใช้บ่อย → ซื้อเพิ่ม
      final mostUsed = trends['most_used_ingredients'] as List? ?? [];
      for (final item in mostUsed.take(3)) {
        suggestions['buy_more']!.add(
          'ซื้อ ${item['name']} เพิ่ม - ใช้ ${item['usage_count']} ครั้งในเดือนนี้',
        );
      }

      // ⚠️ วัตถุดิบเสี่ยงหมดอายุ → ใช้ด่วน
      final wasteRisk = trends['waste_risk_items'] as List? ?? [];
      for (final item in wasteRisk) {
        suggestions['use_urgent']!.add(
          '${item['name']} หมดอายุใน ${item['days_to_expiry']} วัน',
        );
      }

      // 🚮 วัตถุดิบที่ไม่ค่อยใช้ → ระวังเสียทิ้ง
      final underutilized = trends['underutilized_ingredients'] as List? ?? [];
      for (final item in underutilized.take(3)) {
        suggestions['avoid_waste']!.add(
          '${item['name']} ไม่ได้ใช้มา ${item['days_since_added']} วัน',
        );
      }

      // 💰 ประหยัดต้นทุน
      final totalCost = trends['total_cost'] ?? 0;
      if (totalCost > 1000) {
        suggestions['cost_optimization']!.add(
          'ใช้จ่ายวัตถุดิบ ${totalCost.toStringAsFixed(0)} บาท/เดือน - ควรวางแผนเมนู',
        );
      }
    } catch (e) {
      debugPrint('Error generating stock suggestions: $e');
    }

    return suggestions;
  }

  /// สร้างรายงานการใช้วัตถุดิบ
  Future<String> generateUsageReport() async {
    final trends = await analyzeIngredientTrends();
    final suggestions = await getStockManagementSuggestions();

    final report = StringBuffer();
    report.writeln('📊 รายงานการใช้วัตถุดิบ (30 วันล่าสุด)');
    report.writeln('=' * 40);

    report.writeln('🍳 ทำอาหาร: ${trends['total_recipes_cooked']} เมนู');
    report.writeln(
      '💰 ใช้จ่าย: ${(trends['total_cost'] as double).toStringAsFixed(0)} บาท',
    );
    report.writeln('');

    report.writeln('⭐ วัตถุดิบที่ใช้บ่อย:');
    final mostUsed = trends['most_used_ingredients'] as List;
    for (final item in mostUsed.take(5)) {
      report.writeln('- ${item['name']}: ${item['usage_count']} ครั้ง');
    }
    report.writeln('');

    report.writeln('⚠️ วัตถุดิบที่ต้องใช้ด่วน:');
    for (final suggestion in suggestions['use_urgent']!) {
      report.writeln('- $suggestion');
    }
    report.writeln('');

    report.writeln('💡 คำแนะนำเพิ่มเติม:');
    for (final category in suggestions.keys) {
      for (final suggestion in suggestions[category]!) {
        report.writeln('- $suggestion');
      }
    }

    return report.toString();
  }

  /// ดึงวัตถุดิบปัจจุบันจาก Firestore
  Future<List<IngredientModel>> _getCurrentIngredients() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .get();

      return snapshot.docs
          .map((doc) => IngredientModel.fromFirestore(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('Error getting current ingredients: $e');
      return [];
    }
  }
}
