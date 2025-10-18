import '../models/recipe/recipe_model.dart';

class MealPlanEntry {
  final DateTime date;
  final RecipeModel recipe;
  final int servings;
  final bool pinned;
  final int score;
  final bool done;
  const MealPlanEntry({
    required this.date,
    required this.recipe,
    required this.servings,
    this.pinned = false,
    this.score = 0,
    this.done = false,
  });

  MealPlanEntry copyWith({
    DateTime? date,
    RecipeModel? recipe,
    int? servings,
    bool? pinned,
    int? score,
    bool? done,
  }) => MealPlanEntry(
        date: date ?? this.date,
        recipe: recipe ?? this.recipe,
        servings: servings ?? this.servings,
        pinned: pinned ?? this.pinned,
        score: score ?? this.score,
        done: done ?? this.done,
      );

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'recipe': recipe.toJson(),
        'servings': servings,
        'pinned': pinned,
        'score': score,
        'done': done,
      };

  factory MealPlanEntry.fromJson(Map<String, dynamic> json) => MealPlanEntry(
        date: DateTime.parse(json['date'] as String),
        recipe: RecipeModel.fromJson(json['recipe'] as Map<String, dynamic>),
        servings: json['servings'] as int? ?? 1,
        pinned: json['pinned'] as bool? ?? false,
        score: json['score'] as int? ?? 0,
        done: json['done'] as bool? ?? false,
      );
}

class MealPlanDay {
  final DateTime date;
  final List<MealPlanEntry> meals;
  const MealPlanDay({required this.date, required this.meals});

  MealPlanDay copyWith({DateTime? date, List<MealPlanEntry>? meals}) =>
      MealPlanDay(date: date ?? this.date, meals: meals ?? this.meals);

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'meals': meals.map((e) => e.toJson()).toList(),
      };

  factory MealPlanDay.fromJson(Map<String, dynamic> json) => MealPlanDay(
        date: DateTime.parse(json['date'] as String),
        meals: (json['meals'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(MealPlanEntry.fromJson)
            .toList(),
      );
}

class MealPlan {
  final List<MealPlanDay> days;
  final DateTime generatedAt;
  const MealPlan({required this.days, required this.generatedAt});

  Map<String, dynamic> toJson() => {
        'generatedAt': generatedAt.toIso8601String(),
        'days': days.map((d) => d.toJson()).toList(),
      };

  factory MealPlan.fromJson(Map<String, dynamic> json) => MealPlan(
        days: (json['days'] as List? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(MealPlanDay.fromJson)
            .toList(),
        generatedAt: DateTime.parse(json['generatedAt'] as String),
      );
}
