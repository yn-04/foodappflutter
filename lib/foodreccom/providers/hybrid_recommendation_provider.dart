//lib/foodreccom/providers/hybrid_recommendation_provider.dart
import 'package:flutter/foundation.dart';
import '../models/ingredient_model.dart';
import '../models/recipe/recipe.dart';
import '../models/cooking_history_model.dart';
import '../models/hybrid_models.dart';
import '../services/hybrid_recipe_service.dart';
import '../services/ingredient_analytics_service.dart';
import '../services/cooking_service.dart';
import '../utils/ingredient_utils.dart';
import '../utils/ingredient_translator.dart';
import '../utils/date_utils.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
  int _maxExternalRecipes = 12;
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

      final debugLogsEnabled =
          (dotenv.env['DEBUG_FILTER_LOGS'] ?? 'false').trim().toLowerCase();
      final isDebug =
          debugLogsEnabled == 'true' || debugLogsEnabled == '1' || debugLogsEnabled == 'on';

      if (isDebug) {
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final rawExpiry = data['expiry_date'];
          final parsedExpiry = parseDate(rawExpiry);
          final expiryLocal = DateTime(parsedExpiry.year, parsedExpiry.month, parsedExpiry.day);
          final rawType = rawExpiry == null ? 'null' : rawExpiry.runtimeType;
          print(
            '🐞 [RawExpiry] ${data['name']} raw=$rawExpiry (type=$rawType) → parsed=${parsedExpiry.toIso8601String()} (localDate=${expiryLocal.toIso8601String()})',
          );
        }
      }

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

      // ✅ คำนวณ "วัตถุดิบที่ขาด" สำหรับแต่ละเมนูที่แนะนำ เทียบกับสต็อกผู้ใช้
      if (_hybridResult != null) {
        List<RecipeModel> updateMissing(List<RecipeModel> recipes) {
          return recipes.map((r) {
            final missing = _computeMissingIngredients(r);
            return r.copyWith(missingIngredients: missing);
          }).toList();
        }

        _hybridResult!.externalRecipes =
            updateMissing(_hybridResult!.externalRecipes);
        _hybridResult!.combinedRecommendations =
            updateMissing(_hybridResult!.combinedRecommendations);
        _hybridResult!.aiRecommendations =
            updateMissing(_hybridResult!.aiRecommendations);
      }

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
      _maxExternalRecipes = maxExternal.clamp(1, 15);
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

  // ใช้ logic จาก utils/ingredient_utils + cross-language (TH↔EN)
  List<String> _computeMissingIngredients(RecipeModel recipe) {
    final thaiInv = _ingredients.map((i) => _norm(i.name)).toList();
    final engInv = IngredientTranslator
        .translateList(_ingredients.map((i) => i.name).toList())
        .map(_norm)
        .toList();

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

  // -------- Actions: Shopping List --------
  /// เพิ่มวัตถุดิบที่ขาดของสูตรนี้เข้าไปในรายการวัตถุดิบ (shopping/inventory)
  /// - ถ้ามีอยู่แล้ว (เทียบจาก name_key) จะข้ามไม่เพิ่มซ้ำ
  /// - ใส่ค่าเริ่มต้น: quantity=1, unit='ชิ้น', category='ของแห้ง'
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

        final exists = await col.where('name_key', isEqualTo: key).limit(1).get();
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

      // reload categories/ingredients subtly if needed
      return added;
    } catch (e) {
      debugPrint('Error addMissingIngredientsToShoppingList: $e');
      rethrow;
    }
  }

  String _guessCategory(String name) {
    final n = name.trim().toLowerCase();
    const meat = ['ไก่','หมู','เนื้อ','วัว','ปลา','กุ้ง','หมึก','เป็ด','แฮม','เบคอน','pork','beef','chicken','fish','shrimp','squid'];
    const egg = ['ไข่','egg'];
    const veg = ['ผัก','หอม','หัวหอม','ต้นหอม','กระเทียม','พริก','มะเขือเทศ','คะน้า','กะหล่ำ','แครอท','แตง','เห็ด','ขิง','ข่า','ตะไคร้','ใบมะกรูด','onion','garlic','chili','tomato','cabbage','carrot','mushroom','ginger','lemongrass','lime leaf'];
    const fruit = ['ผลไม้','กล้วย','ส้ม','แอปเปิ้ล','สตรอ','มะม่วง','สับปะรด','องุ่น','banana','orange','apple','strawberry','mango','pineapple','grape','lemon','lime'];
    const dairy = ['นม','ชีส','โยเกิร์ต','ครีม','เนย','milk','cheese','yogurt','butter','cream'];
    const rice = ['ข้าว','ข้าวสาร','rice','ข้าวหอมมะลิ'];
    const spice = ['เครื่องเทศ','ยี่หร่า','อบเชย','ผงกะหรี่','ซินนามอน','cumin','curry powder','cinnamon','peppercorn'];
    const condiment = ['ซอส','น้ำปลา','ซีอิ๊ว','เกลือ','น้ำตาล','ผงชูรส','เต้าเจี้ยว','ซอสมะเขือเทศ','มายองเนส','ซอสหอยนางรม','sauce','fish sauce','soy','salt','sugar','ketchup','mayonnaise','oyster sauce'];
    const flour = ['แป้ง','ขนมปัง','เส้น','พาสต้า','noodle','pasta','flour','bread'];
    const oil = ['น้ำมัน','olive oil','vegetable oil','oil'];
    const drink = ['น้ำอัดลม','โซดา','กาแฟ','ชา','juice','soda','coffee','tea'];
    const frozen = ['แช่แข็ง','frozen'];

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
    if (n.contains('นม') || n.contains('ซอส') || n.contains('น้ำ') || n.contains('ครีม') || n.contains('milk') || n.contains('sauce')) {
      return 'มิลลิลิตร';
    }
    if (n.contains('ขวด') || n.contains('กระป๋อง')) return 'ชิ้น';
    return 'กรัม';
  }
}
