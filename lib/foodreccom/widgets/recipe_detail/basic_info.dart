//lib/foodreccom/widgets/recipe_detail/basic_info.dart
import 'package:flutter/material.dart';
import '../../models/recipe/recipe.dart';

class RecipeBasicInfo extends StatelessWidget {
  final RecipeModel recipe;
  const RecipeBasicInfo({super.key, required this.recipe});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInfo(Icons.schedule, '${recipe.totalTime} นาที', 'เวลารวม'),
          _buildInfo(Icons.restaurant, recipe.difficulty, 'ความยาก'),
          _buildInfo(Icons.category, recipe.category, 'ประเภท'),
        ],
      ),
    );
  }

  Widget _buildInfo(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey[600], size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}
