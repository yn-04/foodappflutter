import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/nutrition_thresholds.dart';
import '../../models/ingredient_model.dart';
import '../../models/recipe/recipe_model.dart';
import '../../providers/enhanced_recommendation_provider.dart';

class RecipeFrequencyNotice extends StatelessWidget {
  final RecipeModel recipe;

  const RecipeFrequencyNotice({super.key, required this.recipe});

  @override
  Widget build(BuildContext context) {
    final inventory =
        context.watch<EnhancedRecommendationProvider>().ingredients;
    final info = _evaluateFrequency(recipe, inventory);
    final frequency = info.frequency;
    if (frequency == null) return const SizedBox.shrink();

    final color = _colorForFrequency(frequency);
    final label = _labelForFrequency(frequency);
    final reasonText = info.reason?.trim();
    final fallbackReason = info.highlightedIngredients.isNotEmpty
        ? 'ข้อจำกัดจากวัตถุดิบ: ${info.highlightedIngredients.join(', ')}'
        : 'อ้างอิงจากข้อมูลโภชนาการของวัตถุดิบในคลังของคุณ';

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.shade50,
          border: Border.all(color: color.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.health_and_safety, color: color.shade600, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'คำแนะนำการบริโภค',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: color.shade100,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: color.shade700,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        reasonText != null && reasonText.isNotEmpty
                            ? reasonText
                            : fallbackReason,
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (info.highlightedIngredients.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'วัตถุดิบที่กำหนดความถี่:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color.shade700,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: info.highlightedIngredients
                    .map(
                      (name) => Chip(
                        label: Text(name),
                        backgroundColor: color.shade100,
                        labelStyle: TextStyle(
                          color: color.shade800,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _RecipeFrequencyInfo _evaluateFrequency(
    RecipeModel recipe,
    List<IngredientModel> inventory,
  ) {
    if (inventory.isEmpty || recipe.ingredients.isEmpty) {
      return const _RecipeFrequencyInfo();
    }
    final index = <String, IngredientModel>{};
    for (final ingredient in inventory) {
      final key = _normalizeName(ingredient.name);
      if (key.isEmpty || index.containsKey(key)) continue;
      index[key] = ingredient;
    }

    ConsumptionFrequency? selectedFrequency;
    String? selectedReason;
    final highlighted = <String>[];

    for (final ingredient in recipe.ingredients) {
      final key = _normalizeName(ingredient.name);
      if (key.isEmpty) continue;
      final inv = index[key];
      if (inv == null || inv.consumptionFrequency == null) continue;
      final freq = inv.consumptionFrequency!;
      if (selectedFrequency == null ||
          _frequencySeverity(freq) > _frequencySeverity(selectedFrequency)) {
        selectedFrequency = freq;
        selectedReason = inv.consumptionReason;
        highlighted
          ..clear()
          ..add(inv.name);
      } else if (_frequencySeverity(freq) ==
          _frequencySeverity(selectedFrequency)) {
        if (inv.consumptionReason != null &&
            (selectedReason?.trim().isEmpty ?? true)) {
          selectedReason = inv.consumptionReason;
        }
        highlighted.add(inv.name);
      }
    }

    return _RecipeFrequencyInfo(
      frequency: selectedFrequency,
      reason: selectedReason,
      highlightedIngredients: highlighted,
    );
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

  MaterialColor _colorForFrequency(ConsumptionFrequency frequency) {
    switch (frequency) {
      case ConsumptionFrequency.daily:
        return Colors.green;
      case ConsumptionFrequency.oncePerDay:
        return Colors.amber;
      case ConsumptionFrequency.weekly:
        return Colors.deepOrange;
      case ConsumptionFrequency.occasional:
        return Colors.red;
    }
  }

  String _labelForFrequency(ConsumptionFrequency frequency) {
    switch (frequency) {
      case ConsumptionFrequency.daily:
        return 'ทานได้ทุกวัน';
      case ConsumptionFrequency.oncePerDay:
        return 'วันละครั้ง';
      case ConsumptionFrequency.weekly:
        return 'สัปดาห์ละครั้ง';
      case ConsumptionFrequency.occasional:
        return 'ทานนานๆ ครั้ง';
    }
  }

  String _normalizeName(String value) => value.trim().toLowerCase();
}

class _RecipeFrequencyInfo {
  final ConsumptionFrequency? frequency;
  final String? reason;
  final List<String> highlightedIngredients;

  const _RecipeFrequencyInfo({
    this.frequency,
    this.reason,
    this.highlightedIngredients = const [],
  });
}
