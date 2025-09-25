//lib/foodreccom/widgets/recipe_detail/cooking_steps.dart
import 'package:flutter/material.dart';
import '../../models/recipe/recipe.dart';

class CookingStepsSection extends StatelessWidget {
  final List<CookingStep> steps;
  const CookingStepsSection({super.key, required this.steps});

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '👩‍🍳 ขั้นตอนการทำ',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...steps.asMap().entries.map((entry) {
          final index = entry.key + 1;
          final step = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$index. ${step.instruction}',
                  style: const TextStyle(fontSize: 16),
                ),
                if (step.timeMinutes > 0)
                  Text(
                    '⏱ ${step.timeMinutes} นาที',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                if (step.tips.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...step.tips.map(
                    (tip) => Row(
                      children: [
                        const Icon(
                          Icons.lightbulb,
                          size: 16,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tip,
                            style: TextStyle(
                              color: Colors.amber[800],
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}
