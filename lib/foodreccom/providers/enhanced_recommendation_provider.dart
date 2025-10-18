// lib/foodreccom/providers/enhanced_recommendation_provider.dart
import 'package:flutter/foundation.dart';
import 'package:my_app/common/measurement_constants.dart';
import '../models/ingredient_model.dart';
import '../models/recipe/recipe.dart';
import '../models/cooking_history_model.dart';
import '../models/hybrid_models.dart';
import '../models/purchase_item.dart';
import '../services/hybrid_recipe_service.dart';
import '../services/ingredient_analytics_service.dart';
import '../services/cooking_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/recipe/used_ingredient.dart';
import '../utils/thai_recipe_adapter.dart'; // ✅ ใช้ Google Translate
import '../services/user_recipe_service.dart';
import '../models/filter_options.dart';
import '../utils/ingredient_utils.dart';
import '../utils/ingredient_translator.dart';
import 'package:my_app/foodreccom/services/enhanced_ai_recommendation_service.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';

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
    'คาร์บต่ำ': 'low-carb',
    'high-protein': 'high-protein',
    'high protein': 'high-protein',
    'โปรตีนสูง': 'high-protein',
    'low-fat': 'low-fat',
    'low fat': 'low-fat',
    'ไขมันต่ำ': 'low-fat',
    'gluten-free': 'gluten-free',
    'gluten free': 'gluten-free',
    'glutenfree': 'gluten-free',
    'ปลอดกลูเตน': 'gluten-free',
    'dairy-free': 'dairy-free',
    'dairy free': 'dairy-free',
    'dairyfree': 'dairy-free',
    'ปลอดนม': 'dairy-free',
    'ไม่กินนม': 'dairy-free',
  };
  final HybridRecipeService _hybridService = HybridRecipeService();
  final IngredientAnalyticsService _analyticsService =
      IngredientAnalyticsService();
  final CookingService _cookingService = CookingService();
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

  // ---------- Getters ----------
  List<RecipeModel> get recommendations => _recommendations;
  List<IngredientModel> get ingredients => _ingredients;
  List<RecipeModel> get userRecipes => _userRecipes;
  List<RecipeModel> get userRecommendations =>
      _recommendations.where(_isUserRecipe).toList();
  List<RecipeModel> get hybridRecommendations =>
      _recommendations.where((r) => !_isUserRecipe(r)).toList();

  Set<String> _normalizeDietGoals(Iterable<String> goals) {
    final normalized = <String>{};
    for (final goal in goals) {
      final key = goal.trim().toLowerCase();
      if (key.isEmpty) continue;
      normalized.add(_dietGoalAliases[key] ?? key);
    }
    return normalized;
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
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .get();

      final items = snapshot.docs
          .map((doc) => IngredientModel.fromFirestore(doc.data()))
          .toList();

      // 1) รวมวัตถุดิบชื่อซ้ำที่ระดับข้อมูล (แปลงหน่วยพื้นฐานได้)
      final deduped = _dedupeIngredients(items);
      // 2) เรียงตามความสำคัญ
      _ingredients = await compute(_sortIngredientsByPriority, deduped);
    } catch (e) {
      debugPrint('❌ Error loading ingredients: $e');
    } finally {
      notifyListeners();
    }
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
    try {
      _cookingHistory = await _cookingService.getCookingHistory(limitDays: 30);
    } catch (e) {
      debugPrint('❌ Error loading cooking history: $e');
    } finally {
      notifyListeners();
    }
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

      final combinedDietGoals = {..._filters.dietGoals, ..._dietPreferences};
      final normalizedDietGoals = _normalizeDietGoals(combinedDietGoals);

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
      final filterLog = StringBuffer()
        ..write('👤 ฟิลเตอร์ผู้ใช้ → ')
        ..write(
          'ประเภทอาหาร: ${_filters.cuisineEn.isEmpty ? 'ทั้งหมด' : _filters.cuisineEn.join(', ')} | ',
        )
        ..write(
          'โภชนาการ: ${normalizedDietGoals.isEmpty ? 'ไม่เลือก' : normalizedDietGoals.join(', ')} | ',
        )
        ..write('แคลอรี่: ${_formatCalories()} | ')
        ..write(
          'แมโคร: ${_formatMacros(
            minProtein: _filters.minProtein,
            maxCarbs: _filters.maxCarbs,
            maxFat: _filters.maxFat,
          )} | ',
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
        minProtein: _filters.minProtein,
        maxCarbs: _filters.maxCarbs,
        maxFat: _filters.maxFat,
        excludeIngredients: _allergies.toList(),
      );

      _lastHybridResult = result;

      // ✅ รวมสูตรผู้ใช้ + ภายนอก (ผู้ใช้มาก่อน)
      final external = result.externalRecipes;
      final recipes = [..._userRecipes, ...external];

      if (recipes.isEmpty) {
        debugPrint("⚠️ ไม่มีเมนูจาก RapidAPI → ใช้ fallback");
        _recommendations = [
          RecipeModel(
            id: 'fallback_basic',
            name: 'ข้าวผัดไข่',
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
        // คำนวณวัตถุดิบที่ขาด เทียบกับคลังวัตถุดิบผู้ใช้ (ภาษาไทย)
        final safe = translated.where((r) => !_containsAllergen(r)).toList();
        _recommendations = safe
            .map(
              (r) =>
                  r.copyWith(missingIngredients: _computeMissingIngredients(r)),
            )
            .toList();
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
      notifyListeners();
    }
  }

  void _resetUserFiltersAfterUse() {
    final manualNames = _filters.manualIngredientNames;
    final hasManual = manualNames != null && manualNames.isNotEmpty;
    final hasCuisine = _filters.cuisineEn.isNotEmpty;
    final hasDietOverride =
        !setEquals(_filters.dietGoals, _dietPreferences);
    final hasProteinOverride = _filters.minProtein != _hpMinProtein;
    final hasCarbOverride = _filters.maxCarbs != _hpMaxCarbs;
    final hasFatOverride = _filters.maxFat != _hpMaxFat;

    final shouldReset = hasManual ||
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
    debugPrint('♻️ รีเซ็ตฟิลเตอร์ผู้ใช้หลังประมวลผลคำแนะนำ');
  }

  void _appendFallbackRecommendations() {
    final needed = _minimumRecommendationCount - _recommendations.length;
    if (needed <= 0) return;
    final existingIds = _recommendations.map((r) => r.id).toSet();
    final fallbackPool = _fallbackRecommendations();
    for (final recipe in fallbackPool) {
      if (_recommendations.length >= _minimumRecommendationCount) break;
      if (existingIds.contains(recipe.id)) continue;
      _recommendations.add(recipe);
      existingIds.add(recipe.id);
    }
  }

  List<RecipeModel> _fallbackRecommendations() {
    return [
      _buildSimpleRecipe(
        id: 'fallback_pad_kra_prao',
        name: 'ผัดกะเพราไก่ไข่ดาว',
        description: 'เมนูไทยยอดนิยม ใช้วัตถุดิบพื้นฐานอย่างไก่สับและใบกะเพรา',
        calories: 520,
        protein: 32,
        carbs: 48,
        fat: 20,
        ingredients: [
          RecipeIngredient(name: 'อกไก่สับ', amount: 200, unit: 'g'),
          RecipeIngredient(name: 'ใบกะเพรา', amount: 1, unit: 'กำ'),
          RecipeIngredient(name: 'พริกกระเทียมตำ', amount: 2, unit: 'ช้อนโต๊ะ'),
          RecipeIngredient(name: 'ข้าวสวย', amount: 1, unit: 'จาน'),
        ],
      ),
      _buildSimpleRecipe(
        id: 'fallback_green_curry',
        name: 'แกงเขียวหวานไก่',
        description: 'รสเข้มข้นจากน้ำกะทิและเครื่องแกงหอมจัดจ้าน',
        calories: 450,
        protein: 28,
        carbs: 24,
        fat: 28,
        ingredients: [
          RecipeIngredient(name: 'สะโพกไก่หั่นชิ้น', amount: 250, unit: 'g'),
          RecipeIngredient(name: 'กะทิกล่อง', amount: 250, unit: 'ml'),
          RecipeIngredient(name: 'น้ำพริกแกงเขียวหวาน', amount: 2, unit: 'ช้อนโต๊ะ'),
          RecipeIngredient(name: 'มะเขือพวง', amount: 50, unit: 'g'),
          RecipeIngredient(name: 'ใบโหระพา', amount: 1, unit: 'กำ'),
        ],
      ),
      _buildSimpleRecipe(
        id: 'fallback_salmon_salad',
        name: 'สลัดปลาแซลมอนย่างซอสส้ม',
        description: 'จานสุขภาพโปรตีนสูงพร้อมผักหลากสี',
        calories: 380,
        protein: 30,
        carbs: 18,
        fat: 20,
        ingredients: [
          RecipeIngredient(name: 'ปลาแซลมอนย่าง', amount: 150, unit: 'g'),
          RecipeIngredient(name: 'ผักสลัดรวม', amount: 120, unit: 'g'),
          RecipeIngredient(name: 'ส้มซันควิก', amount: 30, unit: 'ml'),
          RecipeIngredient(name: 'อัลมอนด์อบ', amount: 1, unit: 'ช้อนโต๊ะ'),
        ],
      ),
      _buildSimpleRecipe(
        id: 'fallback_quinoa_bowl',
        name: 'ควินัวโบวล์เต้าหู้ย่าง',
        description: 'เหมาะสำหรับสายรักสุขภาพได้คาร์บเชิงซ้อนและโปรตีนพืช',
        calories: 410,
        protein: 24,
        carbs: 50,
        fat: 12,
        ingredients: [
          RecipeIngredient(name: 'ควินัวสุก', amount: 180, unit: 'g'),
          RecipeIngredient(name: 'เต้าหู้แข็งย่าง', amount: 120, unit: 'g'),
          RecipeIngredient(name: 'บร็อคโคลีลวก', amount: 80, unit: 'g'),
          RecipeIngredient(name: 'น้ำมันมะกอก', amount: 1, unit: 'ช้อนชา'),
        ],
      ),
      _buildSimpleRecipe(
        id: 'fallback_stir_fried_morning_glory',
        name: 'ผัดผักบุ้งไฟแดง',
        description: 'เมนูผักทำง่ายที่ช่วยเพิ่มไฟเบอร์',
        calories: 180,
        protein: 6,
        carbs: 14,
        fat: 10,
        ingredients: [
          RecipeIngredient(name: 'ผักบุ้งไทย', amount: 200, unit: 'g'),
          RecipeIngredient(name: 'เต้าเจี้ยว', amount: 1, unit: 'ช้อนโต๊ะ'),
          RecipeIngredient(name: 'กระเทียม', amount: 3, unit: 'กลีบ'),
          RecipeIngredient(name: 'พริกชี้ฟ้า', amount: 1, unit: 'เม็ด'),
        ],
      ),
      _buildSimpleRecipe(
        id: 'fallback_chicken_congee',
        name: 'โจ๊กไก่ใส่ไข่',
        description: 'ย่อยง่าย ให้พลังงานพอดีสำหรับมื้อเช้า',
        calories: 320,
        protein: 18,
        carbs: 42,
        fat: 8,
        ingredients: [
          RecipeIngredient(name: 'ข้าวกล้องหุง', amount: 1, unit: 'ถ้วย'),
          RecipeIngredient(name: 'เนื้อไก่ฉีก', amount: 100, unit: 'g'),
          RecipeIngredient(name: 'ไข่ไก่', amount: 1, unit: 'ฟอง'),
          RecipeIngredient(name: 'ขิงซอย', amount: 1, unit: 'ช้อนโต๊ะ'),
        ],
      ),
    ];
  }

  RecipeModel _buildSimpleRecipe({
    required String id,
    required String name,
    required String description,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required List<RecipeIngredient> ingredients,
  }) {
    return RecipeModel(
      id: id,
      name: name,
      description: description,
      matchScore: 55,
      reason: 'เมนูสำรองเพื่อเติมจำนวนคำแนะนำ',
      ingredients: ingredients,
      missingIngredients: const [],
      steps: const [],
      cookingTime: 20,
      prepTime: 10,
      difficulty: 'ง่าย',
      servings: 2,
      category: 'อาหารจานหลัก',
      nutrition: NutritionInfo(
        calories: calories,
        protein: protein,
        carbs: carbs,
        fat: fat,
        fiber: 4,
        sodium: 480,
      ),
      source: 'Fallback',
    );
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
        if (diets is List) {
          final raw = diets
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty);
          final normalizedPrefs = _normalizeDietGoals(raw);
          _dietPreferences = normalizedPrefs;
          if (normalizedPrefs.isNotEmpty) {
            final merged = {..._filters.dietGoals, ...normalizedPrefs};
            _filters = _filters.copyWith(dietGoals: merged);
          }
        }
        // nutritionTargetsPerMeal
        int? _readInt(dynamic v) {
          if (v == null) return null;
          if (v is int) return v;
          if (v is double) return v.round();
          return int.tryParse(v.toString());
        }

        final nt = hp['nutritionTargetsPerMeal'];
        if (nt is Map<String, dynamic>) {
          final p = nt['โปรตีน'] ?? nt['protein'];
          if (p is Map<String, dynamic>) _hpMinProtein = _readInt(p['min']);
          final c = nt['คาร์บ'] ?? nt['carbs'];
          if (c is Map<String, dynamic>) _hpMaxCarbs = _readInt(c['max']);
          final f = nt['ไขมัน'] ?? nt['fat'];
          if (f is Map<String, dynamic>) _hpMaxFat = _readInt(f['max']);
          setMacroThresholds(
            minProtein: _hpMinProtein,
            maxCarbs: _hpMaxCarbs,
            maxFat: _hpMaxFat,
          );
        }
      }
    } catch (e) {
      debugPrint('healthProfile load error: $e');
    }
    _healthLoaded = true;
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
    if (_hpMinProtein != null) {
      macroTargets['protein'] = {'min': _hpMinProtein!};
    }
    if (_hpMaxCarbs != null) {
      macroTargets['carbs'] = {'max': _hpMaxCarbs!};
    }
    if (_hpMaxFat != null) {
      macroTargets['fat'] = {'max': _hpMaxFat!};
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
    if (_filters.dietGoals.isNotEmpty) {
      parts.add('ข้อจำกัดอาหาร: ${_filters.dietGoals.join(', ')}');
    }
    if (_dietPreferences.isNotEmpty) {
      parts.add('ความชอบด้านโภชนาการ: ${_dietPreferences.join(', ')}');
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

  Future<Map<String, dynamic>?> generateWeeklyMealPlan({
    required List<ShoppingItem> pantryItems,
  }) async {
    if (!_healthLoaded) {
      await _loadHealthProfile();
    }
    final profile = _buildHealthProfileForAI();
    final notes = _buildDietaryNotesForAI();
    final service = EnhancedAIRecommendationService();
    return service.generateWeeklyMealPlan(
      pantryItems: pantryItems,
      userProfile: profile.isEmpty ? null : profile,
      dietaryNotes: notes,
    );
  }

  bool _containsAllergen(RecipeModel r) {
    if (_allergies.isEmpty) return false;
    final ingNames = r.ingredients
        .map((i) => i.name.trim().toLowerCase())
        .toList();
    final alls = <String>{
      ..._allergies,
      ..._allergies.map((e) => _mapAllergenToEnglish(e) ?? ''),
    }.where((e) => e.trim().isNotEmpty).map((e) => e.toLowerCase());
    for (final a in alls) {
      if (ingNames.any((n) => n.contains(a) || a.contains(n))) return true;
    }
    return false;
  }

  String? _mapAllergenToEnglish(String t) {
    final s = t.trim().toLowerCase();
    if (s.isEmpty) return null;
    const map = {
      'กุ้ง': 'shrimp',
      'ปู': 'crab',
      'หอยนางรม': 'oyster',
      'หอย': 'shellfish',
      'ปลาหมึก': 'squid',
      'หมึก': 'squid',
      'ปลา': 'fish',
      'นม': 'milk',
      'แลคโตส': 'lactose',
      'ไข่': 'egg',
      'ถั่วลิสง': 'peanut',
      'ถั่ว': 'nut',
      'อัลมอนด์': 'almond',
      'วอลนัท': 'walnut',
      'เฮเซลนัท': 'hazelnut',
      'แป้งสาลี': 'wheat',
      'กลูเตน': 'gluten',
      'ถั่วเหลือง': 'soy',
      'งา': 'sesame',
      'น้ำผึ้ง': 'honey',
    };
    return map[s] ?? s;
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

  String _norm(String s) {
    var out = s.trim().toLowerCase();
    out = out.replaceAll(RegExp(r"\(.*?\)"), ""); // remove (...) notes
    out = out.replaceAll(RegExp(r"\s+"), " ").trim();
    return out;
  }

  // ---------- User Recipes CRUD ----------
  Future<void> addUserRecipe(RecipeModel recipe) async {
    try {
      await _userRecipeService.addUserRecipe(recipe);
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
    _filters = _filters.copyWith(dietGoals: _normalizeDietGoals(goals));
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
    final allergens = <String>{
      ..._allergies,
      ..._allergies.map((e) => _mapAllergenToEnglish(e) ?? ''),
    }
        .where((value) => value.trim().isNotEmpty)
        .map((value) => value.trim().toLowerCase())
        .toSet();
    bool isAllergic(String name) {
      if (allergens.isEmpty) return false;
      final key = name.trim().toLowerCase();
      for (final allergen in allergens) {
        if (key.contains(allergen) || allergen.contains(key)) return true;
      }
      return false;
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
