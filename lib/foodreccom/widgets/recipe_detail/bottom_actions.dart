//lib/foodreccom/widgets/recipe_detail/bottom_actions.dart
import 'package:flutter/material.dart';
import '../../models/recipe/recipe.dart';

class BottomActions extends StatelessWidget {
  final RecipeModel recipe;
  final int servings;
  final bool isStarting;
  final VoidCallback onStartCooking;

  const BottomActions({
    super.key,
    required this.recipe,
    required this.servings,
    required this.isStarting,
    required this.onStartCooking,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: isStarting ? null : onStartCooking,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[600],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: isStarting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.play_arrow),
          label: Text(
            isStarting ? 'กำลังเตรียม...' : 'เริ่มทำเมนูนี้',
          ),
        ),
      ),
    );
  }
}
