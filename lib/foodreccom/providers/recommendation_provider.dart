// lib/providers/recommendation_provider.dart
import 'package:flutter/material.dart';
import '../models/ingredient_model.dart';
import '../models/recipe_model.dart';
import '../services/ai_recommendation_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RecommendationProvider extends ChangeNotifier {
  final AIRecommendationService _aiService = AIRecommendationService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<RecipeModel> _recommendations = [];
  List<IngredientModel> _ingredients = [];
  bool _isLoading = false;
  String? _error;

  List<RecipeModel> get recommendations => _recommendations;
  List<IngredientModel> get ingredients => _ingredients;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // วัตถุดิบใกล้หมดอายุ
  List<IngredientModel> get nearExpiryIngredients =>
      _ingredients.where((i) => i.isNearExpiry).toList();

  // โหลดวัตถุดิบจาก Firestore
  Future<void> loadIngredients() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .get();

      _ingredients = snapshot.docs
          .map((doc) => IngredientModel.fromFirestore(doc.data()))
          .toList();

      notifyListeners();
    } catch (e) {
      print('Error loading ingredients: $e');
    }
  }

  // ขอคำแนะนำจาก AI
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
      _recommendations = await _aiService.getRecommendations(_ingredients);

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

  // รีเฟรชข้อมูล
  Future<void> refresh() async {
    await loadIngredients();
    await getRecommendations();
  }

  // ล้างข้อมูล
  void clearRecommendations() {
    _recommendations = [];
    _error = null;
    notifyListeners();
  }
}
