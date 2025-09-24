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
    final multiplier = servings / recipe.servings;
    final adjusted = NutritionInfo(
      calories: recipe.nutrition.calories * multiplier,
      protein: recipe.nutrition.protein * multiplier,
      carbs: recipe.nutrition.carbs * multiplier,
      fat: recipe.nutrition.fat * multiplier,
      fiber: recipe.nutrition.fiber * multiplier,
      sodium: recipe.nutrition.sodium * multiplier,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🥗 ข้อมูลโภชนาการ',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green[50]!, Colors.blue[50]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildItem(
                    '🔥',
                    '${adjusted.calories.toStringAsFixed(0)} kcal',
                  ),
                  _buildItem('🥩', '${adjusted.protein.toStringAsFixed(1)} g'),
                  _buildItem('🍞', '${adjusted.carbs.toStringAsFixed(1)} g'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildItem('🧈', '${adjusted.fat.toStringAsFixed(1)} g'),
                  _buildItem('🌾', '${adjusted.fiber.toStringAsFixed(1)} g'),
                  _buildItem('🧂', '${adjusted.sodium.toStringAsFixed(0)} mg'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildItem(String emoji, String value) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ],
    );
  }
}
