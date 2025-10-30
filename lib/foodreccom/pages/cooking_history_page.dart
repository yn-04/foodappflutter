import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:my_app/common/measurement_constants.dart';
import 'package:my_app/common/smart_unit_converter.dart'
    as base_unit_converter;
import 'package:my_app/foodreccom/utils/ingredient_measure_utils.dart';

import '../models/cooking_history_model.dart';
import '../models/recipe/nutrition_info.dart';
import '../providers/enhanced_recommendation_provider.dart';
import '../utils/purchase_item_utils.dart';

final NumberFormat _metricFormatter = NumberFormat('#,##0.##', 'th_TH');
final NumberFormat _metricFormatterInt = NumberFormat('#,##0', 'th_TH');

class CookingHistoryPage extends StatelessWidget {
  const CookingHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'เมนูที่เคยทำ',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
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
          return ListView.builder(
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
                  const SizedBox(height: 12),
                  ...items.map((item) => _HistoryTile(
                        history: item,
                        onTap: () => _openHistoryDetail(context, item),
                      )),
                  const SizedBox(height: 24),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<MapEntry<String, List<CookingHistory>>> _groupByDate(
      List<CookingHistory> history) {
    final map = <String, List<CookingHistory>>{};
    for (final item in history) {
      final label = _formatThaiDate(item.cookedAt);
      map.putIfAbsent(label, () => []).add(item);
    }
    final entries = map.entries.toList();
    entries.sort((a, b) =>
        b.value.first.cookedAt.compareTo(a.value.first.cookedAt));
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
    return '${date.day} $month $buddhistYear';
  }

  String _formatIngredientAmount(num amount, String unit, String name) {
    final canonical = IngredientMeasureUtils.toCanonical(
      amount.toDouble(),
      unit,
      name,
    );

    if (canonical.unit == 'gram') {
      return _formatMass(canonical.amount);
    }

    if (canonical.unit == 'milliliter') {
      return _formatVolume(canonical.amount);
    }

    final gramsFallback = base_unit_converter.SmartUnitConverter.gramsFromPiece(
      amount.toDouble(),
      unit,
      name,
    );
    if (gramsFallback != null) {
      return _formatMass(gramsFallback);
    }

    final formatted = formatQuantityNumber(
      amount,
      unit: unit,
      ingredientName: name,
    );
    final trimmedUnit = unit.trim();
    if (trimmedUnit.isEmpty) return formatted;
    return '$formatted $trimmedUnit';
  }

  String _formatMass(double grams) {
    final safeValue = grams.isFinite ? grams : 0.0;
    if (safeValue <= 0) {
      return '0 กรัม';
    }

    if (safeValue >= MeasurementConstants.gramsPerKilogram) {
      final kilograms = safeValue / MeasurementConstants.gramsPerKilogram;
      return '${_formatNumberCeil(kilograms, decimals: 2)} กิโลกรัม';
    }

    return '${_formatNumberCeil(safeValue)} กรัม';
  }

  String _formatVolume(double milliliters) {
    final safeValue = milliliters.isFinite ? milliliters : 0.0;
    if (safeValue <= 0) {
      return '0 มิลลิลิตร';
    }

    if (safeValue >= MeasurementConstants.millilitersPerLiter) {
      final liters = safeValue / MeasurementConstants.millilitersPerLiter;
      return '${_formatNumberCeil(liters, decimals: 2)} ลิตร';
    }

    return '${_formatNumberCeil(safeValue)} มิลลิลิตร';
  }

  String _formatNumberCeil(double value, {int decimals = 0}) {
    if (!value.isFinite || value <= 0) return '0';
    final scale = math.pow(10, decimals).toDouble();
    final ceiled = (value * scale).ceilToDouble() / scale;
    if (decimals == 0) {
      return _metricFormatterInt.format(ceiled.round());
    }
    return _metricFormatter.format(ceiled);
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

  void _openHistoryDetail(BuildContext context, CookingHistory history) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CookingHistoryDetailPage(
          history: history,
          hasNutrition: _hasNutritionData(history.totalNutrition),
          formatDate: _formatThaiDate,
          formatIngredientAmount: _formatIngredientAmount,
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final CookingHistory history;
  final VoidCallback onTap;

  const _HistoryTile({
    required this.history,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: const Color(0xFFF7F1FF),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFFFEDD5),
          child: const Icon(Icons.restaurant, color: Color(0xFFFF8A00)),
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

class CookingHistoryDetailPage extends StatelessWidget {
  final CookingHistory history;
  final bool hasNutrition;
  final String Function(DateTime) formatDate;
  final String Function(num amount, String unit, String ingredientName)
      formatIngredientAmount;

  const CookingHistoryDetailPage({
    super.key,
    required this.history,
    required this.hasNutrition,
    required this.formatDate,
    required this.formatIngredientAmount,
  });

  @override
  Widget build(BuildContext context) {
    final recipePortions = history.recipeIngredientPortions;
    final totalNutrition = history.totalNutrition;
    final steps = history.recipeSteps;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'รายละเอียดเมนู',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFFFEDD5),
                    child:
                        const Icon(Icons.restaurant, color: Color(0xFFFF8A00)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          history.recipeName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatDate(history.cookedAt),
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
              const SizedBox(height: 20),
              if (recipePortions.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionTitle('ปริมาณตามสูตร'),
                const SizedBox(height: 8),
                ...recipePortions.map(
                  (portion) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(
                          width: 24,
                          child: Icon(Icons.kitchen_outlined,
                              size: 16, color: Colors.green),
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
                              const SizedBox(height: 2),
                              Text(
                                formatIngredientAmount(
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
              if (hasNutrition) ...[
                const SizedBox(height: 16),
                _sectionTitle('ข้อมูลโภชนาการ'),
                const SizedBox(height: 8),
                _nutritionRow('แคลอรี', totalNutrition.calories),
                _nutritionRow('โปรตีน (g)', totalNutrition.protein),
                _nutritionRow('คาร์บ (g)', totalNutrition.carbs),
                _nutritionRow('ไขมัน (g)', totalNutrition.fat),
                _nutritionRow('ไฟเบอร์ (g)', totalNutrition.fiber),
                _nutritionRow('โซเดียม (mg)', totalNutrition.sodium),
              ],
              if (steps.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionTitle('ขั้นตอนการทำ'),
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
                _sectionTitle('บันทึกเพิ่มเติม'),
                const SizedBox(height: 6),
                Text(history.notes!.trim()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.orange[800],
      ),
    );
  }

  Widget _nutritionRow(String label, double total) {
    const threshold = 0.01;
    if (total.abs() <= threshold) return const SizedBox.shrink();
    final valueText = _formatNutrition(total);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Text(
            valueText,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  String _formatNutrition(double value) {
    if ((value - value.roundToDouble()).abs() < 1e-3) {
      return value.round().toString();
    }
    return value.toStringAsFixed(1).replaceFirst(RegExp(r'\.?0+$'), '');
  }
}
