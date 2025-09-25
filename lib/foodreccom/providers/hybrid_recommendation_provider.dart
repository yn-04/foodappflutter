//lib/foodreccom/providers/hybrid_recommendation_provider.dart
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

class HybridRecommendationProvider extends ChangeNotifier {
  final HybridRecipeService _hybridService = HybridRecipeService();
  final IngredientAnalyticsService _analyticsService =
      IngredientAnalyticsService();
  final CookingService _cookingService = CookingService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // ข้อมูลหลัก
  List<IngredientModel> _ingredients = [];
  List<CookingHistory> _cookingHistory = [];
  HybridRecommendationResult? _hybridResult;
  Map<String, dynamic> _analyticsData = {};

  // สถานะ
  bool _isLoadingRecommendations = false;
  bool _isLoadingIngredients = false;
  bool _isAnalyzing = false;
  String? _error;

  // การตั้งค่า (ไม่มี includeExternalRecipes แล้ว)
  int _maxExternalRecipes = 3;
  String _preferredCuisine = '';

  // -------- Getters --------
  List<IngredientModel> get ingredients => _ingredients;
  List<CookingHistory> get cookingHistory => _cookingHistory;
  HybridRecommendationResult? get hybridResult => _hybridResult;
  Map<String, dynamic> get analyticsData => _analyticsData;

  bool get isLoadingRecommendations => _isLoadingRecommendations;
  bool get isLoadingIngredients => _isLoadingIngredients;
  bool get isAnalyzing => _isAnalyzing;
  bool get isLoading =>
      _isLoadingRecommendations || _isLoadingIngredients || _isAnalyzing;
  String? get error => _error;

  int get maxExternalRecipes => _maxExternalRecipes;
  String get preferredCuisine => _preferredCuisine;

  List<RecipeModel> get allRecommendations =>
      _hybridResult?.combinedRecommendations ?? [];
  List<RecipeModel> get aiRecommendations =>
      _hybridResult?.aiRecommendations ?? [];
  List<RecipeModel> get externalRecommendations =>
      _hybridResult?.externalRecipes ?? [];
  HybridAnalysis? get hybridAnalysis => _hybridResult?.hybridAnalysis;

  // -------- Ingredient Categories --------
  List<IngredientModel> get urgentExpiryIngredients =>
      _ingredients.where((i) => i.isUrgentExpiry).toList();
  List<IngredientModel> get nearExpiryIngredients =>
      _ingredients.where((i) => i.isNearExpiry && !i.isUrgentExpiry).toList();
  List<IngredientModel> get frequentlyUsedIngredients =>
      _ingredients.where((i) => i.isFrequentlyUsed).toList();
  List<IngredientModel> get underutilizedIngredients =>
      _ingredients.where((i) => i.isUnderutilized).toList();

  List<IngredientModel> get priorityIngredients {
    final sorted = [..._ingredients];
    sorted.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return sorted.take(10).toList();
  }

  // -------- Recommendation Categories --------
  List<RecipeModel> get wastePreventionRecommendations {
    final wasteRisk = urgentExpiryIngredients + nearExpiryIngredients;
    if (wasteRisk.isEmpty) return [];
    return allRecommendations.where((recipe) {
      return recipe.ingredients.any((recipeIng) {
        return wasteRisk.any(
          (riskIng) => _ingredientsMatch(riskIng.name, recipeIng.name),
        );
      });
    }).toList();
  }

  List<RecipeModel> get quickRecipes =>
      allRecommendations.where((r) => r.totalTime <= 30).toList();

  List<RecipeModel> get budgetFriendlyRecipes =>
      allRecommendations.where((r) => r.tags.contains('ประหยัด')).toList();

  // -------- Load Data --------
  Future<void> loadIngredients() async {
    if (_isLoadingIngredients) return;

    _isLoadingIngredients = true;
    _error = null;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('ผู้ใช้ไม่ได้เข้าสู่ระบบ');

      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .get();

      final items = snapshot.docs
          .map((doc) => IngredientModel.fromFirestore(doc.data()))
          .toList();

      _ingredients = await compute(_sortIngredients, items);

      debugPrint('โหลดวัตถุดิบสำเร็จ: ${_ingredients.length}');
    } catch (e) {
      _error = 'โหลดวัตถุดิบล้มเหลว: ${e.toString()}';
      debugPrint('Error loadIngredients: $e');
    } finally {
      _isLoadingIngredients = false;
      notifyListeners();
    }
  }

  static List<IngredientModel> _sortIngredients(List<IngredientModel> items) {
    items.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return items;
  }

  Future<void> loadCookingHistory() async {
    try {
      _cookingHistory = await _cookingService.getCookingHistory(limitDays: 30);
    } catch (e) {
      debugPrint('Error loadCookingHistory: $e');
    }
  }

  // -------- Hybrid Recommendations --------
  Future<void> getHybridRecommendations() async {
    if (_isLoadingRecommendations) return;

    if (_ingredients.isEmpty) await loadIngredients();
    if (_ingredients.isEmpty) {
      _error = 'ไม่มีวัตถุดิบ กรุณาเพิ่มก่อน';
      notifyListeners();
      return;
    }

    _isLoadingRecommendations = true;
    _error = null;
    notifyListeners();

    try {
      if (_cookingHistory.isEmpty) await loadCookingHistory();

      _hybridResult = await _hybridService.getHybridRecommendations(
        _ingredients,
        cookingHistory: _cookingHistory,
        maxExternalRecipes:
            _maxExternalRecipes, // ✅ ไม่มี includeExternalRecipes แล้ว
      );

      if (!_hybridResult!.isSuccess) {
        _error = _hybridResult!.error ?? 'เกิดข้อผิดพลาด';
      } else if (_hybridResult!.combinedRecommendations.isEmpty) {
        _error = 'ไม่สามารถแนะนำเมนูได้';
      }
    } catch (e) {
      _error = 'เกิดข้อผิดพลาด: $e';
      debugPrint('Error getHybridRecommendations: $e');
    } finally {
      _isLoadingRecommendations = false;
      notifyListeners();
    }
  }

  // -------- Analytics --------
  Future<void> analyzeIngredientUsage() async {
    if (_isAnalyzing) return;
    _isAnalyzing = true;
    notifyListeners();

    try {
      _analyticsData = await _analyticsService.analyzeIngredientTrends();
    } catch (e) {
      debugPrint('Error analyzeIngredientUsage: $e');
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  // -------- Refresh --------
  Future<void> refresh() async {
    _isLoadingRecommendations = true;
    notifyListeners();

    try {
      await Future.wait([loadIngredients(), loadCookingHistory()]);
      await Future.wait([getHybridRecommendations(), analyzeIngredientUsage()]);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingRecommendations = false;
      notifyListeners();
    }
  }

  // -------- Settings --------
  void setExternalRecipeSettings({int? maxExternal, String? cuisine}) {
    bool changed = false;
    if (maxExternal != null && maxExternal != _maxExternalRecipes) {
      _maxExternalRecipes = maxExternal.clamp(1, 10);
      changed = true;
    }
    if (cuisine != null && cuisine != _preferredCuisine) {
      _preferredCuisine = cuisine;
      changed = true;
    }
    if (changed) {
      notifyListeners();
      getHybridRecommendations();
    }
  }

  // -------- Smart Shopping --------
  List<Map<String, dynamic>> getSmartShoppingList() {
    final shoppingList = <Map<String, dynamic>>[];
    final missingItems = <String>{};

    for (final recipe in allRecommendations.take(3)) {
      missingItems.addAll(recipe.missingIngredients);
    }

    for (final ingredient in frequentlyUsedIngredients) {
      if (ingredient.quantity <= 2) {
        shoppingList.add({
          'name': ingredient.name,
          'suggested_quantity': ingredient.quantity * 3,
          'unit': ingredient.unit,
          'reason': 'วัตถุดิบที่ใช้บ่อย เหลือน้อย',
          'priority': 'high',
          'estimated_cost': (ingredient.price ?? 0) * 3,
        });
      }
    }

    for (final item in missingItems) {
      shoppingList.add({
        'name': item,
        'reason': 'ต้องใช้สำหรับเมนูแนะนำ',
        'priority': 'medium',
      });
    }

    return shoppingList;
  }

  // -------- Summary --------
  Map<String, dynamic> getSummaryStats() {
    final result = _hybridResult;
    return {
      'ingredients': {
        'total': _ingredients.length,
        'urgent_expiry': urgentExpiryIngredients.length,
        'near_expiry': nearExpiryIngredients.length,
      },
      'recommendations': {
        'total': allRecommendations.length,
        'ai_generated': result?.aiRecommendationCount ?? 0,
        'from_api': result?.externalRecommendationCount ?? 0,
        'waste_prevention': wastePreventionRecommendations.length,
        'quick_recipes': quickRecipes.length,
      },
      'analytics': result?.hybridAnalysis?.toMap(),
    };
  }

  // -------- Clear --------
  void clearRecommendations() {
    _hybridResult = null;
    _error = null;
    notifyListeners();
  }

  void clearAnalytics() {
    _analyticsData = {};
    notifyListeners();
  }

  void clearAll() {
    _hybridResult = null;
    _analyticsData = {};
    _cookingHistory = [];
    _error = null;
    notifyListeners();
  }

  // -------- Helper --------
  bool _ingredientsMatch(String available, String required) {
    final a = available.toLowerCase();
    final r = required.toLowerCase();
    return a.contains(r) || r.contains(a);
  }
}
