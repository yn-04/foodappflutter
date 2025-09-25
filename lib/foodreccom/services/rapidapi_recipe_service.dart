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
  static final String _rapidApiKey = dotenv.env['RAPIDAPI_KEY'] ?? '';
  static const String _spoonacularBase =
      'https://spoonacular-recipe-food-nutrition-v1.p.rapidapi.com';

  final Map<String, String> _headers = {
    'X-RapidAPI-Key': dotenv.env['RAPIDAPI_KEY'] ?? '',
    'X-RapidAPI-Host': 'spoonacular-recipe-food-nutrition-v1.p.rapidapi.com',
  };

  static const String _cacheKey = 'rapidapi_cached_recipes';

  /// 🔎 ค้นหาสูตรอาหารจากวัตถุดิบ
  Future<List<RecipeModel>> searchRecipesByIngredients(
    List<IngredientModel> ingredients, {
    int maxResults = 5, // ✅ fix ให้ดึง 5 เมนูเสมอ
    int ranking = 1,
    List<String> cuisineFilters = const [], // english lowercase
    Set<String> dietGoals = const {}, // vegan, high-fiber, high-protein, low-carb
    int? minCalories,
    int? maxCalories,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await ApiUsageService.initDaily();
    final ingredientNames = ingredients.map((i) => i.name).toList();

    // ✅ แปลวัตถุดิบไทย → อังกฤษ และคัดกรองคำที่ไม่ใช่วัตถุดิบ
    final translatedNames = _filterIngredientTokens(
      IngredientTranslator.translateList(ingredientNames),
    );

    final cacheKey = '${_cacheKey}_${translatedNames.join(",")}';
    print('🧪 RapidAPI ingredients (EN): ${translatedNames.join(', ')} [${translatedNames.length}]');

    try {
      // If user applied cuisine/diet/calorie filters, try complexSearch first
      if (!await ApiUsageService.canUseRapid()) {
        print('⛔ RapidAPI quota reached for today → use cache if available');
        final cached = prefs.getString(cacheKey);
        if (cached != null) {
          final data = json.decode(cached);
          final recipes = (data['recipes'] as List)
              .map((r) => RecipeModel.fromJson(r))
              .toList();
          print("♻️ ใช้ cache recipes (${recipes.length}) [quota]");
          return recipes;
        }
        return [];
      }

      // If user applied cuisine/diet/calorie filters, try complexSearch first
      final hasAdvancedFilters =
          cuisineFilters.isNotEmpty || dietGoals.isNotEmpty || minCalories != null || maxCalories != null;

      if (hasAdvancedFilters) {
        final complexRes = await _fetchComplexSearchRelaxed(
          translatedNames,
          number: maxResults,
          cuisines: cuisineFilters,
          dietGoals: dietGoals,
          minCalories: minCalories,
          maxCalories: maxCalories,
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
          ).take(maxResults).toList();
          await prefs.setString(
            cacheKey,
            json.encode({
              'recipes': recipes.map((r) => r.toJson()).toList(),
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          print("✅ RapidAPI cache saved (${recipes.length} recipes) [complexSearch]");
          if (recipes.isNotEmpty) return recipes;
          print('ℹ️ complexSearch returned no recipes after filters → fallback to findByIngredients');
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
      if (!await ApiUsageService.allowRapidCall()) {
        print('⏳ RapidAPI throttled/cooldown → skip call');
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

        // ✅ เก็บ ID พร้อมคะแนน แล้วถ้ายังได้ไม่ครบ ลองขยายเงื่อนไขเพื่อให้ครบ 5
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

          // 2) ลดจำนวนวัตถุดิบลงทีละตัวเพื่อขยายผลลัพธ์
          var reduceCount = 1;
          while (scoreMap.length < maxResults && reduceCount < translatedNames.length) {
            final reduced = translatedNames.take(translatedNames.length - reduceCount).toList();
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
        await prefs.setString(
          cacheKey,
          json.encode({
            'recipes': recipes.map((r) => r.toJson()).toList(),
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }),
        );
        print("✅ RapidAPI cache saved (${recipes.length} recipes)");

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
        if (await ApiUsageService.allowRapidCall()) {
          print("🌍 Retry (ASCII-only) RapidAPI: $url2");
          await ApiUsageService.countRapid();
        } else {
          print('⏳ RapidAPI throttled/cooldown → skip retry (ASCII-only)');
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
          ).take(maxResults).toList();

          await prefs.setString(
            cacheKey,
            json.encode({
              'recipes': recipes.map((r) => r.toJson()).toList(),
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          print("✅ RapidAPI cache saved (${recipes.length} recipes) [ASCII-only]");

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
        if (await ApiUsageService.allowRapidCall()) {
          print("🌍 Retry (reduced set) RapidAPI: $url3");
          await ApiUsageService.countRapid();
        } else {
          print('⏳ RapidAPI throttled/cooldown → skip retry (reduced)');
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
          ).take(maxResults.clamp(1, 3)).toList();

          await prefs.setString(
            cacheKey,
            json.encode({
              'recipes': recipes.map((r) => r.toJson()).toList(),
              'timestamp': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          print("✅ RapidAPI cache saved (${recipes.length} recipes) [reduced]");

          return recipes;
        }
      }

      throw Exception(
        'RapidAPI Error: ${response?.statusCode} - ${response?.body}',
      );
    } catch (e) {
      print('❌ Error searchRecipesByIngredients: $e');

      // ✅ fallback: โหลดจาก cache ถ้ามี
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        final data = json.decode(cached);
        final recipes = (data['recipes'] as List)
            .map((r) => RecipeModel.fromJson(r))
            .toList();
        print("♻️ ใช้ cache recipes (${recipes.length})");
        return recipes;
      }

      return [];
    }
  }

  /// 📌 ดึงรายละเอียดสูตรอาหาร
  Future<RecipeModel?> _getRecipeDetails(int recipeId) async {
    try {
      final url = Uri.parse('$_spoonacularBase/recipes/$recipeId/information?includeNutrition=true');
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
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
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
  }) {
    final query = <String, String>{
      'number': number.toString(),
      'addRecipeInformation': 'true',
      'ignorePantry': 'true',
    };
    if (names.isNotEmpty) query['includeIngredients'] = names.join(',');
    if (cuisines.isNotEmpty) query['cuisine'] = cuisines.join(',');
    // Diet mapping
    if (dietGoals.contains('vegan')) query['diet'] = 'vegan';
    if (dietGoals.contains('high-protein')) query['minProtein'] = '20';
    if (dietGoals.contains('low-carb')) query['maxCarbs'] = '25';
    if (dietGoals.contains('high-fiber')) query['minFiber'] = '5';
    if (minCalories != null) query['minCalories'] = minCalories.toString();
    if (maxCalories != null) query['maxCalories'] = maxCalories.toString();

    final encoded = query.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return Uri.parse('$_spoonacularBase/recipes/complexSearch?$encoded');
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
  }) async {
    final url = _buildComplexSearchUrl(
      names,
      number: number,
      cuisines: cuisines,
      dietGoals: dietGoals,
      minCalories: minCalories,
      maxCalories: maxCalories,
    );
    if (!await ApiUsageService.allowRapidCall()) {
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
  }) async {
    // Step 1: as-is
    var res = await _fetchComplexSearch(
      names,
      number: number,
      cuisines: cuisines,
      dietGoals: dietGoals,
      minCalories: minCalories,
      maxCalories: maxCalories,
    );
    if (res != null && res.isNotEmpty) return res;

    // Step 2: relax by dropping macro thresholds (keep vegan if chosen)
    res = await _fetchComplexSearch(
      names,
      number: number,
      cuisines: cuisines,
      dietGoals:
          dietGoals.difference({'high-protein', 'low-carb', 'high-fiber'}),
      minCalories: minCalories,
      maxCalories: maxCalories,
    );
    if (res != null && res.isNotEmpty) return res;

    // Step 3: drop cuisine but keep diet
    res = await _fetchComplexSearch(
      names,
      number: number,
      cuisines: const [],
      dietGoals: dietGoals,
      minCalories: minCalories,
      maxCalories: maxCalories,
    );
    if (res != null && res.isNotEmpty) return res;

    // Step 4: keep cuisine, drop diet
    res = await _fetchComplexSearch(
      names,
      number: number,
      cuisines: cuisines,
      dietGoals: const {},
      minCalories: minCalories,
      maxCalories: maxCalories,
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
      'fresh', 'ripe', 'large', 'small', 'medium', 'piece', 'pieces', 'pack',
      'bag', 'bottle', 'can', 'cup', 'tbsp', 'tsp', 'ml', 'l', 'kg', 'g',
      'pc', 'pcs', 'optional', 'extra', 'some'
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
          .map((e) => (e is Map ? e['name']?.toString() ?? '' : '').toLowerCase())
          .where((s) => s.isNotEmpty)
          .toSet();
      final missedCount = (r['missedIngredients'] as List?)?.length ??
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

  Iterable<RecipeModel> _applyPostFilters(
    List<RecipeModel> recipes, {
    List<String> cuisineFilters = const [],
    Set<String> dietGoals = const {},
    int? minCalories,
    int? maxCalories,
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

      if (dietGoals.isNotEmpty) {
        final goals = dietGoals.map((d) => d.toLowerCase()).toSet();
        // Vegan: rely on tag or zero animal products (approx via tags)
        if (goals.contains('vegan')) {
          final tags = r.tags.map((t) => t.toLowerCase()).toSet();
          final isVegan = tags.contains('วีแกน') || tags.contains('vegan');
          if (!isVegan) return false;
        }
        if (goals.contains('high-protein')) {
          if (r.nutrition.protein < 20) return false;
        }
        if (goals.contains('low-carb')) {
          if (r.nutrition.carbs > 25) return false;
        }
        if (goals.contains('high-fiber')) {
          if (r.nutrition.fiber < 5) return false;
        }
      }
      return true;
    });
  }
}
