// lib/foodreccom/providers/enhanced_recommendation_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/ingredient_model.dart';
import '../models/recipe/recipe.dart';
import '../models/cooking_history_model.dart';
import '../models/hybrid_models.dart';
import '../services/hybrid_recipe_service.dart';
import '../services/ingredient_analytics_service.dart';
import '../services/cooking_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/recipe/used_ingredient.dart';
import '../utils/thai_recipe_adapter.dart'; // ✅ ใช้ Google Translate
import '../models/recipe/nutrition_info.dart';
import '../services/user_recipe_service.dart';
import '../models/filter_options.dart';

class EnhancedRecommendationProvider extends ChangeNotifier {
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

  // ---------- Getters ----------
  List<RecipeModel> get recommendations => _recommendations;
  List<IngredientModel> get ingredients => _ingredients;
  List<RecipeModel> get userRecipes => _userRecipes;
  List<CookingHistory> get cookingHistory => _cookingHistory;
  Map<String, dynamic> get analyticsData => _analyticsData;
  Map<String, List<String>> get stockSuggestions => _stockSuggestions;
  bool get isLoading => _isLoading;
  bool get isAnalyzing => _isAnalyzing;
  String? get error => _error;
  String? get lastAnalysisReport => _lastAnalysisReport;
  HybridRecommendationResult? get lastHybridResult => _lastHybridResult;
  RecipeFilterOptions get filters => _filters;

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

      _ingredients = await compute(_sortIngredientsByPriority, items);
    } catch (e) {
      debugPrint('❌ Error loading ingredients: $e');
    }
  }

  static List<IngredientModel> _sortIngredientsByPriority(
    List<IngredientModel> items,
  ) {
    items.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return items;
  }

  // ---------- Load Cooking History ----------
  Future<void> loadCookingHistory() async {
    try {
      _cookingHistory = await _cookingService.getCookingHistory(limitDays: 30);
    } catch (e) {
      debugPrint('❌ Error loading cooking history: $e');
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
      if (_cookingHistory.isEmpty) {
        await loadCookingHistory();
      }

      // โหลดสูตรของผู้ใช้ควบคู่
      try {
        _userRecipes = await _userRecipeService.getUserRecipes();
      } catch (_) {}

      final result = await _hybridService.getHybridRecommendations(
        _ingredients,
        cookingHistory: _cookingHistory,
        manualSelectedIngredients: _resolveManualSelectedIngredients(),
        cuisineFilters: _filters.cuisineEn,
        dietGoals: _filters.dietGoals,
        minCalories: _filters.minCalories,
        maxCalories: _filters.maxCalories,
      );

      _lastHybridResult = result;

      // ✅ รวมสูตรผู้ใช้ + ภายนอก (ผู้ใช้มาก่อน)
      final external = result.externalRecipes ?? [];
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
        _recommendations = await ThaiRecipeAdapter.translateRecipes(recipes);
      }

      if (_recommendations.isEmpty) {
        _error = 'ไม่สามารถแนะนำเมนูได้ กรุณาลองใหม่อีกครั้ง';
      }
    } catch (e, st) {
      debugPrint('❌ Hybrid Recommendation Error: $e');
      debugPrintStack(stackTrace: st);

      _error = 'เกิดข้อผิดพลาด: ${e.toString()}';
      _recommendations = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------- User Recipes CRUD ----------
  Future<void> addUserRecipe(RecipeModel recipe) async {
    try {
      await _userRecipeService.addUserRecipe(recipe);
      await _userRecipeService.syncDraftsToCloud();
      _userRecipes = await _userRecipeService.getUserRecipes();
      // นำหน้าในรายการแนะนำ
      _recommendations = [..._userRecipes, ..._recommendations];
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
    _filters = _filters.copyWith(dietGoals: goals);
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

  List<IngredientModel>? _resolveManualSelectedIngredients() {
    final names = _filters.manualIngredientNames;
    if (names == null || names.isEmpty) return null;
    final lookup = {for (final i in _ingredients) i.name.trim().toLowerCase(): i};
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
}
