import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/recipe/recipe.dart';

class UserRecipeService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _draftsKey = 'user_recipe_drafts';

  CollectionReference<Map<String, dynamic>> _collection() {
    final user = _auth.currentUser;
    if (user == null) {
      // ใช้ collection ชั่วคราว (ไม่เรียกจริง) ถ้ายังไม่ล็อกอิน
      // ฟังก์ชันจะบันทึก draft แทน
      return _firestore.collection('_no_user');
    }
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('user_recipes');
  }

  Future<List<RecipeModel>> getUserRecipes() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        // ถ้าไม่ล็อกอิน แสดง drafts แทน เพื่อให้ผู้ใช้เห็นว่าสร้างไว้แล้ว
        final drafts = await _getDrafts();
        return drafts.map((e) => RecipeModel.fromJson(e)).toList();
      }

      final snap = await _collection()
          .orderBy('created_at', descending: true)
          .get();
      return snap.docs
          .map((d) => RecipeModel.fromJson(d.data()))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<String> addUserRecipe(RecipeModel recipe) async {
    final user = _auth.currentUser;
    final payload = recipe
        .copyWith(source: 'ผู้ใช้', sourceUrl: null)
        .toJson();
    payload['is_user_recipe'] = true;
    payload['created_at'] =
        payload['created_at'] ?? DateTime.now().millisecondsSinceEpoch;

    String ensureId(Map<String, dynamic> json) {
      final existing = (json['id'] ?? '').toString().trim();
      if (existing.isNotEmpty) return existing;
      final generated = 'user_${DateTime.now().millisecondsSinceEpoch}';
      json['id'] = generated;
      return generated;
    }

    final docId = ensureId(payload);

    if (user == null) {
      // เก็บเป็น draft ชั่วคราว
      await _addDraft(Map<String, dynamic>.from(payload));
      return docId;
    }

    await _collection().doc(docId).set(payload, SetOptions(merge: true));
    return docId;
  }

  Future<void> updateUserRecipe(String id, RecipeModel recipe) async {
    final data = recipe.copyWith(source: 'ผู้ใช้').toJson();
    await _collection().doc(id).set(data, SetOptions(merge: true));
  }

  Future<void> deleteUserRecipe(String id) async {
    await _collection().doc(id).delete();
  }

  // ---------- Draft helpers (when user not logged in) ----------
  Future<void> _addDraft(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_draftsKey) ?? [];
    list.add(_encode(json));
    await prefs.setStringList(_draftsKey, list);
  }

  Future<List<Map<String, dynamic>>> _getDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_draftsKey) ?? [];
    return list.map(_decode).toList();
  }

  Future<void> syncDraftsToCloud() async {
    final user = _auth.currentUser;
    if (user == null) return; // wait until logged in

    final drafts = await _getDrafts();
    if (drafts.isEmpty) return;

    final col = _collection();
    for (final data in drafts) {
      final copy = Map<String, dynamic>.from(data);
      final id = (copy['id'] ?? '').toString().trim();
      if (id.isEmpty) {
        copy['id'] = 'user_${DateTime.now().millisecondsSinceEpoch}';
      }
      copy['is_user_recipe'] = true;
      copy['created_at'] =
          copy['created_at'] ?? DateTime.now().millisecondsSinceEpoch;
      await col.doc(copy['id'] as String).set(copy, SetOptions(merge: true));
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftsKey);
  }

  String _encode(Map<String, dynamic> json) => jsonEncode(json);
  Map<String, dynamic> _decode(String s) => Map<String, dynamic>.from(jsonDecode(s));
}
