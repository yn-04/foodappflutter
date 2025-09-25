//lib/foodreccom/widgets/recipe_detail/ingredients_list.dart
import 'package:flutter/material.dart';
import '../../models/recipe/recipe.dart';

class IngredientsList extends StatelessWidget {
  final RecipeModel recipe;
  final int servings;
  const IngredientsList({
    super.key,
    required this.recipe,
    required this.servings,
  });

  @override
  Widget build(BuildContext context) {
    final multiplier = servings / recipe.servings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: recipe.ingredients.map((ingredient) {
        final adjusted = ingredient.amount * multiplier;
        return ListTile(
          leading: const Icon(Icons.check_circle, color: Colors.green),
          title: Text(ingredient.name),
          trailing: Text(
            '${adjusted.toStringAsFixed(1)} ${ingredient.unit}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      }).toList(),
    );
  }
}
