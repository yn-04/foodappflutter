import '../models/dri_targets.dart';
import '../models/ingredient_model.dart';
import '../models/meal_plan.dart';
import '../models/recipe/recipe_model.dart';

class MealPlanService {
  static const int _maxRepeatsPerWeek = 3;

  /// Generate a weekly plan that blends pantry usage, DRI targets, and menu variety.
  static MealPlan generateWeeklyPlan({
    required List<IngredientModel> ingredients,
    required List<RecipeModel> candidates,
    int days = 7,
    int mealsPerDay = 1,
    int servingsPerMeal = 1,
    DriTargets? userDri,
  }) {
    if (candidates.isEmpty) {
      return MealPlan(days: const [], generatedAt: DateTime.now());
    }

    final today = DateTime.now();
    final totalMeals = days * mealsPerDay;
    final uniqueRecipes = candidates.map((r) => r.id).toSet().length;
    final canEnforceRepeatLimit =
        uniqueRecipes * _maxRepeatsPerWeek >= totalMeals;
    final repeatLimit = canEnforceRepeatLimit ? _maxRepeatsPerWeek : null;

    final ratios = _deriveMealRatios(mealsPerDay);
    final perMealTargets = _buildPerMealTargets(userDri, mealsPerDay, ratios);
    final inventoryContext = _InventoryContext.fromIngredients(ingredients);

    final baseline = candidates
        .map(
          (recipe) => _RecipeScoreData(
            recipe: recipe,
            baseScore: _inventoryScore(recipe, inventoryContext),
          ),
        )
        .toList()
      ..sort((a, b) => b.baseScore.compareTo(a.baseScore));

    final appearanceCount = <String, int>{};
    final daysOut = <MealPlanDay>[];

    for (int dayIndex = 0; dayIndex < days; dayIndex++) {
      final date = DateTime(today.year, today.month, today.day)
          .add(Duration(days: dayIndex));
      final dayMeals = <MealPlanEntry>[];
      final dayUsedIds = <String>{};

      for (int mealIndex = 0; mealIndex < mealsPerDay; mealIndex++) {
        final selection = _selectRecipeForSlot(
          baseline: baseline,
          mealIndex: mealIndex,
          perMealTargets: perMealTargets,
          appearanceCount: appearanceCount,
          dayUsedIds: dayUsedIds,
          repeatLimit: repeatLimit,
          allowRepeatOverflow: !canEnforceRepeatLimit,
          servingsPerMeal: servingsPerMeal,
        );

        final picked = selection ??
            _selectRecipeForSlot(
              baseline: baseline,
              mealIndex: mealIndex,
              perMealTargets: perMealTargets,
              appearanceCount: appearanceCount,
              dayUsedIds: dayUsedIds,
              repeatLimit: null,
              allowRepeatOverflow: true,
              servingsPerMeal: servingsPerMeal,
            );
        if (picked == null) break;

        dayMeals.add(
          MealPlanEntry(
            date: date,
            recipe: picked.recipe,
            servings: servingsPerMeal,
            score: picked.score.round(),
          ),
        );
        dayUsedIds.add(picked.recipe.id);
        appearanceCount.update(
          picked.recipe.id,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }

      daysOut.add(MealPlanDay(date: date, meals: dayMeals));
    }

    return MealPlan(days: daysOut, generatedAt: DateTime.now());
  }

  static List<double> _deriveMealRatios(int mealsPerDay) {
    if (mealsPerDay <= 0) return const [1];
    if (mealsPerDay == 3) {
      return const [0.3, 0.4, 0.3];
    }
    final ratio = 1 / mealsPerDay;
    return List<double>.filled(mealsPerDay, ratio);
  }

  static List<_PerMealTargets> _buildPerMealTargets(
    DriTargets? dri,
    int mealsPerDay,
    List<double> ratios,
  ) {
    final defaultEnergy = 2000.0;
    final energy = dri?.energyKcal ?? defaultEnergy;
    final carbMin =
        dri?.carbMinG ?? (defaultEnergy * 0.45) / 4.0;
    final carbMax =
        dri?.carbMaxG ?? (defaultEnergy * 0.6) / 4.0;
    final fatMin =
        dri?.fatMinG ?? (defaultEnergy * 0.25) / 9.0;
    final fatMax =
        dri?.fatMaxG ?? (defaultEnergy * 0.35) / 9.0;
    final protein =
        dri?.proteinG ?? (defaultEnergy * 0.18) / 4.0;
    final sodium = dri?.sodiumMaxMg ?? 2000.0;

    final targets = <_PerMealTargets>[];
    for (int i = 0; i < mealsPerDay; i++) {
      final ratio = ratios[i];
      targets.add(
        _PerMealTargets(
          energy: energy * ratio,
          carbMin: carbMin * ratio,
          carbMax: carbMax * ratio,
          fatMin: fatMin * ratio,
          fatMax: fatMax * ratio,
          proteinMin: protein * ratio,
          sodiumMax: sodium * ratio,
        ),
      );
    }
    return targets;
  }

  static _SelectionResult? _selectRecipeForSlot({
    required List<_RecipeScoreData> baseline,
    required int mealIndex,
    required List<_PerMealTargets> perMealTargets,
    required Map<String, int> appearanceCount,
    required Set<String> dayUsedIds,
    required int? repeatLimit,
    required bool allowRepeatOverflow,
    required int servingsPerMeal,
  }) {
    if (baseline.isEmpty) return null;

    _SelectionResult? bestEligible;
    _SelectionResult? bestSameDay;
    _SelectionResult? bestOverflow;

    for (final candidate in baseline) {
      final id = candidate.recipe.id;
      final alreadyUsed = appearanceCount[id] ?? 0;
      final exceedsLimit =
          repeatLimit != null && alreadyUsed >= repeatLimit;
      final sameDayDuplicate = dayUsedIds.contains(id);

      final score = _computeSlotScore(
        data: candidate,
        mealTargets: perMealTargets[mealIndex % perMealTargets.length],
        servingsPerMeal: servingsPerMeal,
        alreadyUsedCount: alreadyUsed,
        sameDayDuplicate: sameDayDuplicate,
      );

      if (exceedsLimit) {
        if (allowRepeatOverflow) {
          if (bestOverflow == null || score > bestOverflow.score) {
            bestOverflow = _SelectionResult(recipe: candidate.recipe, score: score);
          }
        }
        continue;
      }

      if (sameDayDuplicate) {
        if (bestSameDay == null || score > bestSameDay.score) {
          bestSameDay = _SelectionResult(recipe: candidate.recipe, score: score);
        }
        continue;
      }

      if (bestEligible == null || score > bestEligible.score) {
        bestEligible = _SelectionResult(recipe: candidate.recipe, score: score);
      }
    }

    return bestEligible ?? bestSameDay ?? bestOverflow;
  }

  static double _computeSlotScore({
    required _RecipeScoreData data,
    required _PerMealTargets mealTargets,
    required int servingsPerMeal,
    required int alreadyUsedCount,
    required bool sameDayDuplicate,
  }) {
    final nutritionScore = _nutritionMatchScore(
      recipe: data.recipe,
      mealTargets: mealTargets,
      servingsPerMeal: servingsPerMeal,
    );
    final repeatPenalty = alreadyUsedCount * 35.0;
    final sameDayPenalty = sameDayDuplicate ? 40.0 : 0.0;
    return data.baseScore + nutritionScore - repeatPenalty - sameDayPenalty;
  }

  static double _nutritionMatchScore({
    required RecipeModel recipe,
    required _PerMealTargets mealTargets,
    required int servingsPerMeal,
  }) {
    final baseServings = recipe.servings == 0 ? 1 : recipe.servings;
    final multiplier = servingsPerMeal / baseServings;
    final nutrition = recipe.nutrition;
    final calories = nutrition.calories * multiplier;
    final protein = nutrition.protein * multiplier;
    final carbs = nutrition.carbs * multiplier;
    final fat = nutrition.fat * multiplier;
    final sodium = nutrition.sodium * multiplier;

    double weightedScore = 0;
    double weightSum = 0;

    void accumulate(double value, double weight) {
      weightedScore += value * weight;
      weightSum += weight;
    }

    if (mealTargets.energy > 0 && calories > 0) {
      accumulate(
        _targetScore(calories, mealTargets.energy, tolerance: 0.12),
        0.3,
      );
    }

    if ((mealTargets.carbMin > 0 || mealTargets.carbMax > 0) && carbs > 0) {
      accumulate(
        _rangeScore(carbs, mealTargets.carbMin, mealTargets.carbMax),
        0.2,
      );
    }

    if ((mealTargets.fatMin > 0 || mealTargets.fatMax > 0) && fat > 0) {
      accumulate(
        _rangeScore(fat, mealTargets.fatMin, mealTargets.fatMax),
        0.15,
      );
    }

    if (mealTargets.proteinMin > 0 && protein > 0) {
      accumulate(
        _minScore(protein, mealTargets.proteinMin),
        0.25,
      );
    }

    if (mealTargets.sodiumMax > 0 && sodium > 0) {
      accumulate(
        _maxScore(sodium, mealTargets.sodiumMax),
        0.1,
      );
    }

    if (weightSum == 0) return 0;
    return (weightedScore / weightSum) * 150;
  }

  static double _targetScore(double value, double target, {double tolerance = 0.1}) {
    if (target <= 0) return 0;
    final min = target * (1 - tolerance);
    final max = target * (1 + tolerance);
    return _rangeScore(value, min, max);
  }

  static double _rangeScore(double value, double min, double max) {
    if (min <= 0 && max <= 0) return 0;
    if (max <= 0) {
      return value <= min ? 1 : (min / value).clamp(0, 1);
    }
    final lower = min <= 0 ? 0 : min;
    if (value >= lower && value <= max) return 1;
    if (value < lower && lower > 0) {
      return (value / lower).clamp(0, 1);
    }
    if (value > max && max > 0) {
      return (max / value).clamp(0, 1);
    }
    return 0;
  }

  static double _minScore(double value, double min) {
    if (min <= 0) return 0;
    if (value >= min) return 1;
    return (value / min).clamp(0, 1);
  }

  static double _maxScore(double value, double max) {
    if (max <= 0) return 0;
    if (value <= max) return 1;
    return (max / value).clamp(0, 1);
  }

  static double _inventoryScore(
    RecipeModel recipe,
    _InventoryContext context,
  ) {
    int usedCount = 0;
    int closestExpiry = 999;
    for (final ingredient in recipe.ingredients) {
      final key = ingredient.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      if (context.names.contains(key)) {
        usedCount++;
        final days = context.daysToExpiry[key] ?? 999;
        if (days < closestExpiry) closestExpiry = days;
      }
    }
    final missing = recipe.missingIngredients.length;
    final usedScore = usedCount * 120.0;
    final expiryBoost = closestExpiry >= 999 ? 0 : (999 - closestExpiry) * 4;
    final missingPenalty = missing * 60.0;
    return usedScore + expiryBoost - missingPenalty + recipe.matchScore;
  }
}

class _InventoryContext {
  final Set<String> names;
  final Map<String, int> daysToExpiry;
  const _InventoryContext({
    required this.names,
    required this.daysToExpiry,
  });

  factory _InventoryContext.fromIngredients(List<IngredientModel> ingredients) {
    final names = <String>{};
    final days = <String, int>{};
    for (final ingredient in ingredients) {
      final key = ingredient.name.trim().toLowerCase();
      if (key.isEmpty) continue;
      names.add(key);
      days[key] = ingredient.daysToExpiry;
    }
    return _InventoryContext(names: names, daysToExpiry: days);
  }
}

class _RecipeScoreData {
  final RecipeModel recipe;
  final double baseScore;
  const _RecipeScoreData({required this.recipe, required this.baseScore});
}

class _PerMealTargets {
  final double energy;
  final double carbMin;
  final double carbMax;
  final double fatMin;
  final double fatMax;
  final double proteinMin;
  final double sodiumMax;
  const _PerMealTargets({
    required this.energy,
    required this.carbMin,
    required this.carbMax,
    required this.fatMin,
    required this.fatMax,
    required this.proteinMin,
    required this.sodiumMax,
  });
}

class _SelectionResult {
  final RecipeModel recipe;
  final double score;
  const _SelectionResult({required this.recipe, required this.score});
}
