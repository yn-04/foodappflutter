// lib/foodreccom/providers/enhanced_recommendation_provider.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:my_app/common/measurement_constants.dart';
import '../models/ingredient_model.dart';
import '../models/recipe/recipe.dart';
import '../models/cooking_history_model.dart';
import '../models/hybrid_models.dart';
import '../models/purchase_item.dart';
import '../services/hybrid_recipe_service.dart';
import '../services/ingredient_analytics_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/recipe/used_ingredient.dart';
import '../utils/thai_recipe_adapter.dart'; // ✅ ใช้ Google Translate
import '../services/user_recipe_service.dart';
import '../models/filter_options.dart';
import '../utils/ingredient_utils.dart';
import '../utils/ingredient_translator.dart';
import '../utils/allergy_utils.dart';
import '../services/nutrition_estimator.dart';

class EnhancedRecommendationProvider extends ChangeNotifier {
  static const int _minimumRecommendationCount = 12;
  static const Map<String, String> _dietGoalAliases = {
    'vegan': 'vegan',
    'วีแกน': 'vegan',
    'vegetarian': 'vegetarian',
    'มังสวิรัติ': 'vegetarian',
    'มังสวิรต': 'vegetarian',
    'lacto vegetarian': 'lacto-vegetarian',
    'lacto-vegetarian': 'lacto-vegetarian',
    'lacto': 'lacto-vegetarian',
    'ovo vegetarian': 'ovo-vegetarian',
    'ovo-vegetarian': 'ovo-vegetarian',
    'ovo': 'ovo-vegetarian',
    'pescatarian': 'pescatarian',
    'pescetarian': 'pescatarian',
    'คีโต': 'ketogenic',
    'ketogenic': 'ketogenic',
    'keto': 'ketogenic',
    'พาเลโอ': 'paleo',
    'paleo': 'paleo',
    'low-carb': 'low-carb',
    'low carb': 'low-carb',
    'low_carb': 'low-carb',
    'คาร์บต่ำ': 'low-carb',
    'high-protein': 'high-protein',
    'high protein': 'high-protein',
    'high_protein': 'high-protein',
    'โปรตีนสูง': 'high-protein',
    'low-fat': 'low-fat',
    'low fat': 'low-fat',
    'low_fat': 'low-fat',
    'ไขมันต่ำ': 'low-fat',
    'gluten-free': 'gluten-free',
    'gluten free': 'gluten-free',
    'glutenfree': 'gluten-free',
    'gluten_free': 'gluten-free',
    'ปลอดกลูเตน': 'gluten-free',
    'dairy-free': 'dairy-free',
    'dairy free': 'dairy-free',
    'dairyfree': 'dairy-free',
    'dairy_free': 'dairy-free',
    'ปลอดนม': 'dairy-free',
    'ไม่กินนม': 'dairy-free',
  };
  final HybridRecipeService _hybridService = HybridRecipeService();
  final IngredientAnalyticsService _analyticsService =
      IngredientAnalyticsService();
  final UserRecipeService _userRecipeService = UserRecipeService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<RecipeModel> _recommendations = [];
  List<RecipeModel> _userRecipes = [];
  List<IngredientModel> _ingredients = [];
  List<CookingHistory> _cookingHistory = [];
  Map<String, dynamic> _analyticsData = {};
  Map<String, List<String>> _stockSuggestions = {};
  bool _isLoading = false;
  bool _isAnalyzing = false;
  String? _error;
  String? _lastAnalysisReport;
  HybridRecommendationResult? _lastHybridResult;
  RecipeFilterOptions _filters = const RecipeFilterOptions();
  // ---- Health profile ----
  bool _healthLoaded = false;
  Set<String> _allergies = {};
  Set<String> _dietPreferences = {};
  int? _hpMinProtein;
  int? _hpMaxCarbs;
  int? _hpMaxFat;
  bool _userDietOverride = false;
  Set<String> _explicitDietGoals = {};
  final Map<String, int> _servingsOverrides = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ingredientSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _cookingHistorySub;
  Completer<void>? _ingredientInitialLoad;
  Completer<void>? _historyInitialLoad;
  Timer? _autoRefreshDebounce;
  bool _autoRefreshScheduledWhileLoading = false;
  bool _isDisposed = false;
  bool _hasReceivedIngredientSnapshot = false;
  bool _hasReceivedHistorySnapshot = false;
  bool _hasFetchedRecommendations = false;
  Timer? _ingredientExpiryTimer;

  // ---------- Getters ----------
  List<RecipeModel> get recommendations => _recommendations;
  List<IngredientModel> get ingredients => _ingredients;
  List<RecipeModel> get userRecipes => _userRecipes;
  List<RecipeModel> get userRecommendations =>
      _recommendations.where(_isUserRecipe).toList();
  List<RecipeModel> get hybridRecommendations =>
      _recommendations.where((r) => !_isUserRecipe(r)).toList();
  List<RecipeModel> get aiRecommendations =>
      _recommendations.where(_isAiRecipe).toList();
  List<RecipeModel> get simpleMatchedRecipes => _selectSimpleMatchedRecipes();
  List<String> get availableIngredientNames {
    final seen = <String>{};
    final names = <String>[];
    for (final item in _ingredients) {
      if (item.isExpired) continue;
      if (!item.quantity.isFinite || item.quantity < 1) continue;
      final raw = item.name.trim();
      if (raw.isEmpty) continue;
      final key = _norm(raw);
      if (key.isEmpty) continue;
      if (seen.add(key)) {
        names.add(raw);
      }
    }
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Set<String> _normalizeDietGoals(Iterable<String> goals) {
    final normalized = <String>{};
    for (final goal in goals) {
      final key = goal.trim().toLowerCase();
      if (key.isEmpty) continue;
      normalized.add(_dietGoalAliases[key] ?? key);
    }
    return normalized;
  }

  Set<String> _effectiveDietGoalsForRequest() {
    return <String>{
      ..._dietPreferences,
      ...(_userDietOverride ? _explicitDietGoals : _filters.dietGoals),
    };
  }

  bool _isUserRecipe(RecipeModel recipe) {
    final source = (recipe.source ?? '').trim().toLowerCase();
    if (source.isNotEmpty &&
        (source.contains('ผู้ใช้') || source.contains('user'))) {
      return true;
    }
    if (recipe.tags.any((tag) {
      final lower = tag.trim().toLowerCase();
      return lower.contains('ผู้ใช้') || lower.contains('user');
    })) {
      return true;
    }
    if (_userRecipes.any((r) => r.id == recipe.id)) {
      return true;
    }
    final reason = recipe.reason.trim().toLowerCase();
    if (reason.contains('ผู้ใช้') || reason.contains('user')) {
      return true;
    }
    return false;
  }

  bool _isAiRecipe(RecipeModel recipe) {
    if (_isUserRecipe(recipe)) return false;
    if (recipe.tags.any((tag) => tag.trim().toLowerCase() == 'ai')) {
      return true;
    }
    final source = (recipe.source ?? '').trim().toLowerCase();
    if (source.contains('ai model')) return true;
    final reason = recipe.reason.trim().toLowerCase();
    if (reason.contains('ai') && reason.contains('match score')) {
      return true;
    }
    return false;
  }

  List<CookingHistory> get cookingHistory => _cookingHistory;
  Map<String, dynamic> get analyticsData => _analyticsData;
  Map<String, List<String>> get stockSuggestions => _stockSuggestions;
  bool get isLoading => _isLoading;
  bool get isAnalyzing => _isAnalyzing;
  String? get error => _error;
  String? get lastAnalysisReport => _lastAnalysisReport;
  HybridRecommendationResult? get lastHybridResult => _lastHybridResult;
  RecipeFilterOptions get filters => _filters;
  Set<String> get allergies => _allergies;
  int? getServingsOverride(String recipeId) => _servingsOverrides[recipeId];

  void setServingsOverride(String recipeId, int servings) {
    if (servings <= 0) {
      if (_servingsOverrides.remove(recipeId) != null) {
        notifyListeners();
      }
      return;
    }
    final previous = _servingsOverrides[recipeId];
    if (previous == servings) return;
    _servingsOverrides[recipeId] = servings;
    notifyListeners();
  }

  // ---------- Ingredient Categorization ----------
  List<IngredientModel> get urgentExpiryIngredients =>
      _ingredients.where((i) => i.isUrgentExpiry).toList();

  List<IngredientModel> get nearExpiryIngredients =>
      _ingredients.where((i) => i.isNearExpiry && !i.isUrgentExpiry).toList();

  List<IngredientModel> get frequentlyUsedIngredients =>
      _ingredients.where((i) => i.isFrequentlyUsed && !i.isNearExpiry).toList();

  List<IngredientModel> get underutilizedIngredients =>
      _ingredients.where((i) => i.isUnderutilized).toList();

  List<IngredientModel> get highValueIngredients =>
      _ingredients.where((i) => (i.price ?? 0) > 50).toList();

  List<IngredientModel> get priorityIngredients {
    final sorted = [..._ingredients]
      ..sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return sorted.take(10).toList();
  }

  // ---------- Load Ingredients ----------
  Future<void> loadIngredients() async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (_ingredientSub != null) {
      return _ingredientInitialLoad?.future ?? Future.value();
    }

    final completer = Completer<void>();
    _ingredientInitialLoad = completer;

    final collection = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('raw_materials');

    _ingredientSub = collection.snapshots().listen(
      (snapshot) async {
        final items = snapshot.docs
            .map((doc) => IngredientModel.fromFirestore(doc.data()))
            .where((item) => !item.isExpired)
            .toList();

        final deduped = _dedupeIngredients(items);
        final sorted = await compute(_sortIngredientsByPriority, deduped);
        final hadInitialSnapshot = _hasReceivedIngredientSnapshot;
        _hasReceivedIngredientSnapshot = true;
        if (_isDisposed) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        if (_ingredientsChanged(sorted)) {
          _ingredients = sorted;
          _scheduleExpiryWatcher(sorted);
          final pruned = _pruneManualIngredientSelections();
          notifyListeners();
          if (pruned || hadInitialSnapshot || _hasFetchedRecommendations) {
            _scheduleAutoRefresh();
          }
        }
        if (!completer.isCompleted) completer.complete();
      },
      onError: (error, stack) {
        debugPrint('❌ Error streaming ingredients: $error');
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  static List<IngredientModel> _sortIngredientsByPriority(
    List<IngredientModel> items,
  ) {
    items.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return items;
  }

  // ---------- De-duplicate ingredients by name (data level) ----------
  // รวมรายการชื่อเดียวกันให้เป็นอันเดียว พยายามแปลงหน่วย kg/g และ l/ml
  // หมายเหตุ: ดำเนินการในหน่วยความจำเท่านั้น ไม่เขียนทับ Firestore
  List<IngredientModel> _dedupeIngredients(List<IngredientModel> items) {
    if (items.isEmpty) return items;

    final groups = <String, List<IngredientModel>>{};
    for (final it in items) {
      final normName = _norm(it.name);
      if (normName.isEmpty) continue;
      final key = '$normName|${_expiryKey(it.expiryDate)}';
      (groups[key] ??= <IngredientModel>[]).add(it);
    }

    final out = <IngredientModel>[];
    for (final entry in groups.entries) {
      final list = entry.value;
      if (list.isEmpty) continue;

      // เลือกชื่อเดิมแบบ trim
      final displayName = list.first.name.trim();

      // เลือก unit เป้าหมาย: ถ้ามีกรัม/กิโลกรัม → ใช้กรัม, ถ้ามีมล./ลิตร → ใช้มิลลิลิตร, ไม่งั้นใช้ unit ที่พบบ่อยสุด
      final units = list
          .map((e) => (e.unit.trim().isEmpty ? '' : e.unit.trim()))
          .toList();
      String targetUnit = _pickTargetUnit(units);

      // รวมปริมาณหลังแปลงหน่วย ถ้าแปลงไม่ได้จะรวมเฉพาะที่ unit ตรงกัน
      double totalQty = 0;
      for (final it in list) {
        final q = _convertQuantityDouble(
          it.quantity,
          it.unit.trim(),
          targetUnit,
        );
        if (q != null) {
          totalQty += q;
        } else if (it.unit.trim().toLowerCase() == targetUnit.toLowerCase()) {
          totalQty += it.quantity;
        } else {
          // หน่วยเข้ากันไม่ได้: บวกไม่ได้ ข้าม
        }
      }

      // คำนวณฟิลด์อื่น ๆ แบบ safe
      final category = _mostFrequentNonEmpty(list.map((e) => e.category));
      final price = list
          .map((e) => e.price ?? 0)
          .fold<double>(0, (a, b) => a + b);
      final usageCount = list
          .map((e) => e.usageCount)
          .fold<int>(0, (a, b) => a + b);
      final lastUsed = list
          .map((e) => e.lastUsedDate)
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (a, b) => a == null ? b : (b.isAfter(a) ? b : a),
          );
      final addedDate = list
          .map((e) => e.addedDate)
          .fold<DateTime?>(
            null,
            (a, b) => a == null ? b : (b.isBefore(a) ? b : a),
          );
      final expiry = list
          .map((e) => e.expiryDate)
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (a, b) => a == null ? b : (b.isBefore(a) ? b : a),
          );
      final utilization = list.isEmpty
          ? 0.0
          : list.map((e) => e.utilizationRate).reduce((a, b) => a + b) /
                list.length;
      double? pickFirstDouble(Iterable<double?> values) {
        for (final v in values) {
          if (v != null) return v;
        }
        return null;
      }

      out.add(
        IngredientModel(
          name: displayName,
          quantity: totalQty,
          unit: targetUnit,
          category: category ?? '',
          expiryDate: expiry,
          price: price == 0 ? null : price,
          notes: list.first.notes,
          addedDate: addedDate,
          usageCount: usageCount,
          lastUsedDate: lastUsed,
          utilizationRate: utilization,
          fatPer100g: pickFirstDouble(list.map((e) => e.fatPer100g)),
          saturatedFatPer100g: pickFirstDouble(
            list.map((e) => e.saturatedFatPer100g),
          ),
          sugarPer100g: pickFirstDouble(list.map((e) => e.sugarPer100g)),
          saltPer100g: pickFirstDouble(list.map((e) => e.saltPer100g)),
        ),
      );
    }

    return out;
  }

  String _expiryKey(DateTime? date) {
    if (date == null) return 'none';
    final d = DateTime(date.year, date.month, date.day);
    return d.toIso8601String();
  }

  String _pickTargetUnit(List<String> units) {
    final normalized = units
        .map((u) => u.trim())
        .where((u) => u.isNotEmpty)
        .toList();
    if (normalized.any((u) => u == 'กรัม' || u == 'กิโลกรัม')) return 'กรัม';
    if (normalized.any((u) => u == 'มิลลิลิตร' || u == 'ลิตร'))
      return 'มิลลิลิตร';
    if (normalized.isEmpty) return '';
    // เลือก unit ที่พบบ่อยสุด
    final counts = <String, int>{};
    for (final u in normalized) {
      counts[u] = (counts[u] ?? 0) + 1;
    }
    counts.entries.toList().sort((a, b) => b.value.compareTo(a.value));
    return counts.entries.first.key;
  }

  double? _convertQuantityDouble(double qty, String from, String to) {
    final f = from.trim();
    final t = to.trim();
    if (f.isEmpty || t.isEmpty) return null;
    if (f == t) return qty;
    // kg <-> g (SI: prefix kilo = 10^3)
    if (f == 'กิโลกรัม' && t == 'กรัม') {
      return qty * MeasurementConstants.gramsPerKilogram;
    }
    if (f == 'กรัม' && t == 'กิโลกรัม') {
      return qty / MeasurementConstants.gramsPerKilogram;
    }
    // liter <-> milliliter (SI: prefix milli = 10^-3)
    if (f == 'ลิตร' && t == 'มิลลิลิตร') {
      return qty * MeasurementConstants.millilitersPerLiter;
    }
    if (f == 'มิลลิลิตร' && t == 'ลิตร') {
      return qty / MeasurementConstants.millilitersPerLiter;
    }
    return null; // incompatible
  }

  String? _mostFrequentNonEmpty(Iterable<String> values) {
    final counts = <String, int>{};
    for (final v in values) {
      final s = (v).trim();
      if (s.isEmpty) continue;
      counts[s] = (counts[s] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    counts.entries.toList().sort((a, b) => b.value.compareTo(a.value));
    return counts.entries.first.key;
  }

  // ---------- Load Cooking History ----------
  Future<void> loadCookingHistory() async {
    final user = _auth.currentUser;
    if (user == null) return;

    if (_cookingHistorySub != null) {
      return _historyInitialLoad?.future ?? Future.value();
    }

    final completer = Completer<void>();
    _historyInitialLoad = completer;

    final query = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('cooking_history')
        .orderBy('cooked_at', descending: true);

    _cookingHistorySub = query.snapshots().listen(
      (snapshot) {
        final cutoff = DateTime.now().subtract(const Duration(days: 30));
        final histories = snapshot.docs
            .map((doc) {
              final data = Map<String, dynamic>.from(doc.data());
              data.putIfAbsent('id', () => doc.id);
              return CookingHistory.fromFirestore(data);
            })
            .where((history) {
              return !history.cookedAt.isBefore(cutoff);
            })
            .toList();

        final hadInitialSnapshot = _hasReceivedHistorySnapshot;
        _hasReceivedHistorySnapshot = true;
        if (_isDisposed) {
          if (!completer.isCompleted) completer.complete();
          return;
        }
        if (_cookingHistoryChanged(histories)) {
          _cookingHistory = histories;
          notifyListeners();
          if (hadInitialSnapshot || _hasFetchedRecommendations) {
            _scheduleAutoRefresh();
          }
        }

        if (!completer.isCompleted) completer.complete();
      },
      onError: (error, stack) {
        debugPrint('❌ Error streaming cooking history: $error');
        if (!completer.isCompleted) completer.complete();
      },
    );

    return completer.future;
  }

  // ---------- Hybrid Recommendations ----------
  Future<void> getHybridRecommendations() async {
    if (_ingredients.isEmpty) {
      await loadIngredients();
    }

    if (_ingredients.isEmpty) {
      _error = 'ไม่มีวัตถุดิบในระบบ กรุณาเพิ่มวัตถุดิบก่อน';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Load health profile once
      if (!_healthLoaded) {
        await _loadHealthProfile();
      }
      if (_cookingHistory.isEmpty) {
        await loadCookingHistory();
      }

      // โหลดสูตรของผู้ใช้ควบคู่
      try {
        _userRecipes = await _userRecipeService.getUserRecipes();
      } catch (_) {}

      final activeDietGoals = _effectiveDietGoalsForRequest();
      final normalizedDietGoals = _normalizeDietGoals(activeDietGoals);

      String _formatCalories() {
        final min = _filters.minCalories;
        final max = _filters.maxCalories;
        if (min == null && max == null) return 'ไม่กำหนด';
        if (min != null && max != null) return '$min-$max kcal';
        if (min != null) return '≥ $min kcal';
        return '≤ $max kcal';
      }

      String _formatMacros({
        required int? minProtein,
        required int? maxCarbs,
        required int? maxFat,
      }) {
        final parts = <String>[];
        if (minProtein != null) parts.add('โปรตีน ≥ $minProtein g');
        if (maxCarbs != null) parts.add('คาร์บ ≤ $maxCarbs g');
        if (maxFat != null) parts.add('ไขมัน ≤ $maxFat g');
        return parts.isEmpty ? 'ไม่กำหนด' : parts.join(', ');
      }

      final manualIngredientNames = _filters.manualIngredientNames;
      int? _macroValue(int? manual, int? fallback) => manual ?? fallback;
      final hasHighProtein = normalizedDietGoals.contains('high-protein');
      final hasLowCarb =
          normalizedDietGoals.contains('low-carb') ||
          normalizedDietGoals.contains('ketogenic');
      final hasLowFat = normalizedDietGoals.contains('low-fat');

      final effectiveMinProtein = hasHighProtein
          ? _macroValue(_filters.minProtein, _hpMinProtein)
          : null;
      final effectiveMaxCarbs = hasLowCarb
          ? _macroValue(_filters.maxCarbs, _hpMaxCarbs)
          : null;
      final effectiveMaxFat = hasLowFat
          ? _macroValue(_filters.maxFat, _hpMaxFat)
          : null;

      final filterLog = StringBuffer()
        ..write('👤 ฟิลเตอร์ผู้ใช้ → ')
        ..write(
          'ประเภทอาหาร: ${_filters.cuisineEn.isEmpty ? 'ทั้งหมด' : _filters.cuisineEn.join(', ')} | ',
        )
        ..write(
          'ข้อจำกัดด้านอาหาร: ${normalizedDietGoals.isEmpty ? 'ไม่เลือก' : normalizedDietGoals.join(', ')} | ',
        )
        ..write('แคลอรี่: ${_formatCalories()} | ')
        ..write(
          'แมโคร: ${_formatMacros(minProtein: effectiveMinProtein, maxCarbs: effectiveMaxCarbs, maxFat: effectiveMaxFat)} | ',
        )
        ..write(
          'วัตถุดิบที่เลือกเอง: ${manualIngredientNames == null || manualIngredientNames.isEmpty ? 'ให้ระบบเลือก' : manualIngredientNames.join(', ')} | ',
        )
        ..write(
          'หลีกเลี่ยง: ${_allergies.isEmpty ? 'ไม่มี' : _allergies.join(', ')}',
        );
      debugPrint(filterLog.toString());

      final result = await _hybridService.getHybridRecommendations(
        _ingredients,
        cookingHistory: _cookingHistory,
        manualSelectedIngredients: _resolveManualSelectedIngredients(),
        cuisineFilters: _filters.cuisineEn,
        dietGoals: normalizedDietGoals,
        minCalories: _filters.minCalories,
        maxCalories: _filters.maxCalories,
        minProtein: effectiveMinProtein,
        maxCarbs: effectiveMaxCarbs,
        maxFat: effectiveMaxFat,
        excludeIngredients: _allergies.toList(),
      );

      _lastHybridResult = result;

      // ✅ รวมสูตรผู้ใช้ + AI + ภายนอก (ผู้ใช้มาก่อน)
      final ai = result.aiRecommendations;
      final external = result.externalRecipes;
      final merged = <RecipeModel>[];
      final seenIds = <String>{};
      for (final recipe in [..._userRecipes, ...ai, ...external]) {
        if (seenIds.add(recipe.id)) {
          merged.add(recipe);
        }
      }
      final recipes = merged;

      if (recipes.isEmpty) {
        debugPrint("⚠️ ไม่มีเมนูจาก RapidAPI → ใช้ fallback");
        _recommendations = [
          RecipeModel(
            id: 'fallback_basic',
            name: 'ข้าวผัดไข่',
            originalName: 'ข้าวผัดไข่',
            description: 'เมนูง่าย ๆ ใช้วัตถุดิบพื้นฐาน',
            matchScore: 60,
            reason: 'แนะนำ fallback เพราะไม่มีเมนูจาก API',
            ingredients: [],
            missingIngredients: [],
            steps: [],
            cookingTime: 10,
            prepTime: 5,
            difficulty: 'ง่าย',
            servings: 1,
            category: 'อาหารจานหลัก',
            nutrition: NutritionInfo(
              calories: 350,
              protein: 12,
              carbs: 45,
              fat: 8,
              fiber: 1,
              sodium: 400,
            ),
            source: 'Fallback',
          ),
        ];
      } else {
        // แปลเป็นภาษาไทยก่อน เพื่อให้ชื่อวัตถุดิบตรงกับสต็อกผู้ใช้
        final translated = await ThaiRecipeAdapter.translateRecipes(recipes);
        final safe = translated.where((r) => !_containsAllergen(r)).toList();
        final computed = safe
            .map(
              (r) =>
                  r.copyWith(missingIngredients: _computeMissingIngredients(r)),
            )
            .toList();
        final computedMap = {for (final recipe in computed) recipe.id: recipe};
        result.aiRecommendations = result.aiRecommendations.map((recipe) {
          final updated = computedMap[recipe.id];
          return updated ?? recipe;
        }).toList();
        result.externalRecipes = result.externalRecipes.map((recipe) {
          final updated = computedMap[recipe.id];
          return updated ?? recipe;
        }).toList();
        result.combinedRecommendations = [
          ...result.aiRecommendations,
          ...result.externalRecipes,
        ];
        _recommendations = computed;
      }

      if (_recommendations.isEmpty) {
        _error = 'ไม่สามารถแนะนำเมนูได้ กรุณาลองใหม่อีกครั้ง';
      } else if (_recommendations.length < _minimumRecommendationCount) {
        _appendFallbackRecommendations();
      }
    } catch (e, st) {
      debugPrint('❌ Hybrid Recommendation Error: $e');
      debugPrintStack(stackTrace: st);

      _error = 'เกิดข้อผิดพลาด: ${e.toString()}';
      _recommendations = [];
    } finally {
      _resetUserFiltersAfterUse();
      _isLoading = false;
      _hasFetchedRecommendations = true;
      notifyListeners();
      if (_autoRefreshScheduledWhileLoading) {
        _autoRefreshScheduledWhileLoading = false;
      }
    }
  }

  void _resetUserFiltersAfterUse() {
    final manualNames = _filters.manualIngredientNames;
    final hasManual = manualNames != null && manualNames.isNotEmpty;
    final hasCuisine = _filters.cuisineEn.isNotEmpty;
    final hasDietOverride = !setEquals(_filters.dietGoals, _dietPreferences);
    final hasProteinOverride = _filters.minProtein != _hpMinProtein;
    final hasCarbOverride = _filters.maxCarbs != _hpMaxCarbs;
    final hasFatOverride = _filters.maxFat != _hpMaxFat;

    final shouldReset =
        hasManual ||
        hasCuisine ||
        hasDietOverride ||
        hasProteinOverride ||
        hasCarbOverride ||
        hasFatOverride;
    if (!shouldReset) return;

    final reset = RecipeFilterOptions(
      cuisineEn: const [],
      dietGoals: Set<String>.from(_dietPreferences),
      minCalories: _filters.minCalories,
      maxCalories: _filters.maxCalories,
      minProtein: _hpMinProtein,
      maxCarbs: _hpMaxCarbs,
      maxFat: _hpMaxFat,
      manualIngredientNames: null,
    );
    _filters = reset;
    _explicitDietGoals = {};
    _userDietOverride = false;
    debugPrint('♻️ รีเซ็ตฟิลเตอร์ผู้ใช้หลังประมวลผลคำแนะนำ');
  }

  void _appendFallbackRecommendations() {
    final needed = _minimumRecommendationCount - _recommendations.length;
    if (needed <= 0) return;
    // ยกเลิกการเติมเมนูสำรองเพื่อหลีกเลี่ยงสูตรที่ไม่ได้มาจาก Spoonacular
  }

  Future<void> _loadHealthProfile() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      final snap = await _firestore.collection('users').doc(user.uid).get();
      final data = snap.data();
      if (data == null) return;
      final hp = data['healthProfile'];
      if (hp is Map<String, dynamic>) {
        // allergies: String or List
        final alg = hp['allergies'];
        final set = <String>{};
        if (alg is String)
          set.addAll(
            alg
                .split(',')
                .map((e) => e.trim().toLowerCase())
                .where((e) => e.isNotEmpty),
          );
        if (alg is List)
          set.addAll(
            alg.whereType<String>().map((e) => e.trim().toLowerCase()),
          );
        _allergies = set;

        // dietPreferences
        final diets = hp['dietPreferences'];
        var normalizedPrefs = <String>{};
        if (diets is List) {
          final raw = diets
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty);
          normalizedPrefs = _normalizeDietGoals(raw);
        }
        _dietPreferences = normalizedPrefs;
        if (!_userDietOverride &&
            !setEquals(_filters.dietGoals, normalizedPrefs)) {
          _filters =
              _filters.copyWith(dietGoals: Set<String>.from(normalizedPrefs));
        }
        // nutritionTargetsPerMeal
        int? _readInt(dynamic v) {
          if (v == null) return null;
          if (v is int) return v;
          if (v is double) return v.round();
          return int.tryParse(v.toString());
        }

        double? _readDouble(dynamic v) {
          if (v == null) return null;
          if (v is num) return v.toDouble();
          return double.tryParse(v.toString());
        }

        int? _perMeal(dynamic total) {
          final value = _readDouble(total);
          if (value == null) return null;
          return (value / 3).round();
        }

        final dri = hp['dri'];
        if (dri is Map<String, dynamic>) {
          final proteinPerMeal = _perMeal(dri['protein_g']);
          final carbMaxPerMeal = _perMeal(dri['carb_max_g']);
          final fatMinPerMeal = _perMeal(dri['fat_min_g']);
          final fatMaxPerMeal = _perMeal(dri['fat_max_g']);
          if (proteinPerMeal != null) _hpMinProtein = proteinPerMeal;
          if (carbMaxPerMeal != null) _hpMaxCarbs = carbMaxPerMeal;
          if (fatMinPerMeal != null) _hpMaxFat = fatMinPerMeal;
        } else {
          final nt = hp['nutritionTargetsPerMeal'];
          if (nt is Map<String, dynamic>) {
            final p = nt['โปรตีน'] ?? nt['protein'];
            if (p is Map<String, dynamic>) _hpMinProtein = _readInt(p['min']);
            final c = nt['คาร์บ'] ?? nt['carbs'];
            if (c is Map<String, dynamic>) _hpMaxCarbs = _readInt(c['max']);
            final f = nt['ไขมัน'] ?? nt['fat'];
            if (f is Map<String, dynamic>) _hpMaxFat = _readInt(f['max']);
          }
        }

        final hasManualProtein = _filters.minProtein != null;
        final hasManualCarb = _filters.maxCarbs != null;
        final hasManualFat = _filters.maxFat != null;

        if (!hasManualProtein || !hasManualCarb || !hasManualFat) {
          setMacroThresholds(
            minProtein: hasManualProtein ? _filters.minProtein : _hpMinProtein,
            maxCarbs: hasManualCarb ? _filters.maxCarbs : _hpMaxCarbs,
            maxFat: hasManualFat ? _filters.maxFat : _hpMaxFat,
          );
        }
      }
    } catch (e) {
      debugPrint('healthProfile load error: $e');
    }
    _healthLoaded = true;
  }

  void invalidateHealthProfileCache() {
    _healthLoaded = false;
  }

  Map<String, dynamic> _buildHealthProfileForAI() {
    final map = <String, dynamic>{};
    if (_allergies.isNotEmpty) {
      map['allergies'] = _allergies.toList();
    }
    if (_dietPreferences.isNotEmpty) {
      map['diet_preferences'] = _dietPreferences.toList();
    }
    final macroTargets = <String, Map<String, int>>{};
    final effectiveGoals = _effectiveDietGoalsForRequest();
    int? _macroValue(int? manual, int? fallback) => manual ?? fallback;
    if (effectiveGoals.contains('high-protein')) {
      final proteinSource = _macroValue(_filters.minProtein, _hpMinProtein);
      if (proteinSource != null) {
        macroTargets['protein'] = {'min': proteinSource};
      }
    }
    if (effectiveGoals.contains('low-carb') ||
        effectiveGoals.contains('ketogenic')) {
      final carbSource = _macroValue(_filters.maxCarbs, _hpMaxCarbs);
      if (carbSource != null) {
        macroTargets['carbs'] = {'max': carbSource};
      }
    }
    if (effectiveGoals.contains('low-fat')) {
      final fatSource = _macroValue(_filters.maxFat, _hpMaxFat);
      if (fatSource != null) {
        macroTargets['fat'] = {'max': fatSource};
      }
    }
    if (macroTargets.isNotEmpty) {
      map['macro_targets_per_meal'] = macroTargets;
    }
    if (_filters.minCalories != null || _filters.maxCalories != null) {
      map['calorie_preferences'] = {
        if (_filters.minCalories != null) 'min_per_meal': _filters.minCalories,
        if (_filters.maxCalories != null) 'max_per_meal': _filters.maxCalories,
      };
    }
    return map;
  }

  String? _buildDietaryNotesForAI() {
    final parts = <String>[];
    final activeDietGoals = _effectiveDietGoalsForRequest();
    if (activeDietGoals.isNotEmpty) {
      parts.add('ข้อจำกัดอาหาร: ${activeDietGoals.join(', ')}');
    }
    if (_dietPreferences.isNotEmpty) {
      parts.add('ความชอบด้านอาหาร: ${_dietPreferences.join(', ')}');
    }
    if (_filters.minCalories != null || _filters.maxCalories != null) {
      final min = _filters.minCalories;
      final max = _filters.maxCalories;
      if (min != null && max != null) {
        parts.add('พลังงานต่อมื้อระหว่าง $min-$max kcal');
      } else if (min != null) {
        parts.add('พลังงานต่อมื้ออย่างน้อย $min kcal');
      } else if (max != null) {
        parts.add('พลังงานต่อมื้อไม่เกิน $max kcal');
      }
    }
    return parts.isEmpty ? null : parts.join(' • ');
  }

  bool _containsAllergen(RecipeModel r) {
    if (_allergies.isEmpty) return false;
    final expansion = AllergyUtils.expandAllergens(_allergies);
    if (expansion.all.isEmpty) return false;
    for (final ingredient in r.ingredients) {
      if (AllergyUtils.matchesAllergen(ingredient.name, expansion.all)) {
        return true;
      }
    }
    return false;
  }

  // -------- Helper: คำนวณวัตถุดิบที่ขาด --------
  List<String> _computeMissingIngredients(RecipeModel recipe) {
    // Inventory names (Thai) and translated to English for cross-lang match
    final thaiInv = _ingredients.map((i) => _norm(i.name)).toList();
    final engInv = IngredientTranslator.translateList(
      _ingredients.map((i) => i.name).toList(),
    ).map(_norm).toList();

    bool matchAny(String need) {
      final nThai = _norm(need);
      // 1) Direct Thai fuzzy match
      if (thaiInv.any((have) => ingredientsMatch(have, nThai))) return true;
      // 2) Cross-language: translate needed to English and compare
      final nEng = _norm(IngredientTranslator.translate(need));
      if (nEng.isNotEmpty &&
          engInv.any((have) => have.contains(nEng) || nEng.contains(have))) {
        return true;
      }
      return false;
    }

    final missing = <String>[];
    for (final ing in recipe.ingredients) {
      final need = ing.name.trim();
      if (need.isEmpty) continue;
      if (!matchAny(need)) missing.add(need);
    }

    // unique, preserve order
    final seen = <String>{};
    final unique = <String>[];
    for (final m in missing) {
      final key = _norm(m);
      if (seen.add(key)) unique.add(m);
    }
    return unique;
  }

  bool _ingredientsChanged(List<IngredientModel> next) {
    if (_ingredients.length != next.length) return true;
    for (var i = 0; i < next.length; i++) {
      final a = _ingredients[i];
      final b = next[i];
      if (a.name != b.name) return true;
      if (a.unit != b.unit) return true;
      if ((a.quantity - b.quantity).abs() > 0.0001) return true;
      final aExpiry = a.expiryDate?.millisecondsSinceEpoch ?? 0;
      final bExpiry = b.expiryDate?.millisecondsSinceEpoch ?? 0;
      if (aExpiry != bExpiry) return true;
    }
    return false;
  }

  bool _pruneManualIngredientSelections() {
    final manualNames = _filters.manualIngredientNames;
    if (manualNames == null || manualNames.isEmpty) return false;
    final available = availableIngredientNames.map(_norm).toSet();
    final retained = manualNames
        .where((name) => available.contains(_norm(name)))
        .toList();
    if (retained.length == manualNames.length) return false;
    _filters = _filters.copyWith(
      manualIngredientNames: retained.isEmpty ? null : retained,
    );
    return true;
  }

  void _scheduleExpiryWatcher(List<IngredientModel> current) {
    _ingredientExpiryTimer?.cancel();
    if (current.isEmpty) return;
    final now = DateTime.now();
    final upcoming = current
        .map((i) => i.expiryDate)
        .whereType<DateTime>()
        .where((d) => d.isAfter(now))
        .toList();
    if (upcoming.isEmpty) return;
    final nextExpiry = upcoming.reduce((a, b) => a.isBefore(b) ? a : b);
    var delay = nextExpiry.difference(now);
    if (delay.isNegative) {
      delay = const Duration(seconds: 1);
    } else {
      delay += const Duration(minutes: 1);
    }
    _ingredientExpiryTimer = Timer(delay, _handleExpiryTick);
  }

  void _handleExpiryTick() {
    if (_isDisposed) return;
    final filtered = _ingredients.where((i) => !i.isExpired).toList();
    if (_ingredientsChanged(filtered)) {
      _ingredients = filtered;
      _scheduleExpiryWatcher(filtered);
      final pruned = _pruneManualIngredientSelections();
      notifyListeners();
      _scheduleAutoRefresh();
      return;
    }
    _scheduleExpiryWatcher(_ingredients);
  }

  bool _cookingHistoryChanged(List<CookingHistory> next) {
    if (_cookingHistory.length != next.length) return true;
    for (var i = 0; i < next.length; i++) {
      final a = _cookingHistory[i];
      final b = next[i];
      if (a.id != b.id) return true;
      if (a.cookedAt.millisecondsSinceEpoch !=
          b.cookedAt.millisecondsSinceEpoch) {
        return true;
      }
      if (a.servingsMade != b.servingsMade) return true;
    }
    return false;
  }

  void _scheduleAutoRefresh({
    Duration delay = const Duration(milliseconds: 600),
  }) {
    if (_isDisposed) return;
    _autoRefreshDebounce?.cancel();
    _autoRefreshDebounce = null;
    _autoRefreshScheduledWhileLoading = false;
    // การแนะนำเมนูอัตโนมัติถูกปิดไว้ ให้ผู้ใช้กดปุ่มรีเฟรชเองเท่านั้น
  }

  List<RecipeModel> _selectSimpleMatchedRecipes() {
    if (_recommendations.isEmpty) return [];

    const rules = [
      _SimpleRule(maxIngredients: 6, maxMissing: 0, minRatio: 0.85),
      _SimpleRule(maxIngredients: 8, maxMissing: 1, minRatio: 0.75),
      _SimpleRule(maxIngredients: 12, maxMissing: 2, minRatio: 0.6),
    ];

    final picks = <RecipeModel>[];
    final seen = <String>{};
    final base = hybridRecommendations.where((r) => !_isAiRecipe(r)).toList();

    for (final rule in rules) {
      final candidates = <_SimpleCandidate>[];

      for (final recipe in base) {
        if (seen.contains(recipe.id)) continue;
        final ingredientCount = _countUniqueIngredients(recipe);
        if (ingredientCount == 0 || ingredientCount > rule.maxIngredients) {
          continue;
        }
        final missingCount = recipe.missingIngredients.length;
        if (missingCount > rule.maxMissing) continue;
        final ratio = recipe.matchRatio > 0
            ? recipe.matchRatio
            : recipe.matchScore / 100;
        if (ratio < rule.minRatio) continue;

        candidates.add(
          _SimpleCandidate(
            recipe: recipe,
            ingredientCount: ingredientCount,
            missingCount: missingCount,
            ratio: ratio,
          ),
        );
      }

      candidates.sort(_compareSimpleCandidates);

      for (final candidate in candidates) {
        if (seen.add(candidate.recipe.id)) {
          picks.add(candidate.recipe);
        }
        if (picks.length >= 3) break;
      }

      if (picks.length >= 3) break;
    }

    return picks.take(3).toList();
  }

  int _compareSimpleCandidates(_SimpleCandidate a, _SimpleCandidate b) {
    final missingCompare = a.missingCount.compareTo(b.missingCount);
    if (missingCompare != 0) return missingCompare;

    final ingredientCompare = a.ingredientCount.compareTo(b.ingredientCount);
    if (ingredientCompare != 0) return ingredientCompare;

    final ratioCompare = b.ratio.compareTo(a.ratio);
    if (ratioCompare != 0) return ratioCompare;

    return a.recipe.name.toLowerCase().compareTo(b.recipe.name.toLowerCase());
  }

  int _countUniqueIngredients(RecipeModel recipe) {
    final unique = <String>{};
    for (final ingredient in recipe.ingredients) {
      final key = _norm(ingredient.name);
      if (key.isNotEmpty) unique.add(key);
    }
    return unique.length;
  }

  String _norm(String s) {
    var out = s.trim().toLowerCase();
    out = out.replaceAll(RegExp(r"\(.*?\)"), ""); // remove (...) notes
    out = out.replaceAll(RegExp(r"\s+"), " ").trim();
    return out;
  }

  // ---------- User Recipes CRUD ----------
  Future<void> addUserRecipe(RecipeModel recipe) async {
    try {
      final needsNutrition = recipe.nutrition.calories <= 0 &&
          recipe.nutrition.protein <= 0 &&
          recipe.nutrition.carbs <= 0 &&
          recipe.nutrition.fat <= 0 &&
          recipe.nutrition.fiber <= 0 &&
          recipe.nutrition.sodium <= 0;
      final enriched = needsNutrition
          ? recipe.copyWith(
              nutrition: NutritionEstimator.estimateForRecipe(recipe),
            )
          : recipe;

      await _userRecipeService.addUserRecipe(enriched);
      await _userRecipeService.syncDraftsToCloud();
      _userRecipes = await _userRecipeService.getUserRecipes();
      // นำหน้าในรายการแนะนำโดยตัดรายการซ้ำ
      final external = _recommendations
          .where((r) => !_isUserRecipe(r))
          .toList();
      _recommendations = [..._userRecipes, ...external];
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error addUserRecipe: $e');
      rethrow;
    }
  }

  // ---------- Filters ----------
  void setCuisineFilters(List<String> cuisinesEn) {
    _filters = _filters.copyWith(cuisineEn: cuisinesEn);
    notifyListeners();
  }

  void setDietGoals(Set<String> goals) {
    final normalized = _normalizeDietGoals(goals);
    if (normalized.isEmpty) {
      _userDietOverride = false;
      _explicitDietGoals = {};
      final fallback = _dietPreferences;
      _filters = _filters.copyWith(dietGoals: fallback);
    } else {
      final cleaned = normalized.difference(_dietPreferences);
      final effective = cleaned.isNotEmpty ? cleaned : normalized;
      _userDietOverride = true;
      _explicitDietGoals = effective;
      _filters = _filters.copyWith(dietGoals: effective);
    }
    notifyListeners();
  }

  void setCalorieRange({int? min, int? max}) {
    _filters = _filters.copyWith(minCalories: min, maxCalories: max);
    notifyListeners();
  }

  void setManualIngredientNames(List<String>? names) {
    _filters = _filters.copyWith(manualIngredientNames: names);
    notifyListeners();
  }

  void setUseAiIngredientSelector(bool enabled) {
    _hybridService.useAiIngredientSelector = enabled;
    notifyListeners();
  }

  void setMacroThresholds({int? minProtein, int? maxCarbs, int? maxFat}) {
    _filters = _filters.copyWith(
      minProtein: minProtein,
      maxCarbs: maxCarbs,
      maxFat: maxFat,
    );
    notifyListeners();
  }

  List<IngredientModel>? _resolveManualSelectedIngredients() {
    final names = _filters.manualIngredientNames;
    if (names == null || names.isEmpty) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expansion = AllergyUtils.expandAllergens(_allergies);
    final allergens = expansion.all;
    bool isAllergic(String name) {
      return AllergyUtils.matchesAllergen(name, allergens);
    }

    final lookup = <String, IngredientModel>{};
    for (final i in _ingredients) {
      final expiry = i.expiryDate;
      if (expiry != null) {
        final expiryDate = DateTime(expiry.year, expiry.month, expiry.day);
        if (expiryDate.isBefore(today)) continue;
      }
      if (i.quantity <= 0) continue;
      if (isAllergic(i.name)) {
        debugPrint('⚠️ Manual ingredient skip (allergy): ${i.name}');
        continue;
      }

      lookup[i.name.trim().toLowerCase()] = i;
    }
    final selected = <IngredientModel>[];
    for (final n in names) {
      final k = n.trim().toLowerCase();
      if (lookup.containsKey(k)) selected.add(lookup[k]!);
    }
    return selected.isEmpty ? null : selected;
  }

  // ---------- Analytics ----------
  Future<void> analyzeIngredientUsage() async {
    _isAnalyzing = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _analyticsService.analyzeIngredientTrends(),
        _analyticsService.getStockManagementSuggestions(),
        _analyticsService.generateUsageReport(),
      ]);

      _analyticsData = results[0] as Map<String, dynamic>;
      _stockSuggestions = results[1] as Map<String, List<String>>;
      _lastAnalysisReport = results[2] as String?;
    } catch (e, st) {
      debugPrint('❌ Error analyzing ingredient usage: $e');
      debugPrintStack(stackTrace: st);
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }

    @override
    void dispose() {
      _isDisposed = true;
      _ingredientSub?.cancel();
      _cookingHistorySub?.cancel();
      _autoRefreshDebounce?.cancel();
      _ingredientExpiryTimer?.cancel();
      super.dispose();
    }
  }

  // ---------- Refresh ----------
  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    try {
      await Future.wait([loadIngredients(), loadCookingHistory()]);
      await Future.wait([getHybridRecommendations(), analyzeIngredientUsage()]);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------- Update after cooking ----------
  Future<void> updateIngredientAfterCooking(
    List<UsedIngredient> usedIngredients,
  ) async {
    try {
      await _analyticsService.updateIngredientUsageStats(usedIngredients);
      await loadIngredients();
    } catch (e) {
      debugPrint('❌ Error updating ingredient stats: $e');
    }
  }

  // ---------- Clear ----------
  void clearRecommendations() {
    _recommendations = [];
    _error = null;
    notifyListeners();
  }

  void clearAnalytics() {
    _analyticsData = {};
    _stockSuggestions = {};
    _lastAnalysisReport = null;
    notifyListeners();
  }

  // -------- Actions: Shopping List --------
  Future<int> addMissingIngredientsToShoppingList(RecipeModel recipe) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('ผู้ใช้ไม่ได้เข้าสู่ระบบ');
      if (recipe.missingIngredients.isEmpty) return 0;

      final col = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials');

      int added = 0;
      for (final name in recipe.missingIngredients) {
        final key = name.trim().toLowerCase();
        if (key.isEmpty) continue;

        final exists = await col
            .where('name_key', isEqualTo: key)
            .limit(1)
            .get();
        if (exists.docs.isNotEmpty) continue;

        final guessedCategory = _guessCategory(name);
        final guessedUnit = _guessUnit(name);

        await col.add({
          'name': name.trim(),
          'name_key': key,
          'quantity': 1,
          'unit': guessedUnit,
          'unit_key': guessedUnit.toLowerCase(),
          'category': guessedCategory,
          'category_key': guessedCategory,
          'expiry_date': null,
          'price': null,
          'notes': 'เพิ่มจากเมนู: ${recipe.name}',
          'imageUrl': '',
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
          'user_id': user.uid,
        });
        added++;
      }
      return added;
    } catch (e) {
      debugPrint('Error addMissingIngredientsToShoppingList (Enhanced): $e');
      rethrow;
    }
  }

  // --- New: add computed purchase items with quantities/units ---
  Future<int> addPurchaseItemsToShoppingList(
    List<PurchaseItem> items, {
    RecipeModel? recipe,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('ผู้ใช้ไม่ได้เข้าสู่ระบบ');
      if (items.isEmpty) return 0;

      final col = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials');

      int added = 0;
      for (final it in items) {
        final name = it.name.trim();
        if (name.isEmpty) continue;
        final key = name.toLowerCase();
        final exists = await col
            .where('name_key', isEqualTo: key)
            .limit(1)
            .get();
        if (exists.docs.isNotEmpty) continue;

        final category = (it.category?.trim().isNotEmpty ?? false)
            ? it.category!
            : _guessCategory(name);
        final unit = (it.unit.trim().isNotEmpty) ? it.unit : _guessUnit(name);
        final qty = it.quantity > 0 ? it.quantity : 1;

        await col.add({
          'name': name,
          'name_key': key,
          'quantity': qty,
          'unit': unit,
          'unit_key': unit.toLowerCase(),
          'category': category,
          'category_key': category,
          'expiry_date': null,
          'price': null,
          'notes': recipe != null ? 'เพิ่มจากเมนู: ${recipe.name}' : '',
          'imageUrl': '',
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
          'user_id': user.uid,
        });
        added++;
      }
      return added;
    } catch (e) {
      debugPrint('Error addPurchaseItemsToShoppingList: $e');
      rethrow;
    }
  }

  String _guessCategory(String name) {
    final n = name.trim().toLowerCase();
    const meat = [
      'ไก่',
      'หมู',
      'เนื้อ',
      'วัว',
      'ปลา',
      'กุ้ง',
      'หมึก',
      'เป็ด',
      'แฮม',
      'เบคอน',
      'pork',
      'beef',
      'chicken',
      'fish',
      'shrimp',
      'squid',
    ];
    const egg = ['ไข่', 'egg'];
    const veg = [
      'ผัก',
      'หอม',
      'หัวหอม',
      'ต้นหอม',
      'กระเทียม',
      'พริก',
      'มะเขือเทศ',
      'คะน้า',
      'กะหล่ำ',
      'แครอท',
      'แตง',
      'เห็ด',
      'ขิง',
      'ข่า',
      'ตะไคร้',
      'ใบมะกรูด',
      'onion',
      'garlic',
      'chili',
      'tomato',
      'cabbage',
      'carrot',
      'mushroom',
      'ginger',
      'lemongrass',
      'lime leaf',
    ];
    const fruit = [
      'ผลไม้',
      'กล้วย',
      'ส้ม',
      'แอปเปิ้ล',
      'สตรอ',
      'มะม่วง',
      'สับปะรด',
      'องุ่น',
      'banana',
      'orange',
      'apple',
      'strawberry',
      'mango',
      'pineapple',
      'grape',
      'lemon',
      'lime',
    ];
    const dairy = [
      'นม',
      'ชีส',
      'โยเกิร์ต',
      'ครีม',
      'เนย',
      'milk',
      'cheese',
      'yogurt',
      'butter',
      'cream',
    ];
    const rice = ['ข้าว', 'ข้าวสาร', 'rice', 'ข้าวหอมมะลิ'];
    const spice = [
      'เครื่องเทศ',
      'ยี่หร่า',
      'อบเชย',
      'ผงกะหรี่',
      'ซินนามอน',
      'cumin',
      'curry powder',
      'cinnamon',
      'peppercorn',
    ];
    const condiment = [
      'ซอส',
      'น้ำปลา',
      'ซีอิ๊ว',
      'เกลือ',
      'น้ำตาล',
      'ผงชูรส',
      'เต้าเจี้ยว',
      'ซอสมะเขือเทศ',
      'มายองเนส',
      'ซอสหอยนางรม',
      'sauce',
      'fish sauce',
      'soy',
      'salt',
      'sugar',
      'ketchup',
      'mayonnaise',
      'oyster sauce',
    ];
    const flour = [
      'แป้ง',
      'ขนมปัง',
      'เส้น',
      'พาสต้า',
      'noodle',
      'pasta',
      'flour',
      'bread',
    ];
    const oil = ['น้ำมัน', 'olive oil', 'vegetable oil', 'oil'];
    const drink = [
      'น้ำอัดลม',
      'โซดา',
      'กาแฟ',
      'ชา',
      'juice',
      'soda',
      'coffee',
      'tea',
    ];
    const frozen = ['แช่แข็ง', 'frozen'];

    bool any(List<String> list) => list.any((k) => n.contains(k));

    if (any(meat)) return 'เนื้อสัตว์';
    if (any(egg)) return 'ไข่';
    if (any(dairy)) return 'ผลิตภัณฑ์จากนม';
    if (any(rice)) return 'ข้าว';
    if (any(spice)) return 'เครื่องเทศ';
    if (any(condiment)) return 'เครื่องปรุง';
    if (any(flour)) return 'แป้ง';
    if (any(oil)) return 'น้ำมัน';
    if (any(drink)) return 'เครื่องดื่ม';
    if (any(frozen)) return 'ของแช่แข็ง';
    if (any(veg)) return 'ผัก';
    if (any(fruit)) return 'ผลไม้';
    return 'ของแห้ง';
  }

  String _guessUnit(String name) {
    final n = name.trim().toLowerCase();
    if (n.contains('ไข่') || n.contains('egg')) return 'ฟอง';
    if (n.contains('นม') ||
        n.contains('ซอส') ||
        n.contains('น้ำ') ||
        n.contains('ครีม') ||
        n.contains('milk') ||
        n.contains('sauce')) {
      return 'มิลลิลิตร';
    }
    if (n.contains('ขวด') || n.contains('กระป๋อง')) return 'ชิ้น';
    return 'กรัม';
  }
}

class _SimpleRule {
  final int maxIngredients;
  final int maxMissing;
  final double minRatio;

  const _SimpleRule({
    required this.maxIngredients,
    required this.maxMissing,
    required this.minRatio,
  });
}

class _SimpleCandidate {
  final RecipeModel recipe;
  final int ingredientCount;
  final int missingCount;
  final double ratio;

  const _SimpleCandidate({
    required this.recipe,
    required this.ingredientCount,
    required this.missingCount,
    required this.ratio,
  });
}
