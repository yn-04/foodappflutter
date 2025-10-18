//lib/foodreccom/providers/thai_recipe_provider.dart
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/ingredient_model.dart';
import '../models/recipe/recipe.dart';
import '../services/hybrid_recipe_service.dart';
import '../services/ai_translation_service.dart';
import '../utils/ingredient_utils.dart';
import '../utils/ingredient_translator.dart';

class ThaiRecipeProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final HybridRecipeService _hybridService = HybridRecipeService();

  List<RecipeModel> _recommendations = [];
  List<IngredientModel> _ingredients = [];
  bool _isLoading = false;
  String? _error;

  List<RecipeModel> get recommendations => _recommendations;
  List<IngredientModel> get ingredients => _ingredients;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<IngredientModel> get nearExpiryIngredients =>
      _ingredients.where((i) => i.isNearExpiry).toList();

  /// โหลดวัตถุดิบจาก Firestore
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

      _ingredients = items;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading ingredients: $e');
    }
  }

  /// ดึง Hybrid Recommendations แล้วแปลไทย
  Future<void> getThaiRecommendations() async {
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
      final result = await _hybridService.getHybridRecommendations(
        _ingredients,
      );

      if (!result.isSuccess) {
        _error = result.error ?? 'ไม่สามารถดึงเมนูแนะนำได้';
        _recommendations = [];
      } else {
        // ✅ คำนวณวัตถุดิบที่ขาดเทียบกับสต็อกก่อน แล้วค่อยแปลไทย
        final withMissing = result.combinedRecommendations.map((r) {
          final missing = _computeMissingIngredients(r);
          return r.copyWith(missingIngredients: missing);
        }).toList();

        // ✅ แปลไทยทุกเมนู
        _recommendations = await _translateRecipes(withMissing);
      }
    } catch (e) {
      _error = 'เกิดข้อผิดพลาด: $e';
      _recommendations = [];
      debugPrint('❌ Error getThaiRecommendations: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<String> _computeMissingIngredients(RecipeModel recipe) {
    final thaiInv = _ingredients.map((i) => _norm(i.name)).toList();
    final engInv = IngredientTranslator.translateList(
      _ingredients.map((i) => i.name).toList(),
    ).map(_norm).toList();

    bool matchAny(String need) {
      final nThai = _norm(need);
      if (thaiInv.any((have) => ingredientsMatch(have, nThai))) return true;
      final nEng = _norm(IngredientTranslator.translate(need));
      if (engInv.any((have) => have.contains(nEng) || nEng.contains(have))) {
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
    out = out.replaceAll(RegExp(r"\(.*?\)"), "");
    out = out.replaceAll(RegExp(r"\s+"), " ").trim();
    return out;
  }

  /// ฟังก์ชันแปลภาษาไทยทุก field สำคัญ
  Future<List<RecipeModel>> _translateRecipes(List<RecipeModel> recipes) async {
    List<RecipeModel> translated = [];
    for (final recipe in recipes) {
      final nameTh = await AITranslationService.translateToThai(recipe.name);
      final descTh = await AITranslationService.translateToThai(
        recipe.description,
      );

      final reasonTh = await AITranslationService.translateToThai(
        recipe.reason,
      );

      final ingredientsTh = await Future.wait(
        recipe.ingredients.map((i) async {
          final ingNameTh = await AITranslationService.translateToThai(i.name);
          return RecipeIngredient(
            name: ingNameTh,
            amount: i.amount,
            unit: i.unit,
          );
        }),
      );

      final missingTh = await Future.wait(
        recipe.missingIngredients.map(AITranslationService.translateToThai),
      );

      final stepsTh = await Future.wait(
        recipe.steps.map((s) async {
          final stepTextTh = await AITranslationService.translateToThai(
            s.instruction,
          );
          final tipsTh = await Future.wait(
            s.tips.map(AITranslationService.translateToThai),
          );
          return CookingStep(
            stepNumber: s.stepNumber,
            instruction: stepTextTh,
            timeMinutes: s.timeMinutes,
            tips: tipsTh,
          );
        }),
      );

      final tagsTh = await Future.wait(
        recipe.tags.map(AITranslationService.translateToThai),
      );

      translated.add(
        recipe.copyWith(
          name: nameTh,
          description: descTh,
          reason: reasonTh,
          ingredients: ingredientsTh,
          missingIngredients: missingTh,
          steps: stepsTh,
          tags: tagsTh,
        ),
      );
    }
    return translated;
  }

  /// รีเฟรชข้อมูลใหม่
  Future<void> refresh() async {
    _isLoading = true;
    notifyListeners();
    try {
      await loadIngredients();
      await getThaiRecommendations();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearRecommendations() {
    _recommendations = [];
    _error = null;
    notifyListeners();
  }
}
