// lib/models/recipe_model.dart
import 'package:flutter/material.dart';

class RecipeIngredient {
  final String name;
  final dynamic amount;
  final String unit;
  final bool isOptional;

  RecipeIngredient({
    required this.name,
    required this.amount,
    required this.unit,
    this.isOptional = false,
  });

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      name: json['name'] ?? '',
      amount: _parseAmount(json['amount']), // ใช้ helper method
      unit: json['unit'] ?? '',
      isOptional: json['is_optional'] ?? false,
    );
  }
  // Helper method สำหรับ parse amount ที่อาจเป็น string หรือ number
  static dynamic _parseAmount(dynamic value) {
    if (value == null) return 0.0;

    // ถ้าเป็นตัวเลขอยู่แล้ว
    if (value is num) return value.toDouble();

    // ถ้าเป็น string ให้ตรวจสอบว่าเป็น range หรือไม่
    if (value is String) {
      // ถ้ามี "-" ให้เก็บเป็น string
      if (value.contains('-')) {
        return value; // เก็บเป็น "5-10"
      }

      // ถ้าไม่มี "-" ให้แปลงเป็นตัวเลข
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'amount': amount,
    'unit': unit,
    'is_optional': isOptional,
  };

  // Helper method สำหรับแสดงผล amount
  String get displayAmount {
    if (amount is String) return amount.toString();
    if (amount is num) {
      // ถ้าเป็นจำนวนเต็ม ไม่แสดงทศนิยม
      if (amount == amount.toInt()) {
        return amount.toInt().toString();
      }
      return amount.toString();
    }
    return '0';
  }

  // Helper method สำหรับได้ค่าตัวเลขจาก amount (สำหรับการคำนวณ)
  double get numericAmount {
    if (amount is num) return amount.toDouble();
    if (amount is String) {
      // ถ้าเป็น range เช่น "5-10" ให้เอาค่าแรก
      final parts = amount.toString().split('-');
      return double.tryParse(parts[0].trim()) ?? 0.0;
    }
    return 0.0;
  }

  // Helper method สำหรับได้ช่วงค่า (ถ้ามี)
  String get amountRange {
    if (amount is String && amount.toString().contains('-')) {
      return amount.toString();
    }
    return displayAmount;
  }
}

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
}

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

  factory NutritionInfo.fromJson(Map<String, dynamic> json) {
    return NutritionInfo(
      calories: (json['calories'] ?? 0).toDouble(),
      protein: (json['protein'] ?? 0).toDouble(),
      carbs: (json['carbs'] ?? 0).toDouble(),
      fat: (json['fat'] ?? 0).toDouble(),
      fiber: (json['fiber'] ?? 0).toDouble(),
      sodium: (json['sodium'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'fiber': fiber,
    'sodium': sodium,
  };
}

class RecipeModel {
  final String id;
  final String name;
  final String description;
  final int matchScore;
  final String reason;
  final List<RecipeIngredient> ingredients;
  final List<String> missingIngredients;
  final List<CookingStep> steps;
  final int cookingTime;
  final int prepTime;
  final String difficulty;
  final int servings;
  final String category;
  final NutritionInfo nutrition;
  final String? imageUrl;
  final List<String> tags;
  final String? source; // เพิ่มอ้างอิง
  final String? sourceUrl; // เพิ่ม URL อ้างอิง

  RecipeModel({
    required this.id,
    required this.name,
    required this.description,
    required this.matchScore,
    required this.reason,
    required this.ingredients,
    required this.missingIngredients,
    required this.steps,
    required this.cookingTime,
    required this.prepTime,
    required this.difficulty,
    required this.servings,
    required this.category,
    required this.nutrition,
    this.imageUrl,
    this.tags = const [],
    this.source,
    this.sourceUrl,
  });

  factory RecipeModel.fromAI(Map<String, dynamic> json) {
    return RecipeModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: json['menu_name'] ?? 'ไม่ระบุชื่อ',
      description: json['description'] ?? '',
      matchScore: (json['match_score'] ?? 0).round(),
      reason: json['reason'] ?? '',
      ingredients: (json['ingredients'] as List? ?? [])
          .map((i) => RecipeIngredient.fromJson(i))
          .toList(),
      missingIngredients: List<String>.from(json['missing_ingredients'] ?? []),
      steps: (json['steps'] as List? ?? []).map((stepData) {
        if (stepData is String) {
          // ถ้าเป็น string ให้สร้าง CookingStep
          return CookingStep(stepNumber: 1, instruction: stepData);
        } else if (stepData is Map<String, dynamic>) {
          // ถ้าเป็น object ให้ parse ตาม format
          return CookingStep.fromJson(stepData);
        } else {
          return CookingStep(stepNumber: 1, instruction: stepData.toString());
        }
      }).toList(),
      cookingTime: json['cooking_time'] ?? 30,
      prepTime: json['prep_time'] ?? 10,
      difficulty: json['difficulty'] ?? 'ปานกลาง',
      servings: json['servings'] ?? 2,
      category: json['category'] ?? 'อาหารจานหลัก',
      nutrition: NutritionInfo.fromJson(json['nutrition'] ?? {}),
      imageUrl: json['image_url'],
      tags: List<String>.from(json['tags'] ?? []),
      source: json['source'],
      sourceUrl: json['source_url'],
    );
  }

  // เพิ่ม getter สำหรับ backward compatibility
  List<String> get ingredientsUsed =>
      ingredients.map((ing) => ing.name).toList();

  int get totalTime => cookingTime + prepTime;

  Color get scoreColor {
    if (matchScore >= 80) return Colors.green;
    if (matchScore >= 60) return Colors.orange;
    return Colors.red;
  }

  double get caloriesPerServing => nutrition.calories / servings;
}
