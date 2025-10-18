// lib/foodreccom/services/rapidapi_recipe_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe/recipe.dart';
import '../models/ingredient_model.dart';
import '../utils/recipe_parser.dart';
import '../utils/ingredient_translator.dart';
import 'api_usage_service.dart';

class RapidAPIRecipeService {
  static const String _spoonacularBase =
      'https://spoonacular-recipe-food-nutrition-v1.p.rapidapi.com';

  final Map<String, String> _headers = {
    'X-RapidAPI-Key': dotenv.env['RAPIDAPI_KEY'] ?? '',
    'X-RapidAPI-Host': 'spoonacular-recipe-food-nutrition-v1.p.rapidapi.com',
  };

  static const String _cacheKey = 'rapidapi_cached_recipes';
  static const String _lastCacheKey = 'rapidapi_cached_last';
  final Map<String, List<RecipeModel>> _memoryCache = {};

  /// 🔎 ค้นหาสูตรอาหารจากวัตถุดิบ
  Future<List<RecipeModel>> searchRecipesByIngredients(
    List<IngredientModel> ingredients, {
    int maxResults = 12, // ✅ ดึงอย่างน้อย 12 เมนู (ถ้ามีในระบบ)
    int ranking = 1,
    List<String> cuisineFilters = const [], // english lowercase
    Set<String> dietGoals =
        const {}, // vegan, high-fiber, high-protein, low-carb
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
    List<String> excludeIngredients = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await ApiUsageService.initDaily();
    final ingredientNames = ingredients.map((i) => i.name).toList();

    // ✅ แปลวัตถุดิบไทย → อังกฤษ และคัดกรองคำที่ไม่ใช่วัตถุดิบ
    final translatedNames = _filterIngredientTokens(
      IngredientTranslator.translateList(ingredientNames),
    );

    final cacheKey = _buildCacheKey(
      translatedNames: translatedNames,
      cuisineFilters: cuisineFilters,
      dietGoals: dietGoals,
      minCalories: minCalories,
      maxCalories: maxCalories,
      minProtein: minProtein,
      maxCarbs: maxCarbs,
      maxFat: maxFat,
      excludeIngredients: excludeIngredients,
    );
    if (_memoryCache.containsKey(cacheKey)) {
      final cached = _memoryCache[cacheKey]!;
      print('♻️ ใช้ memory cache recipes (${cached.length})');
      return cached.map((r) => r.copyWith()).toList();
    }
    print(
      '🧪 RapidAPI ingredients (EN): ${translatedNames.join(', ')} [${translatedNames.length}]',
    );

    try {
      // If user applied cuisine/diet/calorie filters, try complexSearch first
      if (!await ApiUsageService.canUseRapid()) {
        print('⛔ RapidAPI quota reached for today → use cache if available');
        final recipes = _loadCachedRecipes(prefs, cacheKey, reason: 'quota');
        if (recipes != null) return recipes;
        return [];
      }

      // If user applied cuisine/diet/calorie filters, try complexSearch first
      final hasAdvancedFilters =
          cuisineFilters.isNotEmpty ||
          dietGoals.isNotEmpty ||
          minCalories != null ||
          maxCalories != null;

      if (hasAdvancedFilters) {
        // เพิ่มจำนวนผลค้นหาเบื้องต้นเมื่อตัวกรองเข้มงวด เพื่อโอกาส match สูงขึ้น
        int strictness = 0;
        strictness += dietGoals.length;
        if (minProtein != null && minProtein > 0) strictness++;
        if (maxCarbs != null && maxCarbs > 0) strictness++;
        if (maxFat != null && maxFat > 0) strictness++;
        final expandedNumber = (strictness >= 2)
            ? (maxResults * 3).clamp(5, 15)
            : maxResults;
        final complexRes = await _fetchComplexSearchRelaxed(
          translatedNames,
          number: expandedNumber,
          cuisines: cuisineFilters,
          dietGoals: dietGoals,
          minCalories: minCalories,
          maxCalories: maxCalories,
          minProtein: minProtein,
          maxCarbs: maxCarbs,
          maxFat: maxFat,
          excludeIngredients: excludeIngredients,
        );
        if (complexRes != null && complexRes.isNotEmpty) {
          print('🌍 RapidAPI complexSearch hit: ${complexRes.length}');
          final ids = complexRes
              .map((r) => (r is Map ? r['id'] : null))
              .whereType<int>()
              .toList();
          final detailed = await Future.wait(ids.map(_getRecipeDetails));
          var recipes = detailed.whereType<RecipeModel>().toList();
          recipes = _applyPostFilters(
            recipes,
            cuisineFilters: cuisineFilters,
            dietGoals: dietGoals,
            minCalories: minCalories,
            maxCalories: maxCalories,
            minProtein: minProtein,
            maxCarbs: maxCarbs,
            maxFat: maxFat,
            excludeIngredients: excludeIngredients,
          ).take(maxResults).toList();
          await _saveRecipesToCache(
            prefs,
            cacheKey,
            recipes,
            tag: 'complexSearch',
          );
          if (recipes.isNotEmpty) return recipes;
          print(
            'ℹ️ complexSearch returned no recipes after filters → fallback to findByIngredients',
          );
        }
      }

      // First attempt: translated list
      final firstRanking = translatedNames.length <= 2 ? 2 : ranking;
      final firstNumber = translatedNames.length <= 2
          ? (maxResults.clamp(1, 3))
          : maxResults;
      final url = _buildFindByIngredientsUrl(
        translatedNames,
        number: firstNumber,
        ranking: firstRanking,
      );
      final allowCall = await ApiUsageService.waitForRapidSlot();
      if (!allowCall) {
        print('⏳ RapidAPI throttled/cooldown → use cache instead of call');
        final recipes = _loadCachedRecipes(
          prefs,
          cacheKey,
          reason: 'throttled',
        );
        if (recipes != null) return recipes;
      } else {
        print("🌍 Calling RapidAPI: $url");
        await ApiUsageService.countRapid();
      }
      final response = await _getWithTimeout(url);

      if (response?.statusCode == 200) {
        final List<dynamic> data = json.decode(response!.body);

        // ✅ Auto-learn mapping จาก usedIngredients
        for (final r in data) {
          if (r is Map && r.containsKey("usedIngredients")) {
            for (final used in r["usedIngredients"]) {
              final original = used["original"]?.toString() ?? "";
              final name = used["name"]?.toString() ?? "";
              if (original.isNotEmpty && name.isNotEmpty) {
                await IngredientTranslator.learnMapping(original, name);
              }
            }
          }
        }

        // ✅ เก็บ ID พร้อมคะแนน แล้วถ้ายังได้ไม่ครบ ลองขยายเงื่อนไขเพื่อให้ครบตามที่ร้องขอ (อย่างน้อย 12)
        final targetSet = translatedNames.toSet();
        final scoreMap = _scoreRecipes(data, targetSet);

        if (scoreMap.length < maxResults) {
          // 1) ผ่อน ranking เป็น 2 เพื่อให้ได้เมนูเพิ่ม
          final more1 = await _fetchFindByIngredients(
            translatedNames,
            number: maxResults,
            ranking: 2,
          );
          if (more1 != null) {
            final m = _scoreRecipes(more1, targetSet);
            for (final e in m.entries) {
              final current = scoreMap[e.key];
              if (current == null || e.value > current) {
                scoreMap[e.key] = e.value;
              }
            }
          }

          // 2) ลดจำนวนวัตถุดิบลงทีละตัวเพื่อขยายผลลัพธ์จนเต็มจำนวนที่ต้องการ
          var reduceCount = 1;
          while (scoreMap.length < maxResults &&
              reduceCount < translatedNames.length) {
            final reduced = translatedNames
                .take(translatedNames.length - reduceCount)
                .toList();
            if (reduced.isEmpty) break;
            final more = await _fetchFindByIngredients(
              reduced,
              number: maxResults,
              ranking: 2,
            );
            if (more != null) {
              final m = _scoreRecipes(more, targetSet);
              for (final e in m.entries) {
                final current = scoreMap[e.key];
                if (current == null || e.value > current) {
                  scoreMap[e.key] = e.value;
                }
              }
            }
            reduceCount++;
          }
        }

        final orderedIds = scoreMap.keys.toList()
          ..sort((a, b) => scoreMap[b]!.compareTo(scoreMap[a]!));
        final limitedIds = orderedIds.take(maxResults).toList();

        // ✅ ดึงรายละเอียดเมนูตามลำดับที่จัดไว้ (แบบมี timeout)
        final detailed = <RecipeModel>[];
        for (final id in limitedIds) {
          final r = await _getRecipeDetails(id);
          if (r != null) detailed.add(r);
        }

        var recipes = detailed.whereType<RecipeModel>().toList();
        recipes = _applyPostFilters(
          recipes,
          cuisineFilters: cuisineFilters,
          dietGoals: dietGoals,
          minCalories: minCalories,
          maxCalories: maxCalories,
        ).take(maxResults).toList();

        // ✅ เก็บ cache ไว้ backup
        await _saveRecipesToCache(prefs, cacheKey, recipes);

        return recipes;
      }

      // If failed or timed out, retry with ASCII-only ingredients
      final asciiOnly = translatedNames
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .where((s) => _isAscii(s))
          .toList();

      if (asciiOnly.isNotEmpty && asciiOnly.length != translatedNames.length) {
        final url2 = _buildFindByIngredientsUrl(
          asciiOnly,
          number: maxResults.clamp(1, 4),
          ranking: 2,
        );
        if (await ApiUsageService.waitForRapidSlot()) {
          print("🌍 Retry (ASCII-only) RapidAPI: $url2");
          await ApiUsageService.countRapid();
        } else {
          print(
            '⏳ RapidAPI throttled/cooldown → use cache for retry (ASCII-only)',
          );
          final recipes = _loadCachedRecipes(
            prefs,
            cacheKey,
            reason: 'ascii throttled',
          );
          if (recipes != null) return recipes;
        }
        final response2 = await _getWithTimeout(url2);
        if (response2?.statusCode == 200) {
          final List<dynamic> data = json.decode(response2!.body);

          for (final r in data) {
            if (r is Map && r.containsKey("usedIngredients")) {
              for (final used in r["usedIngredients"]) {
                final original = used["original"]?.toString() ?? "";
                final name = used["name"]?.toString() ?? "";
                if (original.isNotEmpty && name.isNotEmpty) {
                  await IngredientTranslator.learnMapping(original, name);
                }
              }
            }
          }

          // เติมผลลัพธ์ให้ครบ 5 ด้วยวิธีเดียวกัน
          final targetSet = asciiOnly.toSet();
          final scoreMap = _scoreRecipes(data, targetSet);
          if (scoreMap.length < maxResults) {
            final more1 = await _fetchFindByIngredients(
              asciiOnly,
              number: maxResults,
              ranking: 2,
            );
            if (more1 != null) {
              final m = _scoreRecipes(more1, targetSet);
              for (final e in m.entries) {
                final current = scoreMap[e.key];
                if (current == null || e.value > current) {
                  scoreMap[e.key] = e.value;
                }
              }
            }
          }
          final orderedIds = scoreMap.keys.toList()
            ..sort((a, b) => scoreMap[b]!.compareTo(scoreMap[a]!));
          final limitedIds = orderedIds.take(maxResults).toList();
          final detailed = <RecipeModel>[];
          for (final id in limitedIds) {
            final r = await _getRecipeDetails(id);
            if (r != null) detailed.add(r);
          }
          var recipes = detailed.whereType<RecipeModel>().toList();
          recipes = _applyPostFilters(
            recipes,
            cuisineFilters: cuisineFilters,
            dietGoals: dietGoals,
            minCalories: minCalories,
            maxCalories: maxCalories,
            minProtein: minProtein,
            maxCarbs: maxCarbs,
            maxFat: maxFat,
            excludeIngredients: excludeIngredients,
          ).take(maxResults).toList();

          await _saveRecipesToCache(
            prefs,
            cacheKey,
            recipes,
            tag: 'ASCII-only',
          );

          return recipes;
        }
      }

      // Final retry: fewer ingredients and fewer results
      final reduced = (asciiOnly.isNotEmpty ? asciiOnly : translatedNames)
          .take(4)
          .toList();
      if (reduced.isNotEmpty) {
        final url3 = _buildFindByIngredientsUrl(
          reduced,
          number: maxResults.clamp(1, 3),
          ranking: 2,
        );
        if (await ApiUsageService.waitForRapidSlot()) {
          print("🌍 Retry (reduced set) RapidAPI: $url3");
          await ApiUsageService.countRapid();
        } else {
          print(
            '⏳ RapidAPI throttled/cooldown → use cache for retry (reduced)',
          );
          final recipes = _loadCachedRecipes(
            prefs,
            cacheKey,
            reason: 'reduced throttled',
          );
          if (recipes != null) return recipes;
        }
        final response3 = await _getWithTimeout(url3);
        if (response3?.statusCode == 200) {
          final List<dynamic> data = json.decode(response3!.body);
          final targetSet = reduced.toSet();
          final scoreMap = _scoreRecipes(data, targetSet);
          final orderedIds = scoreMap.keys.toList()
            ..sort((a, b) => scoreMap[b]!.compareTo(scoreMap[a]!));
          final limitedIds = orderedIds.take(maxResults.clamp(1, 3)).toList();
          final detailed = <RecipeModel>[];
          for (final id in limitedIds) {
            final r = await _getRecipeDetails(id);
            if (r != null) detailed.add(r);
          }
          var recipes = detailed.whereType<RecipeModel>().toList();
          recipes = _applyPostFilters(
            recipes,
            cuisineFilters: cuisineFilters,
            dietGoals: dietGoals,
            minCalories: minCalories,
            maxCalories: maxCalories,
            minProtein: minProtein,
            maxCarbs: maxCarbs,
            maxFat: maxFat,
            excludeIngredients: excludeIngredients,
          ).take(maxResults.clamp(1, 3)).toList();

          await _saveRecipesToCache(prefs, cacheKey, recipes, tag: 'reduced');

          return recipes;
        }
      }

      throw Exception(
        'RapidAPI Error: ${response?.statusCode} - ${response?.body}',
      );
    } catch (e) {
      print('❌ Error searchRecipesByIngredients: $e');

      // ✅ fallback: โหลดจาก cache ถ้ามี
      final recipes = _loadCachedRecipes(prefs, cacheKey, reason: 'error');
      if (recipes != null) return recipes;

      return [];
    }
  }

  /// 📌 ดึงรายละเอียดสูตรอาหาร
  Future<RecipeModel?> _getRecipeDetails(int recipeId) async {
    try {
      final url = Uri.parse(
        '$_spoonacularBase/recipes/$recipeId/information?includeNutrition=true',
      );
      final response = await _getWithTimeout(url);
      if (response?.statusCode == 200) {
        final data = json.decode(response!.body);
        return RecipeParser.parseSpoonacularRecipe(data);
      }
      return null;
    } catch (e) {
      print('❌ Error getRecipeDetails: $e');
      return null;
    }
  }

  Future<List<dynamic>?> _fetchFindByIngredients(
    List<String> names, {
    required int number,
    required int ranking,
  }) async {
    final url = _buildFindByIngredientsUrl(
      names,
      number: number,
      ranking: ranking,
    );
    final res = await _getWithTimeout(url);
    if (res?.statusCode == 200) {
      return json.decode(res!.body) as List<dynamic>;
    }
    return null;
  }

  Uri _buildFindByIngredientsUrl(
    List<String> names, {
    required int number,
    required int ranking,
  }) {
    final joined = names.join(',');
    final query = {
      'ingredients': joined,
      'number': number.toString(),
      'ranking': ranking.toString(),
      'ignorePantry': 'true',
    };
    final encoded = query.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return Uri.parse('$_spoonacularBase/recipes/findByIngredients?$encoded');
  }

  Uri _buildComplexSearchUrl(
    List<String> names, {
    required int number,
    List<String> cuisines = const [],
    Set<String> dietGoals = const {},
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
    List<String> excludeIngredients = const [],
  }) {
    final query = <String, String>{
      'number': number.toString(),
      'addRecipeInformation': 'true',
      'ignorePantry': 'true',
    };
    if (names.isNotEmpty) query['includeIngredients'] = names.join(',');
    if (cuisines.isNotEmpty) query['cuisine'] = cuisines.join(',');
    // Diet mapping — Spoonacular "diet" supports a single value.
    // เราจะส่งค่าแรกเพื่อช่วยกรองที่ต้นทาง และกรองแบบเข้มงวด (AND) ที่ฝั่งแอป
    final goals = dietGoals.map((e) => e.toLowerCase()).toSet();
    const supportedDiets = [
      'vegan',
      'vegetarian',
      'lacto-vegetarian',
      'ovo-vegetarian',
      'ketogenic',
      'paleo',
    ];
    final diets = supportedDiets.where(goals.contains).toList();
    if (diets.isNotEmpty) query['diet'] = diets.first;

    // Intolerances mapping
    const intoleranceMap = {
      'gluten-free': 'gluten',
      'dairy-free': 'dairy',
    };
    final intoleranceList = intoleranceMap.entries
        .where((entry) => goals.contains(entry.key))
        .map((entry) => entry.value)
        .toList();
    if (intoleranceList.isNotEmpty) {
      query['intolerances'] = intoleranceList.join(',');
    }

    // Macro constraints
    final mp = (minProtein != null && minProtein > 0)
        ? minProtein
        : (goals.contains('high-protein') ? 30 : null);
    final mc = (maxCarbs != null && maxCarbs > 0)
        ? maxCarbs
        : (goals.contains('low-carb') || goals.contains('ketogenic'))
            ? 20
            : null;
    final mf = (maxFat != null && maxFat > 0)
        ? maxFat
        : (goals.contains('low-fat') ? 15 : null);
    if (mp != null) query['minProtein'] = mp.toString();
    if (mc != null) query['maxCarbs'] = mc.toString();
    if (mf != null) query['maxFat'] = mf.toString();

    if (minCalories != null) query['minCalories'] = minCalories.toString();
    if (maxCalories != null) query['maxCalories'] = maxCalories.toString();

    // Exclude ingredients inferred from selected diets (เพิ่มความเข้มงวดที่ฝั่ง API)
    final excludes = _excludeIngredientsForGoals(goals);
    final userEx = excludeIngredients
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty);
    final allEx = {...excludes, ...userEx}.toList();
    if (allEx.isNotEmpty) query['excludeIngredients'] = allEx.join(',');

    final encoded = query.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');
    return Uri.parse('$_spoonacularBase/recipes/complexSearch?$encoded');
  }

  List<String> _excludeIngredientsForGoals(Set<String> goals) {
    final g = goals.map((e) => e.toLowerCase()).toSet();
    final out = <String>{};
    void addAll(Iterable<String> xs) => out.addAll(xs);

    const meats = [
      'pork',
      'beef',
      'chicken',
      'turkey',
      'lamb',
      'bacon',
      'ham',
      'sausage',
      'meat',
    ];
    const seafood = [
      'fish',
      'tuna',
      'salmon',
      'shrimp',
      'prawn',
      'crab',
      'squid',
      'octopus',
      'anchovy',
      'seafood',
    ];
    const eggs = ['egg'];
    const dairy = ['milk', 'cheese', 'butter', 'yogurt', 'cream', 'ghee'];
    const gluten = [
      'wheat',
      'barley',
      'rye',
      'bread',
      'flour',
      'pasta',
      'spaghetti',
      'noodles',
    ];
    const highCarb = [
      'sugar',
      'rice',
      'bread',
      'pasta',
      'noodles',
      'potato',
      'corn',
      'tortilla',
    ];
    const legumes = ['beans', 'lentil', 'pea', 'peanut', 'soy'];
    const grains = ['wheat', 'barley', 'rye', 'oats', 'rice'];

    if (g.contains('vegan')) {
      addAll(meats);
      addAll(seafood);
      addAll(eggs);
      addAll(dairy);
      out.add('honey');
    }
    if (g.contains('vegetarian')) {
      addAll(meats);
      addAll(seafood);
    }
    if (g.contains('lacto-vegetarian')) {
      addAll(meats);
      addAll(seafood);
      addAll(eggs);
    }
    if (g.contains('ovo-vegetarian')) {
      addAll(meats);
      addAll(seafood);
      addAll(dairy);
    }
    if (g.contains('gluten-free')) {
      addAll(gluten);
    }
    if (g.contains('dairy-free')) {
      addAll(dairy);
    }
    if (g.contains('ketogenic')) {
      addAll(highCarb);
    }
    if (g.contains('paleo')) {
      addAll(grains);
      addAll(legumes);
      addAll(dairy);
      out.add('sugar');
    }
    return out.toList();
  }

  List<RecipeModel>? _decodeRecipes(String? raw) {
    if (raw == null) return null;
    try {
      final data = json.decode(raw);
      final recipes = (data['recipes'] as List?)
          ?.map((r) => RecipeModel.fromJson(r))
          .toList();
      return recipes;
    } catch (e) {
      print('⚠️ Failed to decode RapidAPI cache: $e');
      return null;
    }
  }

  List<RecipeModel>? _loadCachedRecipes(
    SharedPreferences prefs,
    String cacheKey, {
    bool allowFallback = true,
    String reason = '',
  }) {
    final recipes = _decodeRecipes(prefs.getString(cacheKey));
    if (recipes != null) {
      _memoryCache[cacheKey] = recipes;
      final tag = reason.isNotEmpty ? ' [$reason]' : '';
      print('♻️ ใช้ cache recipes (${recipes.length})$tag');
      return recipes.map((r) => r.copyWith()).toList();
    }

    if (!allowFallback || cacheKey == _lastCacheKey) {
      return null;
    }

    final fallback = _decodeRecipes(prefs.getString(_lastCacheKey));
    if (fallback != null) {
      _memoryCache[cacheKey] = fallback;
      _memoryCache[_lastCacheKey] = fallback;
      final tag = reason.isNotEmpty ? ' [$reason-fallback]' : ' [fallback]';
      print('♻️ ใช้ cache recipes ล่าสุด (${fallback.length})$tag');
      return fallback.map((r) => r.copyWith()).toList();
    }
    return null;
  }

  Future<void> _saveRecipesToCache(
    SharedPreferences prefs,
    String cacheKey,
    List<RecipeModel> recipes, {
    String tag = '',
  }) async {
    final payload = json.encode({
      'recipes': recipes.map((r) => r.toJson()).toList(),
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    await prefs.setString(cacheKey, payload);
    await prefs.setString(_lastCacheKey, payload);
    _memoryCache[cacheKey] = recipes;
    _memoryCache[_lastCacheKey] = recipes;
    final label = tag.isNotEmpty ? ' [$tag]' : '';
    print('✅ RapidAPI cache saved (${recipes.length} recipes)$label');
  }

  Future<http.Response?> _getWithTimeout(Uri url) async {
    try {
      return await http
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      print('⏱️ RapidAPI request timeout or error: $e');
      final msg = e.toString().toLowerCase();
      if (msg.contains('timeout')) {
        await ApiUsageService.setRapidCooldown(const Duration(seconds: 4));
      }
      return null;
    }
  }

  Future<List<dynamic>?> _fetchComplexSearch(
    List<String> names, {
    required int number,
    List<String> cuisines = const [],
    Set<String> dietGoals = const {},
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
    List<String> excludeIngredients = const [],
  }) async {
    final url = _buildComplexSearchUrl(
      names,
      number: number,
      cuisines: cuisines,
      dietGoals: dietGoals,
      minCalories: minCalories,
      maxCalories: maxCalories,
      minProtein: minProtein,
      maxCarbs: maxCarbs,
      maxFat: maxFat,
      excludeIngredients: excludeIngredients,
    );
    if (!await ApiUsageService.waitForRapidSlot()) {
      print('⏳ RapidAPI throttled/cooldown → skip complexSearch');
      return null;
    }
    print('🌍 Calling RapidAPI (complexSearch): $url');
    await ApiUsageService.countRapid();
    final res = await _getWithTimeout(url);
    if (res?.statusCode == 200) {
      final data = json.decode(res!.body);
      final results = (data['results'] as List?) ?? [];
      return results;
    }
    return null;
  }

  // Try complexSearch with progressive relaxation to avoid zero results
  Future<List<dynamic>?> _fetchComplexSearchRelaxed(
    List<String> names, {
    required int number,
    List<String> cuisines = const [],
    Set<String> dietGoals = const {},
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
    List<String> excludeIngredients = const [],
  }) async {
    // STRICT mode: never drop cuisine or diet constraints
    // Step 1: full constraints
    var res = await _fetchComplexSearch(
      names,
      number: number,
      cuisines: cuisines,
      dietGoals: dietGoals,
      minCalories: minCalories,
      maxCalories: maxCalories,
      minProtein: minProtein,
      maxCarbs: maxCarbs,
      maxFat: maxFat,
      excludeIngredients: excludeIngredients,
    );
    if (res != null && res.isNotEmpty) return res;

    // Step 2: keep cuisine+diets, reduce includeIngredients subset (4 then 3)
    for (final k in [4, 3]) {
      final subset = names.take(k).toList();
      if (subset.isEmpty) continue;
      res = await _fetchComplexSearch(
        subset,
        number: number,
        cuisines: cuisines,
        dietGoals: dietGoals,
        minCalories: minCalories,
        maxCalories: maxCalories,
        minProtein: minProtein,
        maxCarbs: maxCarbs,
        maxFat: maxFat,
        excludeIngredients: excludeIngredients,
      );
      if (res != null && res.isNotEmpty) return res;
    }

    // Step 3: keep cuisine+diets, drop includeIngredients entirely
    res = await _fetchComplexSearch(
      const <String>[],
      number: number,
      cuisines: cuisines,
      dietGoals: dietGoals,
      minCalories: minCalories,
      maxCalories: maxCalories,
      minProtein: minProtein,
      maxCarbs: maxCarbs,
      maxFat: maxFat,
      excludeIngredients: excludeIngredients,
    );
    return res;
  }

  bool _isAscii(String s) {
    for (final code in s.codeUnits) {
      if (code > 127) return false;
    }
    return true;
  }

  // ---- Helpers: filtering and sorting ----
  List<String> _filterIngredientTokens(List<String> tokens) {
    final out = <String>{};
    for (var t in tokens) {
      final s = t.trim().toLowerCase();
      if (s.isEmpty) continue;
      if (!_containsLetter(s)) continue; // drop items without letters
      if (_looksLikeNonIngredient(s)) continue;
      out.add(s);
    }
    if (out.isEmpty) return tokens.map((e) => e.trim().toLowerCase()).toList();
    return out.toList();
  }

  bool _containsLetter(String s) => RegExp(r"[a-zA-Z]").hasMatch(s);

  bool _looksLikeNonIngredient(String s) {
    if (s.length < 2) return true;
    if (RegExp(r"[0-9@/#]").hasMatch(s)) return true;
    const stop = {
      'fresh',
      'ripe',
      'large',
      'small',
      'medium',
      'piece',
      'pieces',
      'pack',
      'bag',
      'bottle',
      'can',
      'cup',
      'tbsp',
      'tsp',
      'ml',
      'l',
      'kg',
      'g',
      'pc',
      'pcs',
      'optional',
      'extra',
      'some',
    };
    return stop.contains(s);
  }

  Map<int, int> _scoreRecipes(List<dynamic> data, Set<String> targets) {
    final scoreMap = <int, int>{};
    for (final r in data) {
      if (r is! Map) continue;
      final id = r['id'];
      if (id is! int) continue;
      final used = (r['usedIngredients'] as List? ?? [])
          .map(
            (e) => (e is Map ? e['name']?.toString() ?? '' : '').toLowerCase(),
          )
          .where((s) => s.isNotEmpty)
          .toSet();
      final missedCount =
          (r['missedIngredients'] as List?)?.length ??
          (r['missedIngredientCount'] as int? ?? 0);
      final likes = r['likes'] as int? ?? 0;
      final matchCount = used.intersection(targets).length;
      final score = matchCount * 100 - missedCount * 10 + likes;
      final current = scoreMap[id];
      if (current == null || score > current) {
        scoreMap[id] = score;
      }
    }
    return scoreMap;
  }

  String _buildCacheKey({
    required List<String> translatedNames,
    List<String> cuisineFilters = const [],
    Set<String> dietGoals = const {},
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
    List<String> excludeIngredients = const [],
  }) {
    final ing = [...translatedNames]..sort();
    final cuisines = [...cuisineFilters]..sort();
    final diets = [...dietGoals.map((e) => e.toLowerCase())]..sort();
    final excludes = [...excludeIngredients.map((e) => e.toLowerCase())]..sort();
    final buffer = StringBuffer(_cacheKey);
    buffer.write('_i:${ing.join("|")}');
    if (cuisines.isNotEmpty) buffer.write('_c:${cuisines.join("|")}');
    if (diets.isNotEmpty) buffer.write('_d:${diets.join("|")}');
    if (minCalories != null) buffer.write('_minCal:$minCalories');
    if (maxCalories != null) buffer.write('_maxCal:$maxCalories');
    if (minProtein != null) buffer.write('_minProt:$minProtein');
    if (maxCarbs != null) buffer.write('_maxCarb:$maxCarbs');
    if (maxFat != null) buffer.write('_maxFat:$maxFat');
    if (excludes.isNotEmpty) buffer.write('_x:${excludes.join("|")}');
    return buffer.toString();
  }

  Iterable<RecipeModel> _applyPostFilters(
    List<RecipeModel> recipes, {
    List<String> cuisineFilters = const [],
    Set<String> dietGoals = const {},
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
    List<String> excludeIngredients = const [],
  }) {
    return recipes.where((r) {
      if (minCalories != null && r.nutrition.calories < minCalories) {
        return false;
      }
      if (maxCalories != null && r.nutrition.calories > maxCalories) {
        return false;
      }

      if (cuisineFilters.isNotEmpty) {
        final tags = r.tags.map((t) => t.toLowerCase()).toSet();
        final anyCuisine = cuisineFilters.any(tags.contains);
        if (!anyCuisine) return false;
      }

      if (dietGoals.isNotEmpty ||
          minProtein != null ||
          maxCarbs != null ||
          maxFat != null) {
        final goals = dietGoals.map((d) => d.toLowerCase()).toSet();
        final tags = r.tags.map((t) => t.toLowerCase()).toSet();

        bool hasAnyTag(Set<String> s, List<String> keys) =>
            keys.any(s.contains);

        // Diet groups: treat multiple selections as AND (เข้มงวด)
        const dietDefs = {
          'vegan': ['วีแกน', 'vegan'],
          'vegetarian': ['มังสวิรัติ', 'vegetarian'],
          'lacto-vegetarian': ['lacto-vegetarian', 'lacto vegetarian'],
          'ovo-vegetarian': ['ovo-vegetarian', 'ovo vegetarian'],
          'ketogenic': ['ketogenic', 'keto'],
          'paleo': ['paleo'],
        };
        final selectedDiets = goals.intersection(dietDefs.keys.toSet());
        if (selectedDiets.isNotEmpty) {
          for (final d in selectedDiets) {
            final keys = dietDefs[d] ?? const <String>[];
            final match = hasAnyTag(tags, keys);
            if (!match) return false; // ต้องผ่านทุก diet ที่เลือก
          }
        }

        // Gluten-Free / Dairy-Free via tags if present
        if (goals.contains('gluten-free')) {
          final ok = hasAnyTag(tags, [
            'ปลอดกลูเตน',
            'gluten-free',
            'glutenfree',
          ]);
          if (!ok) return false;
        }
        if (goals.contains('dairy-free')) {
          final ok = hasAnyTag(tags, ['ปลอดนม', 'dairy-free', 'dairyfree']);
          if (!ok) return false;
        }

        // Macro goals
        final proteinMin =
            minProtein ?? (goals.contains('high-protein') ? 30 : null);
        final carbsMax = maxCarbs ??
            ((goals.contains('low-carb') || goals.contains('ketogenic'))
                ? 20
                : null);
        final fatMax = maxFat ?? (goals.contains('low-fat') ? 15 : null);
        if (proteinMin != null && r.nutrition.protein < proteinMin)
          return false;
        if (carbsMax != null && r.nutrition.carbs > carbsMax) return false;
        if (fatMax != null && r.nutrition.fat > fatMax) return false;

        // For ketogenic/paleo/lacto/ovo — rely on API diet filtering (no strict local check)
      }

      // Exclude ingredients (allergens) by simple name contains check (lowercased)
      if (excludeIngredients.isNotEmpty) {
        final ingNames = r.ingredients
            .map((i) => i.name.toLowerCase().trim())
            .toList();
        for (final ex in excludeIngredients) {
          final e = ex.toLowerCase().trim();
          if (e.isEmpty) continue;
          if (ingNames.any((n) => n.contains(e) || e.contains(n))) {
            return false;
          }
        }
      }
      return true;
    });
  }
}
