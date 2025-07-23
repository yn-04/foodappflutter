// lib/widgets/recipe_card.dart
import 'package:flutter/material.dart';
import '../models/recipe_model.dart';

class RecipeCard extends StatelessWidget {
  final RecipeModel recipe;
  final VoidCallback? onTap;

  const RecipeCard({super.key, required this.recipe, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recipe.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        if (recipe.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            recipe.description,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: recipe.scoreColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${recipe.matchScore}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Reason
              Text(
                recipe.reason,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),

              const SizedBox(height: 12),

              // Details
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${recipe.totalTime} นาที',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.restaurant, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    recipe.difficulty,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.people, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${recipe.servings} คน',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ),

              // Nutrition Preview
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNutritionItem(
                      '🔥',
                      '${recipe.caloriesPerServing.toStringAsFixed(0)}',
                      'แคลอรี',
                    ),
                    _buildNutritionItem(
                      '🥩',
                      '${(recipe.nutrition.protein / recipe.servings).toStringAsFixed(1)}g',
                      'โปรตีน',
                    ),
                    _buildNutritionItem(
                      '🍞',
                      '${(recipe.nutrition.carbs / recipe.servings).toStringAsFixed(1)}g',
                      'คาร์บ',
                    ),
                  ],
                ),
              ),

              // Ingredients Used
              if (recipe.ingredients.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Colors.green[600],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'ใช้: ${recipe.ingredientsUsed.take(3).join(', ')}${recipe.ingredientsUsed.length > 3 ? '...' : ''}',
                        style: TextStyle(
                          color: Colors.green[600],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              // Missing Ingredients
              if (recipe.missingIngredients.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shopping_cart,
                      size: 16,
                      color: Colors.orange[600],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'ต้องซื้อ: ${recipe.missingIngredients.take(2).join(', ')}${recipe.missingIngredients.length > 2 ? '...' : ''}',
                        style: TextStyle(
                          color: Colors.orange[600],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              // Source Reference
              if (recipe.source != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.book, size: 14, color: Colors.blue[600]),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'อ้างอิง: ${recipe.source}',
                        style: TextStyle(
                          color: Colors.blue[600],
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNutritionItem(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }
}
