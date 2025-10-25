import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cooking_history_model.dart';
import '../models/recipe/nutrition_info.dart';
import '../providers/enhanced_recommendation_provider.dart';
import '../utils/purchase_item_utils.dart';

class CookingHistoryPage extends StatelessWidget {
  const CookingHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'เมนูที่เคยทำ',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Consumer<EnhancedRecommendationProvider>(
        builder: (context, provider, child) {
          final history = [...provider.cookingHistory]
            ..sort((a, b) => b.cookedAt.compareTo(a.cookedAt));
          if (history.isEmpty) {
            return const Center(
              child: Text(
                'ยังไม่มีประวัติการทำเมนู\nลองเริ่มทำเมนูแรกกันเลย!',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            );
          }

          final grouped = _groupByDate(history);
          return RefreshIndicator(
            onRefresh: provider.loadCookingHistory,
            color: Colors.orange[600],
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: grouped.length,
              itemBuilder: (context, index) {
                final entry = grouped[index];
                final dateLabel = entry.key;
                final items = entry.value;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...items.map(
                      (item) => _HistoryTile(
                        history: item,
                        onTap: () => _showHistoryDetail(context, item),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  List<MapEntry<String, List<CookingHistory>>> _groupByDate(
    List<CookingHistory> history,
  ) {
    final map = <String, List<CookingHistory>>{};
    for (final item in history) {
      final label = _formatThaiDate(item.cookedAt);
      map.putIfAbsent(label, () => []).add(item);
    }
    final entries = map.entries.toList();
    entries.sort(
      (a, b) => b.value.first.cookedAt.compareTo(a.value.first.cookedAt),
    );
    return entries;
  }

  String _formatThaiDate(DateTime date) {
    const months = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    final month = months[date.month - 1];
    final buddhistYear = date.year + 543;
    return '${date.day} $month ${buddhistYear}';
  }

  String _formatIngredientAmount(num amount, String unit, String name) {
    final formatted = formatQuantityNumber(
      amount,
      unit: unit,
      ingredientName: name,
    );
    final trimmedUnit = unit.trim();
    if (trimmedUnit.isEmpty) return formatted;
    return '$formatted $trimmedUnit';
  }

  bool _hasNutritionData(NutritionInfo? info) {
    if (info == null) return false;
    const threshold = 0.01;
    return info.calories.abs() > threshold ||
        info.protein.abs() > threshold ||
        info.carbs.abs() > threshold ||
        info.fat.abs() > threshold ||
        info.fiber.abs() > threshold ||
        info.sodium.abs() > threshold;
  }

  Widget _nutritionRow({required String label, required double total}) {
    const threshold = 0.01;
    if (total.abs() <= threshold) return const SizedBox.shrink();

    final valueText = _formatNutritionValue(total);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          Text(
            valueText,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  String _formatNutritionValue(double value) {
    if ((value - value.roundToDouble()).abs() < 1e-3) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _showHistoryDetail(BuildContext context, CookingHistory history) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final ingredients = history.usedIngredients;
        final recipePortions = history.recipeIngredientPortions;
        final totalNutrition = history.totalNutrition;
        final steps = history.recipeSteps;
        final hasNutritionSection = _hasNutritionData(totalNutrition);
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(context).viewPadding.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_long, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        history.recipeName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      _formatThaiDate(history.cookedAt),
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'วัตถุดิบที่ใช้',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[800],
                  ),
                ),
                const SizedBox(height: 8),
                if (ingredients.isEmpty)
                  const Text(
                    'ไม่พบข้อมูลวัตถุดิบที่บันทึกไว้',
                    style: TextStyle(color: Colors.black54),
                  )
                else
                  ...ingredients.map(
                    (ing) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(
                            width: 24,
                            child: Icon(
                              Icons.check_circle,
                              size: 16,
                              color: Colors.orange,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${ing.name} • ${_formatIngredientAmount(ing.amount, ing.unit, ing.name)}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (recipePortions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'ปริมาณตามสูตร (จำนวนที่ใช้รอบนี้)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...recipePortions.map(
                    (portion) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(
                            width: 24,
                            child: Icon(
                              Icons.kitchen_outlined,
                              size: 16,
                              color: Colors.green,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  portion.isOptional
                                      ? '${portion.name} (ไม่บังคับ)'
                                      : portion.name,
                                  style: const TextStyle(fontSize: 14),
                                ),
                                Text(
                                  _formatIngredientAmount(
                                    portion.amount,
                                    portion.unit,
                                    portion.name,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (hasNutritionSection) ...[
                  const SizedBox(height: 16),
                  Text(
                    'ข้อมูลโภชนาการ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _nutritionRow(
                    label: 'แคลอรี',
                    total: totalNutrition.calories,
                  ),
                  _nutritionRow(
                    label: 'โปรตีน (g)',
                    total: totalNutrition.protein,
                  ),
                  _nutritionRow(
                    label: 'คาร์บ (g)',
                    total: totalNutrition.carbs,
                  ),
                  _nutritionRow(label: 'ไขมัน (g)', total: totalNutrition.fat),
                  _nutritionRow(
                    label: 'ไฟเบอร์ (g)',
                    total: totalNutrition.fiber,
                  ),
                  _nutritionRow(
                    label: 'โซเดียม (mg)',
                    total: totalNutrition.sodium,
                  ),
                ],
                if (steps.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'ขั้นตอนการทำ',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...steps.map(
                    (step) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.orange[200],
                                child: Text(
                                  '${step.stepNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  step.instruction,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                          if (step.timeMinutes > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.timer_outlined,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${step.timeMinutes} นาที',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (step.tips.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ...step.tips.map(
                              (tip) => Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.lightbulb_outline,
                                    size: 14,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      tip,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                if (history.notes?.trim().isNotEmpty ?? false) ...[
                  const SizedBox(height: 16),
                  Text(
                    'บันทึกเพิ่มเติม',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[800],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(history.notes!.trim()),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final CookingHistory history;
  final VoidCallback onTap;

  const _HistoryTile({required this.history, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: Colors.orange[100],
          child: const Icon(Icons.restaurant, color: Colors.orange),
        ),
        title: Text(
          history.recipeName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: history.notes?.trim().isNotEmpty == true
            ? Text(
                history.notes!.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
