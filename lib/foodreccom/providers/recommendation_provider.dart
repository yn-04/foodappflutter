//lib/foodreccom/providers/recommendation_provider.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/ingredient_model.dart';
import '../models/recipe/recipe.dart';
import '../services/ai_recommendation_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_recipe_service.dart';

class RecommendationProvider extends ChangeNotifier {
  final AIRecommendationService _aiService = AIRecommendationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserRecipeService _userRecipeService = UserRecipeService();

  List<RecipeModel> _recommendations = [];
  List<RecipeModel> _userRecipes = [];
  List<IngredientModel> _ingredients = [];
  bool _isLoading = false;
  String? _error;

  List<RecipeModel> get recommendations => _recommendations;
  List<RecipeModel> get userRecipes => _userRecipes;
  List<IngredientModel> get ingredients => _ingredients;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // -------- Ingredient Categories --------
  List<IngredientModel> get nearExpiryIngredients =>
      _ingredients.where((i) => i.isNearExpiry).toList();

  // -------- Load Ingredients --------
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

      // แยก isolate ถ้า list ใหญ่
      _ingredients = await compute(_sortIngredients, items);

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading ingredients: $e');
    }
  }

  static List<IngredientModel> _sortIngredients(List<IngredientModel> items) {
    items.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return items;
  }

  // -------- Get Recommendations --------
  Future<void> getRecommendations() async {
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
      // โหลดสูตรผู้ใช้ด้วย
      try {
        _userRecipes = await _userRecipeService.getUserRecipes();
      } catch (_) {}
      final recs = await _aiService.getRecommendations(_ingredients);

      // แยก isolate เผื่อ sort/filter ภายหลัง
      final sorted = await compute(_sortRecommendations, recs);
      _recommendations = [..._userRecipes, ...sorted];

      if (_recommendations.isEmpty) {
        _error = 'ไม่สามารถแนะนำเมนูได้ กรุณาลองใหม่อีกครั้ง';
      }
    } catch (e) {
      _error = 'เกิดข้อผิดพลาด: $e';
      _recommendations = [];
      debugPrint('Error getRecommendations: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // -------- User recipes --------
  Future<void> addUserRecipe(RecipeModel recipe) async {
    await _userRecipeService.addUserRecipe(recipe);
    _userRecipes = await _userRecipeService.getUserRecipes();
    _recommendations = [..._userRecipes, ..._recommendations];
    notifyListeners();
  }

  static List<RecipeModel> _sortRecommendations(List<RecipeModel> recs) {
    recs.sort((a, b) => b.matchScore.compareTo(a.matchScore));
    return recs;
  }

  // -------- Refresh --------
  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();

    try {
      // โหลดข้อมูล + ขอคำแนะนำ
      await loadIngredients();
      await getRecommendations();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // -------- Clear --------
  void clearRecommendations() {
    _recommendations = [];
    _error = null;
    notifyListeners();
  }
}
