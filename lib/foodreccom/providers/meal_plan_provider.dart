import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_app/foodreccom/constants/nutrition_thresholds.dart';
import '../models/meal_plan.dart';
import '../models/ingredient_model.dart';
import '../models/recipe/recipe_model.dart';
import '../models/purchase_item.dart';
import '../services/meal_plan_service.dart';
import '../services/hybrid_recipe_service.dart';
import 'enhanced_recommendation_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/ingredient_translator.dart';
import '../utils/purchase_item_utils.dart';
import '../models/dri_targets.dart';
import '../models/recipe/nutrition_info.dart';
import '../services/enhanced_ai_recommendation_service.dart';
import '../services/api_usage_service.dart';
import 'package:my_app/utils/app_logger.dart';

class MealFrequencyInfo {
  final ConsumptionFrequency? frequency;
  final String? reason;
  final List<String> highlightedIngredients;
  const MealFrequencyInfo({
    this.frequency,
    this.reason,
    this.highlightedIngredients = const [],
  });
}

class MealPlanFrequencySummary {
  final Map<ConsumptionFrequency, int> counts;
  final int totalMeals;
  final double totalCalories;
  final int dayCount;
  const MealPlanFrequencySummary({
    required this.counts,
    required this.totalMeals,
    required this.totalCalories,
    required this.dayCount,
  });

  double get averageCaloriesPerDay =>
      dayCount == 0 ? 0 : totalCalories / dayCount;

  double get averageCaloriesPerMeal =>
      totalMeals == 0 ? 0 : totalCalories / totalMeals;
}

class MealPlanProvider extends ChangeNotifier {
  MealPlan? _plan;
  DriTargets? _driTargets;
  static const int _fixedMealsPerDay = 3; // ใช้ค่า 3 มื้อ/วัน แบบคงที่
  List<DailyNutritionSummary> _dailySummaries = const [];
  Map<DateTime, String> _dailyInsights = const {};
  bool _insightBusy = false;
  NutritionInfo? _weeklyTotals;
  String? _weeklyInsight;
  bool _weeklyInsightBusy = false;

  MealPlan? get plan => _plan;
  NutritionInfo? get weeklyTotals => _weeklyTotals;
  String? get weeklyInsight => _weeklyInsight;
  bool get isWeeklyInsightGenerating => _weeklyInsightBusy;

  DailyNutritionSummary? summaryFor(DateTime date) {
    final key = DateTime(date.year, date.month, date.day);
    for (final summary in _dailySummaries) {
      if (summary.date == key) return summary;
    }
    return null;
  }

  String? insightFor(DateTime date) {
    final key = DateTime(date.year, date.month, date.day);
    return _dailyInsights[key];
  }
  List<DailyNutritionSummary> get dailySummaries => _dailySummaries;
  bool get isGeneratingInsights => _insightBusy;

  Future<void> generateWeeklyPlan(EnhancedRecommendationProvider recProvider) async {
    // Ensure ingredients and candidates available
    if (recProvider.ingredients.isEmpty) {
      await recProvider.loadIngredients();
    }
    // ใช้ recipes จาก EnhancedRecommendationProvider ก่อน ถ้าไม่มีค่อยเรียก Hybrid
    List<RecipeModel> candidates = [...recProvider.recommendations];
    if (candidates.isEmpty) {
      // ensure we have recommendations
      await recProvider.getHybridRecommendations();
      candidates = [...recProvider.recommendations];
    }
    if (candidates.isEmpty) {
      final hybrid = HybridRecipeService()..useAiIngredientSelector = true;
      final result = await hybrid.getHybridRecommendations(
        recProvider.ingredients,
        cookingHistory: recProvider.cookingHistory,
        cuisineFilters: recProvider.filters.cuisineEn,
        dietGoals: recProvider.filters.dietGoals,
        minCalories: recProvider.filters.minCalories,
        maxCalories: recProvider.filters.maxCalories,
      );
      candidates = List<RecipeModel>.from(result.externalRecipes);
    }

    _driTargets = null;
    final driTargets = await _loadUserDriTargets();
    _driTargets = driTargets;
    _plan = MealPlanService.generateWeeklyPlan(
      ingredients: recProvider.ingredients,
      candidates: candidates,
      days: 7,
      mealsPerDay: _fixedMealsPerDay,
      servingsPerMeal: 1,
      userDri: driTargets,
      // ไม่ใช้ pinned/targets/budget อีกต่อไป
    );
    _dailySummaries = _buildDailySummaries();
    _dailyInsights = _buildLocalNutritionInsights();
    _weeklyTotals = _computeWeeklyTotals();
    _weeklyInsight = _buildLocalWeeklyInsight();
    _weeklyInsightBusy = false;
    notifyListeners();
    unawaited(_generateDailyNutritionInsights());
    unawaited(_generateWeeklyNutritionInsight());
  }

  Future<void> regenerateUnlocked(EnhancedRecommendationProvider recProvider) async {
    if (_plan == null) {
      await generateWeeklyPlan(recProvider);
      return;
    }
    // สร้างใหม่เฉพาะรายการที่ไม่ถูกปักหมุดและวันที่ยังไม่ถึง
    await generateWeeklyPlan(recProvider);
  }

  // Consolidated shopping list across the week (simple sum of missing per recipe)
  List<PurchaseItem> consolidatedShoppingList(List<IngredientModel> inventory) {
    if (_plan == null) return [];
    final map = <String, CanonicalQuantity>{}; // canonical name -> canonical amount
    final aliasLookup = <String, String>{}; // alias -> canonical name
    final displayNames = <String, String>{}; // canonical name -> display label

    for (final day in _plan!.days) {
      for (final entry in day.meals) {
        final r = entry.recipe;
        final baseServ = r.servings == 0 ? 1 : r.servings;
        final mult = entry.servings / baseServ;
        for (final ri in r.ingredients) {
          final amt = ri.numericAmount * mult;
          final canon = toCanonicalQuantity(amt, ri.unit, ri.name);
          final canonicalName = normalizeName(ri.name);
          final prev = map[canonicalName];
          map[canonicalName] = prev == null ? canon : prev + canon;
          displayNames.putIfAbsent(canonicalName, () => ri.name.trim());
          _registerAliases(
            aliasLookup: aliasLookup,
            canonicalName: canonicalName,
            name: ri.name,
          );
        }
      }
    }
    // subtract inventory using aliases + unit conversion
    for (final inv in inventory) {
      final candidates = <String>{
        normalizeName(inv.name),
        normalizeName(IngredientTranslator.translate(inv.name)),
      }..removeWhere((value) => value.isEmpty);

      final canonicalKey = _resolveCanonicalKey(
        candidates,
        aliasLookup,
        map,
      );
      if (canonicalKey == null) continue;

      final need = map[canonicalKey];
      if (need == null) continue;

      final haveCanonical =
          toCanonicalQuantity(inv.quantity.toDouble(), inv.unit, inv.name);
      final availableAmount = _convertCanonicalAmount(
        source: haveCanonical,
        targetCanonicalUnit: need.unit,
        ingredientName: inv.name,
      );
      if (availableAmount <= 0) continue;

      final remainingAmount = need.amount - availableAmount;
      if (remainingAmount <= 0) {
        map.remove(canonicalKey);
      } else {
        map[canonicalKey] = CanonicalQuantity(remainingAmount, need.unit);
      }
    }
    // build list
    final items = <PurchaseItem>[];
    for (final e in map.entries) {
      final canonicalName = e.key;
      final need = e.value;
      final displayName = displayNames[canonicalName] ?? canonicalName;
      final unit = displayUnitForCanonical(need.unit, displayName);
      final qty = need.amount.ceil();
      if (qty <= 0) continue;
      items.add(
        PurchaseItem(
          name: displayName,
          quantity: qty,
          unit: unit,
          category: guessCategory(displayName),
        ),
      );
    }
    return items;
  }

  // ----- Firestore persistence -----
  Future<String?> saveCurrentPlan() async {
    if (_plan == null) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meal_plans');
    final doc = await col.add({
      'plan': _plan!.toJson(),
      'generated_at': _plan!.generatedAt.toIso8601String(),
      'meals_per_day': _fixedMealsPerDay,
      'created_at': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> loadLatestPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meal_plans');
    final snap = await col.orderBy('created_at', descending: true).limit(1).get();
    if (snap.docs.isEmpty) return;
    final data = snap.docs.first.data();
    final planJson = (data['plan'] as Map<String, dynamic>);
    _plan = MealPlan.fromJson(planJson);
    // ค่าตั้งค่าส่วนอื่นถูกตัดออก ไม่ต้องโหลด
    notifyListeners();
  }

  Future<DriTargets?> _loadUserDriTargets() async {
    if (_driTargets != null) return _driTargets;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data();
      if (data == null) return null;
      final profile = data['healthProfile'];
      if (profile is Map<String, dynamic>) {
        final dri = profile['dri'];
        if (dri is Map<String, dynamic>) {
          final parsed = DriTargets.fromMap(dri);
          if (parsed.energyKcal > 0) {
            _driTargets = parsed;
            return parsed;
          }
        }
      }
    } catch (_) {
      // ignore fetch errors; plan generation will fallback without DRI
    }
    return null;
  }

  List<DailyNutritionSummary> _buildDailySummaries() {
    final plan = _plan;
    if (plan == null) return const [];
    final summaries = <DailyNutritionSummary>[];
    for (final day in plan.days) {
      double calories = 0;
      double protein = 0;
      double carbs = 0;
      double fat = 0;
      double fiber = 0;
      double sodium = 0;

      for (final meal in day.meals) {
        final recipe = meal.recipe;
        final baseServings = recipe.servings == 0 ? 1 : recipe.servings;
        final multiplier = meal.servings / baseServings;
        final nutrition = recipe.nutrition;
        calories += nutrition.calories * multiplier;
        protein += nutrition.protein * multiplier;
        carbs += nutrition.carbs * multiplier;
        fat += nutrition.fat * multiplier;
        fiber += nutrition.fiber * multiplier;
        sodium += nutrition.sodium * multiplier;
      }

      summaries.add(
        DailyNutritionSummary(
          date: DateTime(day.date.year, day.date.month, day.date.day),
          totals: NutritionInfo(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sodium: sodium,
          ),
        ),
      );
    }
    return summaries;
  }

  NutritionInfo? _computeWeeklyTotals() {
    if (_dailySummaries.isEmpty) return null;
    double calories = 0;
    double protein = 0;
    double carbs = 0;
    double fat = 0;
    double fiber = 0;
    double sodium = 0;
    for (final summary in _dailySummaries) {
      final totals = summary.totals;
      calories += totals.calories;
      protein += totals.protein;
      carbs += totals.carbs;
      fat += totals.fat;
      fiber += totals.fiber;
      sodium += totals.sodium;
    }
    return NutritionInfo(
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      fiber: fiber,
      sodium: sodium,
    );
  }

  Map<DateTime, String> _buildLocalNutritionInsights() {
    final summaries = _dailySummaries;
    if (summaries.isEmpty) return const {};
    final Map<DateTime, String> map = {};
    for (final summary in summaries) {
      final builder = <String>[];
      final totals = summary.totals;
      final dri = _driTargets;
      if (dri != null) {
        builder.add(_compareSingle('พลังงาน', totals.calories, dri.energyKcal, 'kcal'));
        builder.add(_compareSingle('โปรตีน', totals.protein, dri.proteinG, 'g'));
        builder.add(_compareRange('คาร์บ', totals.carbs, dri.carbMinG, dri.carbMaxG, 'g'));
        builder.add(_compareRange('ไขมัน', totals.fat, dri.fatMinG, dri.fatMaxG, 'g'));
        builder.add(_compareSingle('ไฟเบอร์', totals.fiber, _estimatedFiberTarget(), 'g'));
        builder.add(_compareMax('โซเดียม', totals.sodium, dri.sodiumMaxMg, 'mg'));
      } else {
        builder.add('พลังงานรวม ${totals.calories.toStringAsFixed(0)} kcal');
        builder.add('โปรตีน ${totals.protein.toStringAsFixed(0)} g');
        builder.add('คาร์บ ${totals.carbs.toStringAsFixed(0)} g');
        builder.add('ไขมัน ${totals.fat.toStringAsFixed(0)} g');
      }
      map[summary.date] = builder.where((e) => e.isNotEmpty).join(' • ');
    }
    return map;
  }

  String? _buildLocalWeeklyInsight() {
    final totals = _weeklyTotals;
    final dri = _driTargets;
    final dayCount = _plan?.days.length ?? _dailySummaries.length;
    if (totals == null || dayCount == 0) return null;

    final name = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final userName = (name == null || name.isEmpty) ? 'คุณ' : name;
    final nf0 = NumberFormat('#,##0', 'th_TH');
    final nf1 = NumberFormat('#,##0.0', 'th_TH');

    if (dri == null) {
      return '$userName รวมพลังงานสัปดาห์นี้ ${nf0.format(totals.calories)} kcal '
          'โปรตีน ${nf0.format(totals.protein)} g คาร์บ ${nf0.format(totals.carbs)} g '
          'ไขมัน ${nf0.format(totals.fat)} g และไฟเบอร์ ${nf0.format(totals.fiber)} g';
    }

    final targetCalories = dri.energyKcal * dayCount;
    final targetProtein = dri.proteinG * dayCount;
    final targetCarbMin = dri.carbMinG * dayCount;
    final targetCarbMax = dri.carbMaxG * dayCount;
    final targetFatMin = dri.fatMinG * dayCount;
    final targetFatMax = dri.fatMaxG * dayCount;
    final targetFiber = _estimatedWeeklyFiberTarget(dayCount);
    final targetSodium = dri.sodiumMaxMg * dayCount;

    final buffer = StringBuffer();
    final calDiff = totals.calories - targetCalories;
    final calTolerance = targetCalories * 0.05;
    if (calDiff.abs() <= calTolerance) {
      buffer.write('$userName คุมพลังงานตลอดสัปดาห์ได้ดีมาก!');
    } else if (calDiff > 0) {
      buffer.write(
        '$userName พลังงานรวมเกินเป้าราว ${nf0.format(calDiff)} kcal ลองลดเมนูพลังงานสูงลงเล็กน้อยนะ',
      );
    } else {
      buffer.write(
        '$userName พลังงานรวมยังขาดประมาณ ${nf0.format(calDiff.abs())} kcal เติมเมนูหลักเพิ่มอีกนิดได้นะ',
      );
    }

    final suggestions = <String>[];

    final proteinDiff = totals.protein - targetProtein;
    if (proteinDiff < -10) {
      suggestions.add('เพิ่มโปรตีนอีก ${nf1.format(proteinDiff.abs())} g');
    }

    if (totals.carbs < targetCarbMin) {
      suggestions.add('เติมคาร์บอีก ${nf1.format((targetCarbMin - totals.carbs).abs())} g');
    } else if (totals.carbs > targetCarbMax) {
      suggestions.add('ลดคาร์บลง ${nf1.format((totals.carbs - targetCarbMax).abs())} g');
    }

    if (totals.fat < targetFatMin) {
      suggestions.add('เพิ่มไขมันดีอีก ${nf1.format((targetFatMin - totals.fat).abs())} g');
    } else if (totals.fat > targetFatMax) {
      suggestions.add('ลดไขมันลง ${nf1.format((totals.fat - targetFatMax).abs())} g');
    }

    final fiberDiff = totals.fiber - targetFiber;
    if (fiberDiff < -5) {
      suggestions.add('เพิ่มผักผลไม้เพื่อไฟเบอร์อีก ${nf1.format(fiberDiff.abs())} g');
    }

    if (totals.sodium > targetSodium) {
      suggestions.add('ลดโซเดียมลง ${nf0.format((totals.sodium - targetSodium).abs())} mg');
    }

    if (suggestions.isNotEmpty) {
      buffer.write(' ลอง${suggestions.join(' และ ')} จะยิ่งสมดุลขึ้นค่ะ');
    } else {
      buffer.write(' โภชนาการหลักอยู่ในช่วงพอดีแทบทุกหมวด เยี่ยมเลย!');
    }

    buffer.write(' (เฉลี่ยวันละ ${nf0.format(totals.calories / dayCount)} kcal)');
    return buffer.toString();
  }

  String _compareSingle(String label, double actual, double target, String unit) {
    final diff = actual - target;
    if (diff.abs() < 1) return '$label อยู่ในเป้า';
    final symbol = diff > 0 ? '+' : '-';
    return '$label ${actual.toStringAsFixed(0)}$unit ($symbol${diff.abs().toStringAsFixed(0)}$unit)';
  }

  String _compareRange(
    String label,
    double actual,
    double min,
    double max,
    String unit,
  ) {
    if (actual >= min && actual <= max) return '$label อยู่ในช่วงปกติ';
    if (actual < min) {
      return '$label ขาด ${(min - actual).abs().toStringAsFixed(0)}$unit';
    }
    return '$label เกิน ${(actual - max).toStringAsFixed(0)}$unit';
  }

  double _estimatedFiberTarget() {
    final dri = _driTargets;
    if (dri == null) return 25;
    final calories = dri.energyKcal;
    if (calories <= 0) return 25;
    return calories * 14 / 1000; // 14g ต่อ 1000 kcal ตามคำแนะนำทั่วไป
  }

  double _estimatedWeeklyFiberTarget(int dayCount) {
    if (dayCount <= 0) return 0;
    return _estimatedFiberTarget() * dayCount;
  }

  String _compareMax(String label, double actual, double max, String unit) {
    if (actual <= max) return '$label ไม่เกินกำหนด';
    return '$label เกิน ${(actual - max).toStringAsFixed(0)}$unit';
  }

  Future<void> _generateDailyNutritionInsights() async {
    if (_plan == null || _dailySummaries.isEmpty) return;
    final dri = _driTargets ?? await _loadUserDriTargets();
    if (dri == null) return;

    _insightBusy = true;
    notifyListeners();

    final userName = FirebaseAuth.instance.currentUser?.displayName ?? 'คุณ';
    final context = {
      'user_name': userName,
      'dri': {
        'calories': dri.energyKcal,
        'protein': dri.proteinG,
        'carb_min': dri.carbMinG,
        'carb_max': dri.carbMaxG,
        'fat_min': dri.fatMinG,
        'fat_max': dri.fatMaxG,
        'sodium_max': dri.sodiumMaxMg,
      },
      'days': _dailySummaries
          .map(
            (d) => {
              'date': d.date.toIso8601String(),
              'weekday': _weekdayLabel(d.date.weekday),
              'totals': {
                'calories': d.totals.calories,
                'protein': d.totals.protein,
                'carbs': d.totals.carbs,
                'fat': d.totals.fat,
                'fiber': d.totals.fiber,
                'sodium': d.totals.sodium,
              },
            },
          )
          .toList(),
    };

    try {
      if (!await ApiUsageService.canUseGemini() ||
          !await ApiUsageService.allowGeminiCall()) {
        _insightBusy = false;
        notifyListeners();
        return;
      }
      final ai = EnhancedAIRecommendationService();
      final prompt = [
        'คุณคือ Smart Insight by Gemini สำหรับวางแผนโภชนาการรายวัน',
        'เป้าหมาย: ให้คำแนะนำแบบเป็นกันเองว่าแต่ละวันควรเพิ่มหรือลดสารอาหารใดเท่าใดเมื่อเทียบกับค่า DRI',
        'ตอบเป็น JSON {"insights":[{"date":"YYYY-MM-DD","message":"ข้อความย่อ 1 ประโยค"}]} เท่านั้น',
        'ให้ขึ้นต้นข้อความด้วยคำว่า "${userName}…" หรือ "${userName}ครับ/ค่ะ" ตามความเหมาะสม ใช้โทนเชียร์บวก เช่น "${userName} คุมโภชนาการได้ดีมาก!" หรือ "เพิ่มโปรตีนอีก 15g จะพอดีเลย"',
        'ห้ามระบุหน่วยซ้ำซ้อน เก็บไว้ในรูปแบบเช่น +120 kcal, -15 g โปรตีน',
        'ข้อมูล:',
        jsonEncode(context),
      ].join('\n');
      final response = await ai.generateTextSmart(prompt);
      await ApiUsageService.countGemini();
      final parsed = _parseInsightJson(response);
      if (parsed.isNotEmpty) {
        _dailyInsights = parsed;
      }
    } catch (e, st) {
      logError('Smart Insight daily error: $e', stackTrace: st);
      try {
        await ApiUsageService.setGeminiCooldown(const Duration(seconds: 30));
      } catch (_) {}
    } finally {
      _insightBusy = false;
      notifyListeners();
    }
  }

  Future<void> _generateWeeklyNutritionInsight() async {
    final totals = _weeklyTotals ?? _computeWeeklyTotals();
    final dri = _driTargets ?? await _loadUserDriTargets();
    final dayCount = _plan?.days.length ?? _dailySummaries.length;
    if (totals == null || dri == null || dayCount == 0) return;

    final name = FirebaseAuth.instance.currentUser?.displayName?.trim();
    final userName = (name == null || name.isEmpty) ? 'คุณ' : name;

    _weeklyInsight = _buildLocalWeeklyInsight();
    _weeklyInsightBusy = true;
    notifyListeners();

    final context = {
      'user_name': userName,
      'day_count': dayCount,
      'weekly_totals': {
        'calories': totals.calories,
        'protein': totals.protein,
        'carbs': totals.carbs,
        'fat': totals.fat,
        'fiber': totals.fiber,
        'sodium': totals.sodium,
      },
      'average_per_day': {
        'calories': totals.calories / dayCount,
        'protein': totals.protein / dayCount,
        'carbs': totals.carbs / dayCount,
        'fat': totals.fat / dayCount,
        'fiber': totals.fiber / dayCount,
        'sodium': totals.sodium / dayCount,
      },
      'targets': {
        'calories': dri.energyKcal * dayCount,
        'protein': dri.proteinG * dayCount,
        'carb_min': dri.carbMinG * dayCount,
        'carb_max': dri.carbMaxG * dayCount,
        'fat_min': dri.fatMinG * dayCount,
        'fat_max': dri.fatMaxG * dayCount,
        'fiber': _estimatedWeeklyFiberTarget(dayCount),
        'sodium_max': dri.sodiumMaxMg * dayCount,
      },
    };

    try {
      if (!await ApiUsageService.canUseGemini() ||
          !await ApiUsageService.allowGeminiCall()) {
        _weeklyInsightBusy = false;
        notifyListeners();
        return;
      }

      final ai = EnhancedAIRecommendationService();
      final prompt = [
        'คุณคือ Smart Insight by Gemini สำหรับสรุปโภชนาการรายสัปดาห์',
        'เป้าหมาย: วิเคราะห์ภาพรวมทั้งสัปดาห์ แล้วเขียนข้อความสั้นๆ ที่เป็นมิตรบอกว่า ${userName} ควรเพิ่มหรือลดสารอาหารใด',
        'ตอบเป็น JSON {"message":"ข้อความเดียว"} เท่านั้น',
        'ใช้โทนเชียร์บวก อ่านแล้วอยากทำตาม เช่น "${userName} คุมพลังงานสัปดาห์นี้ดีมาก! ลองเพิ่มโปรตีนอีก 20g จะยิ่งสมดุล"',
        'ข้อมูล:',
        jsonEncode(context),
      ].join('\n');

      final response = await ai.generateTextSmart(prompt);
      await ApiUsageService.countGemini();
      final parsed = _parseWeeklyInsightJson(response);
      if (parsed != null && parsed.isNotEmpty) {
        _weeklyInsight = parsed;
        _weeklyInsightBusy = false;
        notifyListeners();
        return;
      }
    } catch (e, st) {
      logError('Smart Insight weekly error: $e', stackTrace: st);
      try {
        await ApiUsageService.setGeminiCooldown(const Duration(seconds: 30));
      } catch (_) {}
    }

    _weeklyInsightBusy = false;
    notifyListeners();
  }

  Map<DateTime, String> _parseInsightJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final list = decoded['insights'];
        if (list is List) {
          final map = <DateTime, String>{};
          for (final item in list) {
            if (item is! Map<String, dynamic>) continue;
            final dateStr = item['date']?.toString();
            final message = item['message']?.toString();
            if (dateStr == null || message == null) continue;
            final date = DateTime.tryParse(dateStr);
            if (date == null) continue;
            map[DateTime(date.year, date.month, date.day)] = message.trim();
          }
          return map;
        }
      }
    } catch (_) {}
    return const {};
  }

  String? _parseWeeklyInsightJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final msg = decoded['message'];
        if (msg is String && msg.trim().isNotEmpty) {
          return msg.trim();
        }
        final insights = decoded['insights'];
        if (insights is List && insights.isNotEmpty) {
          final first = insights.first;
          if (first is Map) {
            final text = first['message'];
            if (text is String && text.trim().isNotEmpty) {
              return text.trim();
            }
          } else if (first is String && first.trim().isNotEmpty) {
            return first.trim();
          }
        }
      }
    } catch (_) {}
    return null;
  }

  String _weekdayLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'จันทร์';
      case DateTime.tuesday:
        return 'อังคาร';
      case DateTime.wednesday:
        return 'พุธ';
      case DateTime.thursday:
        return 'พฤหัส';
      case DateTime.friday:
        return 'ศุกร์';
      case DateTime.saturday:
        return 'เสาร์';
      case DateTime.sunday:
        return 'อาทิตย์';
      default:
        return 'ไม่ระบุ';
    }
  }

  MealFrequencyInfo mealFrequencyInfo(
    MealPlanEntry entry,
    List<IngredientModel> inventory,
  ) {
    if (_plan == null) return const MealFrequencyInfo();
    final index = _ingredientIndex(inventory);
    ConsumptionFrequency? selectedFrequency;
    String? selectedReason;
    final flagged = <String>[];

    for (final recipeIngredient in entry.recipe.ingredients) {
      final key = normalizeName(recipeIngredient.name);
      final inv = index[key];
      if (inv == null || inv.consumptionFrequency == null) continue;
      final freq = inv.consumptionFrequency!;
      if (selectedFrequency == null ||
          _frequencySeverity(freq) > _frequencySeverity(selectedFrequency)) {
        selectedFrequency = freq;
        selectedReason = inv.consumptionReason;
        flagged
          ..clear()
          ..add(inv.name);
      } else if (selectedFrequency != null &&
          _frequencySeverity(freq) == _frequencySeverity(selectedFrequency)) {
        if (inv.consumptionReason != null &&
            (selectedReason == null || selectedReason!.trim().isEmpty)) {
          selectedReason = inv.consumptionReason;
        }
        flagged.add(inv.name);
      }
    }

    return MealFrequencyInfo(
      frequency: selectedFrequency,
      reason: selectedReason,
      highlightedIngredients: flagged,
    );
  }

  Map<ConsumptionFrequency, int> dayFrequencyCounts(
    MealPlanDay day,
    List<IngredientModel> inventory,
  ) {
    final counts = <ConsumptionFrequency, int>{};
    for (final meal in day.meals) {
      final info = mealFrequencyInfo(meal, inventory);
      final freq = info.frequency;
      if (freq == null) continue;
      counts[freq] = (counts[freq] ?? 0) + 1;
    }
    return counts;
  }

  MealPlanFrequencySummary frequencySummary(
    List<IngredientModel> inventory,
  ) {
    if (_plan == null) {
      return const MealPlanFrequencySummary(
        counts: {},
        totalMeals: 0,
        totalCalories: 0,
        dayCount: 0,
      );
    }
    final counts = <ConsumptionFrequency, int>{};
    double totalCalories = 0;
    int totalMeals = 0;
    for (final day in _plan!.days) {
      for (final meal in day.meals) {
        totalMeals++;
        totalCalories += meal.recipe.nutrition.calories;
        final freq = mealFrequencyInfo(meal, inventory).frequency;
        if (freq == null) continue;
        counts[freq] = (counts[freq] ?? 0) + 1;
      }
    }
    return MealPlanFrequencySummary(
      counts: counts,
      totalMeals: totalMeals,
      totalCalories: totalCalories,
      dayCount: _plan!.days.length,
    );
  }

  Future<bool> swapMeal(
    DateTime date,
    int mealIndex,
    EnhancedRecommendationProvider recProvider,
  ) async {
    if (_plan == null) return false;
    int dayIdx =
        _plan!.days.indexWhere((d) => _isSameDay(d.date, date));
    if (dayIdx == -1) return false;

    if (recProvider.recommendations.isEmpty) {
      await recProvider.getHybridRecommendations();
    }
    var candidates = [...recProvider.recommendations];
    if (candidates.isEmpty) {
      final hybrid = HybridRecipeService()..useAiIngredientSelector = true;
      final result = await hybrid.getHybridRecommendations(
        recProvider.ingredients,
        cookingHistory: recProvider.cookingHistory,
        cuisineFilters: recProvider.filters.cuisineEn,
        dietGoals: recProvider.filters.dietGoals,
        minCalories: recProvider.filters.minCalories,
        maxCalories: recProvider.filters.maxCalories,
      );
      candidates = List<RecipeModel>.from(result.externalRecipes);
    }
    if (candidates.isEmpty) return false;

    final usedIds = _plan!.days
        .expand((d) => d.meals.map((m) => m.recipe.id))
        .toSet();
    final currentEntry = _plan!.days[dayIdx].meals[mealIndex];
    RecipeModel? replacement;
    for (final candidate in candidates) {
      if (candidate.id == currentEntry.recipe.id) continue;
      if (usedIds.contains(candidate.id)) continue;
      replacement = candidate;
      break;
    }
    replacement ??= candidates.firstWhere(
      (c) => c.id != currentEntry.recipe.id,
      orElse: () => candidates.first,
    );
    if (replacement == null || replacement.id == currentEntry.recipe.id) {
      return false;
    }

    final days = [..._plan!.days];
    final meals = [...days[dayIdx].meals];
    meals[mealIndex] =
        currentEntry.copyWith(recipe: replacement, done: false, pinned: false);
    days[dayIdx] = days[dayIdx].copyWith(meals: meals);
    _plan = MealPlan(days: days, generatedAt: _plan!.generatedAt);
    _dailySummaries = _buildDailySummaries();
    _dailyInsights = _buildLocalNutritionInsights();
    _weeklyTotals = _computeWeeklyTotals();
    _weeklyInsight = _buildLocalWeeklyInsight();
    _weeklyInsightBusy = false;
    unawaited(_generateDailyNutritionInsights());
    unawaited(_generateWeeklyNutritionInsight());
    notifyListeners();
    return true;
  }

  Map<String, IngredientModel> _ingredientIndex(
    List<IngredientModel> inventory,
  ) {
    final map = <String, IngredientModel>{};
    for (final ingredient in inventory) {
      final key = normalizeName(ingredient.name);
      if (key.isEmpty) continue;
      map.putIfAbsent(key, () => ingredient);
    }
    return map;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int _frequencySeverity(ConsumptionFrequency frequency) {
    switch (frequency) {
      case ConsumptionFrequency.daily:
        return 0;
      case ConsumptionFrequency.oncePerDay:
        return 1;
      case ConsumptionFrequency.weekly:
        return 2;
      case ConsumptionFrequency.occasional:
        return 3;
    }
  }

  void _registerAliases({
    required Map<String, String> aliasLookup,
    required String canonicalName,
    required String name,
  }) {
    void addAlias(String raw) {
      final key = normalizeName(raw);
      if (key.isEmpty || aliasLookup.containsKey(key)) return;
      aliasLookup[key] = canonicalName;
    }

    addAlias(name);
    final cleaned = name.split(RegExp(r'[(/,]')).first;
    addAlias(cleaned);

    final translated = IngredientTranslator.translate(name);
    addAlias(translated);
    final translatedClean = translated.split(RegExp(r'[(/,]')).first;
    addAlias(translatedClean);

    if (translated.length > 3 && translated.endsWith('es')) {
      addAlias(translated.substring(0, translated.length - 2));
    }
    if (translated.length > 2 && translated.endsWith('s')) {
      addAlias(translated.substring(0, translated.length - 1));
    }

    addAlias(canonicalName);
  }

  String? _resolveCanonicalKey(
    Set<String> candidates,
    Map<String, String> aliasLookup,
    Map<String, CanonicalQuantity> requirement,
  ) {
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      final alias = aliasLookup[candidate];
      if (alias != null && requirement.containsKey(alias)) return alias;
      if (requirement.containsKey(candidate)) return candidate;
    }

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      for (final entry in aliasLookup.entries) {
        if (!requirement.containsKey(entry.value)) continue;
        if (candidate.contains(entry.key) || entry.key.contains(candidate)) {
          return entry.value;
        }
      }
    }

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      for (final key in requirement.keys) {
        if (candidate.contains(key) || key.contains(candidate)) {
          return key;
        }
      }
    }
    return null;
  }

  double _convertCanonicalAmount({
    required CanonicalQuantity source,
    required String targetCanonicalUnit,
    required String ingredientName,
  }) {
    if (source.unit == targetCanonicalUnit) return source.amount;
    final targetUnitDisplay =
        displayUnitForCanonical(targetCanonicalUnit, ingredientName);
    final convertedAmount = convertCanonicalToUnit(
      canonicalUnit: source.unit,
      canonicalAmount: source.amount,
      targetUnit: targetUnitDisplay,
      ingredientName: ingredientName,
    );
    final convertedCanonical = toCanonicalQuantity(
      convertedAmount,
      targetUnitDisplay,
      ingredientName,
    );
    if (convertedCanonical.unit != targetCanonicalUnit) return 0;
    return convertedCanonical.amount;
  }

  // ----- Estimation helpers for external plans (from JSON) -----
  double estimateTotalCostForPlanJson(Map<String, dynamic> planJson, List<IngredientModel> inventory) {
    final plan = MealPlan.fromJson(planJson);
    // Build consolidated map
    final map = <String, CanonicalQuantity>{};
    for (final day in plan.days) {
      for (final entry in day.meals) {
        final r = entry.recipe;
        final baseServ = r.servings == 0 ? 1 : r.servings;
        final mult = entry.servings / baseServ;
        for (final ri in r.ingredients) {
          final amt = ri.numericAmount * mult;
          final canon = toCanonicalQuantity(amt, ri.unit, ri.name);
          final key = normalizeName(ri.name);
          final prev = map[key];
          map[key] = prev == null ? canon : prev + canon;
        }
      }
    }
    // subtract inventory
    for (final inv in inventory) {
      final key = normalizeName(inv.name);
      if (!map.containsKey(key)) continue;
      final have = toCanonicalQuantity(inv.quantity.toDouble(), inv.unit, inv.name);
      final need = map[key]!;
      if (have.unit == need.unit) {
        final remain = need.subtract(have);
        if (remain.amount <= 0) {
          map.remove(key);
        } else {
          map[key] = remain;
        }
      }
    }
    // sum cost
    double total = 0;
    map.forEach((name, need) {
      final cat = guessCategory(name);
      final unit = need.unit; // canonical unit key
      final price = _pricePerUnit(cat, unit);
      total += need.amount * price;
    });
    return total;
  }

  double _pricePerUnit(String category, String canonUnit) {
    // canonUnit: 'gram'|'milliliter'|'piece'
    if (category == 'เนื้อสัตว์') return canonUnit == 'gram' ? 0.6 : 15;
    if (category == 'ผัก') return canonUnit == 'gram' ? 0.08 : 10;
    if (category == 'ผลไม้') return canonUnit == 'gram' ? 0.1 : 12;
    if (category == 'ผลิตภัณฑ์จากนม') return canonUnit == 'milliliter' ? 0.04 : 20;
    if (category == 'ข้าว' || category == 'แป้ง') return canonUnit == 'gram' ? 0.03 : 15;
    if (category == 'เครื่องเทศ') return canonUnit == 'gram' ? 0.2 : 20;
    if (category == 'เครื่องปรุง') return canonUnit == 'milliliter' ? 0.02 : 15;
    if (category == 'น้ำมัน') return canonUnit == 'milliliter' ? 0.05 : 25;
    if (category == 'เครื่องดื่ม') return 25; // per piece
    if (category == 'ของแช่แข็ง') return 50; // per piece
    return canonUnit == 'gram' ? 0.03 : 15; // default
  }

  // ----- Update slot status (done) -----
  void markEntryDone(DateTime date, String recipeId) {
    if (_plan == null) return;
    final days = _plan!.days.map((d) {
      if (d.date.year == date.year && d.date.month == date.month && d.date.day == date.day) {
        final meals = d.meals.map((m) {
          if (m.recipe.id == recipeId) return m.copyWith(done: true);
          return m;
        }).toList();
        return d.copyWith(meals: meals);
      }
      return d;
    }).toList();
    _plan = MealPlan(days: days, generatedAt: _plan!.generatedAt);
    notifyListeners();
  }

  // Mark a specific meal slot (by index) as done only for that slot
  void markEntryDoneAt(DateTime date, int mealIndex) {
    if (_plan == null) return;
    final days = _plan!.days.map((d) {
      if (d.date.year == date.year && d.date.month == date.month && d.date.day == date.day) {
        if (mealIndex < 0 || mealIndex >= d.meals.length) return d;
        final meals = [...d.meals];
        meals[mealIndex] = meals[mealIndex].copyWith(done: true);
        return d.copyWith(meals: meals);
      }
      return d;
    }).toList();
    _plan = MealPlan(days: days, generatedAt: _plan!.generatedAt);
    notifyListeners();
  }

  Future<void> loadPlanById(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meal_plans')
        .doc(id)
        .get();
    if (!doc.exists) return;
    final data = doc.data() as Map<String, dynamic>;
    final planJson = (data['plan'] as Map<String, dynamic>);
    _plan = MealPlan.fromJson(planJson);
    _driTargets ??= await _loadUserDriTargets();
    _dailySummaries = _buildDailySummaries();
    _dailyInsights = _buildLocalNutritionInsights();
    _weeklyTotals = _computeWeeklyTotals();
    _weeklyInsight = _buildLocalWeeklyInsight();
    _weeklyInsightBusy = false;
    notifyListeners();
    unawaited(_generateDailyNutritionInsights());
    unawaited(_generateWeeklyNutritionInsight());
  }

}

class DailyNutritionSummary {
  final DateTime date;
  final NutritionInfo totals;
  const DailyNutritionSummary({required this.date, required this.totals});
}
