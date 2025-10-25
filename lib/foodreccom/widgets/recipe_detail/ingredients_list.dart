//lib/foodreccom/widgets/recipe_detail/ingredients_list.dart
import 'package:flutter/material.dart';
import '../../models/recipe/recipe.dart';
import '../../utils/purchase_item_utils.dart';

class IngredientsList extends StatelessWidget {
  final RecipeModel recipe;
  final int servings;
  final Map<String, double>? manualRequiredAmounts;
  const IngredientsList({
    super.key,
    required this.recipe,
    required this.servings,
    this.manualRequiredAmounts,
  });

  @override
  Widget build(BuildContext context) {
    // ใช้ตัวช่วยเดียวกับฝั่ง "วัตถุดิบที่ต้องซื้อ" เพื่อให้หน่วยและปริมาณสอดคล้องกัน
    final statuses = analyzeIngredientStatus(
      recipe,
      const [],
      servings: servings,
      manualRequiredAmounts: manualRequiredAmounts,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'ปริมาณวัตถุดิบ',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        ...statuses.map((st) {
          final display = formatQuantityNumber(
            st.requiredAmount,
            unit: st.unit,
            ingredientName: st.name,
          );
          return ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text(st.name),
            trailing: Text(
              '$display ${st.unit}'.trim(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }).toList(),
      ],
    );
  }
}
