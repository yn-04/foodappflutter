//lib/foodreccom/widgets/recipe_card.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/recipe/recipe.dart';
import '../utils/recipe_image_helper.dart';
import '../constants/nutrition_thresholds.dart';
import '../providers/enhanced_recommendation_provider.dart';

class RecipeCard extends StatelessWidget {
  final RecipeModel recipe;
  final VoidCallback? onTap;
  final bool showSourceBadge; // ✅ เพิ่ม field
  final bool compact; // ✅ แสดงแบบย่อ (ใช้ใน Dashboard)

  const RecipeCard({
    super.key,
    required this.recipe,
    this.onTap,
    this.showSourceBadge = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EnhancedRecommendationProvider>();
    final displayServings = provider.getServingsOverride(recipe.id) ?? 1;
    final reasonText = _visibleReason(recipe.reason);
    final _FrequencyDisplay? frequencyDisplay = _deriveRecipeFrequency(recipe);
    final EdgeInsetsGeometry cardPadding = EdgeInsets.all(
      compact ? 12.0 : 14.0,
    );
    final double? compactImageHeight = compact ? 280 : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              if (recipe.displayImageUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: compactImageHeight != null
                      ? SizedBox(
                          height: compactImageHeight,
                          width: double.infinity,
                          child: _buildRecipeImage(),
                        )
                      : AspectRatio(
                          aspectRatio: 4 / 3,
                          child: _buildRecipeImage(),
                        ),
                ),
                SizedBox(height: compact ? 10 : 12),
              ],
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
                        if (frequencyDisplay != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: frequencyDisplay.color.shade100,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              frequencyDisplay.label,
                              style: TextStyle(
                                color: frequencyDisplay.color.shade700,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
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
                      '${recipe.matchScoreLabel}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Reason (limit lines to avoid overflow on small cards)
              if (!compact && reasonText != null)
                Text(
                  reasonText,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

              const SizedBox(height: 8),

              // Details (allow horizontal scroll for smaller cards)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
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
                      '$displayServings คน',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),

              // Nutrition Preview (skip on compact)
              if (!compact) ...[
                const SizedBox(height: 8),
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
              ],

              // Ingredients Used
              if (!compact && recipe.ingredients.isNotEmpty) ...[
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                const SizedBox(height: 6),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.orange[600],
                          fontSize: 12,
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

  Widget _buildRecipeImage() {
    return Image.network(
      recipe.displayImageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.network(
        RecipeImageHelper.defaultImage,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey[200],
          alignment: Alignment.center,
          child: const Icon(Icons.restaurant, color: Colors.grey),
        ),
      ),
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          color: Colors.grey[200],
          alignment: Alignment.center,
          child: const CircularProgressIndicator(strokeWidth: 2),
        );
      },
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

  String? _visibleReason(String? reason) {
    if (reason == null) return null;
    final trimmed = reason.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    const blocked = ['สูตรจาก', 'อ้างอิง', 'ai '];
    for (final token in blocked) {
      if (lower.startsWith(token)) return null;
    }
    return trimmed;
  }

  _FrequencyDisplay? _deriveRecipeFrequency(RecipeModel recipe) {
    final servings = recipe.servings <= 0 ? 1 : recipe.servings;
    if (servings <= 0) return null;
    final double? fat = recipe.nutrition.fat.isFinite
        ? recipe.nutrition.fat / servings
        : null;
    final double? sodium = recipe.nutrition.sodium.isFinite
        ? recipe.nutrition.sodium
        : null;
    final double? saltGrams = sodium != null ? (sodium / 1000) * 2.5 : null;
    final frequency = NutritionThresholds.frequencyFromValues(
      fat: fat,
      salt: saltGrams,
    );
    if (frequency == null) return null;
    return _FrequencyDisplay(
      label: _frequencyLabel(frequency),
      color: _frequencyColor(frequency),
    );
  }

  MaterialColor _frequencyColor(ConsumptionFrequency frequency) {
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

  String _frequencyLabel(ConsumptionFrequency frequency) {
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
}

class _FrequencyDisplay {
  final String label;
  final MaterialColor color;

  const _FrequencyDisplay({required this.label, required this.color});
}
