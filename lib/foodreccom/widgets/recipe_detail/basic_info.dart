//lib/foodreccom/widgets/recipe_detail/basic_info.dart
import 'package:flutter/material.dart';
import '../../models/recipe/recipe.dart';

class RecipeBasicInfo extends StatelessWidget {
  final RecipeModel recipe;
  const RecipeBasicInfo({super.key, required this.recipe});

  @override
  Widget build(BuildContext context) {
    final cuisine = _resolveCuisine(recipe);
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
          _buildInfo(Icons.public, cuisine, 'สัญชาติ'),
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

  String _resolveCuisine(RecipeModel recipe) {
    const cuisineMap = {
      'thai': 'ไทย',
      'ไทย': 'ไทย',
      'chinese': 'จีน',
      'จีน': 'จีน',
      'japanese': 'ญี่ปุ่น',
      'ญี่ปุ่น': 'ญี่ปุ่น',
      'korean': 'เกาหลี',
      'เกาหลี': 'เกาหลี',
      'vietnamese': 'เวียดนาม',
      'เวียดนาม': 'เวียดนาม',
      'indian': 'อินเดีย',
      'อินเดีย': 'อินเดีย',
      'italian': 'อิตาเลียน',
      'อิตาเลียน': 'อิตาเลียน',
      'mexican': 'เม็กซิกัน',
      'เม็กซิกัน': 'เม็กซิกัน',
      'american': 'อเมริกัน',
      'อเมริกัน': 'อเมริกัน',
      'french': 'ฝรั่งเศส',
      'ฝรั่งเศส': 'ฝรั่งเศส',
      'spanish': 'สเปน',
      'สเปน': 'สเปน',
      'german': 'เยอรมัน',
      'เยอรมัน': 'เยอรมัน',
      'british': 'อังกฤษ',
      'อังกฤษ': 'อังกฤษ',
      'asian': 'เอเชีย',
      'เอเชีย': 'เอเชีย',
      'mediterranean': 'เมดิเตอร์เรเนียน',
      'เมดิเตอร์เรเนียน': 'เมดิเตอร์เรเนียน',
    };

    for (final tag in recipe.tags) {
      final key = tag.trim().toLowerCase();
      final value = cuisineMap[key];
      if (value != null) {
        return value;
      }
    }
    // fallback: try category if it looks like a cuisine
    final categoryKey = recipe.category.trim().toLowerCase();
    final fromCategory = cuisineMap[categoryKey];
    return fromCategory ?? recipe.category;
  }
}
