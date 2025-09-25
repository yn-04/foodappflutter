//lib/foodreccom/models/recipe/cooking_step.dart
class CookingStep {
  final int stepNumber;
  final String instruction;
  final int timeMinutes;
  final String? imageUrl;
  final List<String> tips;

  CookingStep({
    required this.stepNumber,
    required this.instruction,
    this.timeMinutes = 0,
    this.imageUrl,
    this.tips = const [],
  });

  factory CookingStep.fromJson(Map<String, dynamic> json) {
    return CookingStep(
      stepNumber: json['step_number'] ?? 0,
      instruction: json['instruction'] ?? '',
      timeMinutes: json['time_minutes'] ?? 0,
      imageUrl: json['image_url'],
      tips: List<String>.from(json['tips'] ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
    'step_number': stepNumber,
    'instruction': instruction,
    'time_minutes': timeMinutes,
    'image_url': imageUrl,
    'tips': tips,
  };
}
