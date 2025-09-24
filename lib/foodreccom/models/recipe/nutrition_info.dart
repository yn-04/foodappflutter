// lib/foodreccom/models/recipe/nutrition_info.dart
class NutritionInfo {
  final double calories;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber;
  final double sodium;

  NutritionInfo({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.sodium,
  });

  /// ✅ แปลงจาก Map (Firestore หรือ API)
  factory NutritionInfo.fromMap(Map<String, dynamic> map) {
    return NutritionInfo(
      calories: (map['calories'] ?? 0).toDouble(),
      protein: (map['protein'] ?? 0).toDouble(),
      carbs: (map['carbs'] ?? 0).toDouble(),
      fat: (map['fat'] ?? 0).toDouble(),
      fiber: (map['fiber'] ?? 0).toDouble(),
      sodium: (map['sodium'] ?? 0).toDouble(),
    );
  }

  /// ✅ แปลงเป็น Map
  Map<String, dynamic> toMap() {
    return {
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'fiber': fiber,
      'sodium': sodium,
    };
  }

  /// ✅ alias สำหรับ JSON (compatibility)
  factory NutritionInfo.fromJson(Map<String, dynamic> json) =>
      NutritionInfo.fromMap(json);

  Map<String, dynamic> toJson() => toMap();
}
