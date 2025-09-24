import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/ingredient_model.dart';
import '../models/recipe/recipe.dart';
import '../models/cooking_history_model.dart';
import '../models/hybrid_models.dart';
import '../services/enhanced_ai_recommendation_service.dart';
import '../services/hybrid_recipe_service.dart';
import '../services/ingredient_analytics_service.dart';
import '../services/cooking_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/recipe/used_ingredient.dart';

class EnhancedRecommendationProvider extends ChangeNotifier {
  final EnhancedAIRecommendationService _aiService =
      EnhancedAIRecommendationService();
  final HybridRecipeService _hybridService = HybridRecipeService();
  final IngredientAnalyticsService _analyticsService =
      IngredientAnalyticsService();
  final CookingService _cookingService = CookingService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<RecipeModel> _recommendations = [];
  List<IngredientModel> _ingredients = [];
  List<CookingHistory> _cookingHistory = [];
  Map<String, dynamic> _analyticsData = {};
  Map<String, List<String>> _stockSuggestions = {};
  bool _isLoading = false;
  bool _isAnalyzing = false;
  String? _error;
  String? _lastAnalysisReport;
  HybridRecommendationResult? _lastHybridResult;

  // Getters
  List<RecipeModel> get recommendations => _recommendations;
  List<IngredientModel> get ingredients => _ingredients;
  List<CookingHistory> get cookingHistory => _cookingHistory;
  Map<String, dynamic> get analyticsData => _analyticsData;
  Map<String, List<String>> get stockSuggestions => _stockSuggestions;
  bool get isLoading => _isLoading;
  bool get isAnalyzing => _isAnalyzing;
  String? get error => _error;
  String? get lastAnalysisReport => _lastAnalysisReport;
  HybridRecommendationResult? get lastHybridResult => _lastHybridResult;

  // Enhanced ingredient categorization
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

  // ---------- Load Data ----------
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
      debugPrint('Error loading enhanced ingredients: $e');
    }
  }

  static List<IngredientModel> _sortIngredientsByPriority(
    List<IngredientModel> items,
  ) {
    items.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return items;
  }

  Future<void> loadCookingHistory() async {
    try {
      _cookingHistory = await _cookingService.getCookingHistory(limitDays: 30);
    } catch (e) {
      debugPrint('Error loading cooking history: $e');
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

      final result = await _hybridService.getHybridRecommendations(
        _ingredients,
        cookingHistory: _cookingHistory,
      );

      _lastHybridResult = result;
      _recommendations = result.combinedRecommendations;

      if (_recommendations.isEmpty) {
        _error = 'ไม่สามารถแนะนำเมนูได้ กรุณาลองใหม่อีกครั้ง';
      }
    } catch (e) {
      _error = 'เกิดข้อผิดพลาด: ${e.toString()}';
      _recommendations = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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

      debugPrint('Analytics completed: ${_analyticsData.keys}');
    } catch (e) {
      debugPrint('Error analyzing ingredient usage: $e');
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

  // ---------- Other Methods ----------
  Future<void> updateIngredientAfterCooking(
    List<UsedIngredient> usedIngredients,
  ) async {
    try {
      await _analyticsService.updateIngredientUsageStats(usedIngredients);
      await loadIngredients();
    } catch (e) {
      debugPrint('Error updating ingredient stats: $e');
    }
  }

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
