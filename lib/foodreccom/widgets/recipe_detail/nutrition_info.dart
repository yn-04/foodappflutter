//lib/foodreccom/widgets/recipe_detail/nutrition_info.dart
import 'package:flutter/material.dart';
import '../../models/recipe/recipe.dart';

class NutritionInfoSection extends StatelessWidget {
  final RecipeModel recipe;
  final int servings;

  const NutritionInfoSection({
    super.key,
    required this.recipe,
    required this.servings,
  });

  @override
  Widget build(BuildContext context) {
    final baseServings = recipe.servings == 0 ? servings : recipe.servings;
    final multiplier = servings / baseServings;
    final adjusted = NutritionInfo(
      calories: recipe.nutrition.calories * multiplier,
      protein: recipe.nutrition.protein * multiplier,
      carbs: recipe.nutrition.carbs * multiplier,
      fat: recipe.nutrition.fat * multiplier,
      fiber: recipe.nutrition.fiber * multiplier,
      sodium: recipe.nutrition.sodium * multiplier,
    );

    final tiles = [
      _NutritionCardData(
        emoji: '⚡',
        label: 'พลังงาน',
        value: '${adjusted.calories.toStringAsFixed(0)} kcal',
        background: const Color(0xFFFFF3CD),
      ),
      _NutritionCardData(
        emoji: '🥚',
        label: 'โปรตีน',
        value: '${adjusted.protein.toStringAsFixed(1)} g',
        background: const Color(0xFFFFE0CC),
      ),
      _NutritionCardData(
        emoji: '🍚',
        label: 'คาร์บ',
        value: '${adjusted.carbs.toStringAsFixed(1)} g',
        background: const Color(0xFFE5F3FF),
      ),
      _NutritionCardData(
        emoji: '🥑',
        label: 'ไขมัน',
        value: '${adjusted.fat.toStringAsFixed(1)} g',
        background: const Color(0xFFE7F9F3),
      ),
      _NutritionCardData(
        emoji: '🥦',
        label: 'ไฟเบอร์',
        value: '${adjusted.fiber.toStringAsFixed(1)} g',
        background: const Color(0xFFE9F7E9),
      ),
      _NutritionCardData(
        emoji: '🧂',
        label: 'โซเดียม',
        value: '${adjusted.sodium.toStringAsFixed(0)} mg',
        background: const Color(0xFFF6E9FA),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🥗 ข้อมูลโภชนาการ',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final spacing = 12.0;
            final cardWidth = width <= 0
                ? 0.0
                : (width - spacing) / 2; // two columns layout
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: tiles.map((tile) {
                return SizedBox(
                  width: cardWidth,
                  child: _NutritionCard(tile: tile),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _NutritionCardData {
  final String emoji;
  final String label;
  final String value;
  final Color background;

  const _NutritionCardData({
    required this.emoji,
    required this.label,
    required this.value,
    required this.background,
  });
}

class _NutritionCard extends StatelessWidget {
  final _NutritionCardData tile;

  const _NutritionCard({required this.tile});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tile.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tile.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 8),
          Text(
            tile.label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tile.value,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}
