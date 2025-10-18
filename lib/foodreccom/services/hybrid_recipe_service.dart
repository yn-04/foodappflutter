// lib/foodreccom/services/hybrid_recipe_service.dart
import 'dart:convert';
import '../models/ingredient_model.dart';
import '../models/cooking_history_model.dart';
import '../models/hybrid_models.dart';
import '../models/recipe/recipe_model.dart';
import 'enhanced_ai_recommendation_service.dart';
import 'rapidapi_recipe_service.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'api_usage_service.dart';

class HybridRecipeService {
  final EnhancedAIRecommendationService _aiService =
      EnhancedAIRecommendationService();
  final RapidAPIRecipeService _rapidApiService = RapidAPIRecipeService();
  bool useAiIngredientSelector = true;
  final Map<String, List<String>> _priorityCache = {};

  HybridRecipeService() {
    // Allow .env to turn off AI ingredient selection globally
    final flag = (dotenv.env['AI_GEMINI_ENABLED'] ?? 'true')
        .trim()
        .toLowerCase();
    useAiIngredientSelector =
        !(flag == 'false' || flag == '0' || flag == 'off' || flag == 'no');
  }

  Future<HybridRecommendationResult> getHybridRecommendations(
    List<IngredientModel> ingredients, {
    List<CookingHistory>? cookingHistory,
    int maxExternalRecipes = 12,
    // Optional user overrides/filters
    List<IngredientModel>? manualSelectedIngredients,
    List<String> cuisineFilters = const [], // english lowercase
    Set<String> dietGoals = const {},
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
    List<String> excludeIngredients = const [],
  }) async {
    final result = HybridRecommendationResult();

    try {
      final debugLogsEnabled = (dotenv.env['DEBUG_FILTER_LOGS'] ?? 'false')
          .trim()
          .toLowerCase();
      final isDebug =
          debugLogsEnabled == 'true' ||
          debugLogsEnabled == '1' ||
          debugLogsEnabled == 'on';

      final allergySet = excludeIngredients
          .map(_normalizeName)
          .where((e) => e.isNotEmpty)
          .toSet();

      final eligibleIngredients = <IngredientModel>[];
      var allergyFiltered = 0;
      var expiredFiltered = 0;
      var dessertFiltered = 0;
      for (final ingredient in ingredients) {
        final key = _normalizeName(ingredient.name);
        final isAllergy = allergySet.contains(key);
        final isExpired = ingredient.isExpired;
        final isDessert = _isDessertIngredient(ingredient);
        if (isAllergy) {
          allergyFiltered++;
          continue;
        }
        if (isExpired) {
          expiredFiltered++;
          continue;
        }
        if (isDessert) {
          dessertFiltered++;
          continue;
        }
        eligibleIngredients.add(ingredient);
      }

      if (isDebug) {
        if (allergySet.isNotEmpty) {
          print(
            '🐞 [AllergyFilter] skip=$allergyFiltered/${ingredients.length}',
          );
        }
        if (expiredFiltered > 0) {
          print(
            '🐞 [ExpiryFilter] skip=$expiredFiltered/${ingredients.length}',
          );
        }
        if (dessertFiltered > 0) {
          print(
            '🐞 [SavoryFilter] skip=$dessertFiltered/${ingredients.length}',
          );
        }
      }

      if (isDebug) {
        print('🐞 [InventoryDump] total=${ingredients.length}');
        for (final ing in ingredients) {
          print(
            '🐞 [Stock] ${ing.name} → days=${ing.daysToExpiry}, urgent=${ing.isUrgentExpiry}, near=${ing.isNearExpiry}, expired=${ing.isExpired}, allergySkip=${allergySet.contains(_normalizeName(ing.name))}',
          );
        }
      }

      if (eligibleIngredients.isEmpty) {
        print('⚠️ ไม่มีวัตถุดิบหลังกรองภูมิแพ้');
        result.error = 'ไม่พบวัตถุดิบที่ปลอดภัยสำหรับผู้ใช้';
        result.isSuccess = false;
        return result;
      }

      int minCap =
          int.tryParse((dotenv.env['AI_MIN_INGREDIENTS'] ?? '8').trim()) ?? 8;
      int maxCap =
          int.tryParse((dotenv.env['AI_MAX_INGREDIENTS'] ?? '12').trim()) ?? 12;
      if (maxCap <= 0) maxCap = 12;
      if (minCap <= 0) minCap = 1;
      if (minCap > maxCap) {
        minCap = maxCap;
      }
      maxCap = maxCap.clamp(1, eligibleIngredients.length).toInt();
      minCap = minCap.clamp(1, maxCap).toInt();
      final eligibleLookup = <String, IngredientModel>{};
      for (final ing in eligibleIngredients) {
        final key = _normalizeName(ing.name);
        if (key.isNotEmpty) {
          eligibleLookup.putIfAbsent(key, () => ing);
        }
      }

      IngredientModel? _matchEligible(String name) {
        final key = _normalizeName(name);
        if (key.isEmpty) return null;
        final direct = eligibleLookup[key];
        if (direct != null) return direct;
        for (final entry in eligibleLookup.entries) {
          final candidate = entry.key;
          if (candidate.contains(key) || key.contains(candidate)) {
            return entry.value;
          }
        }
        return null;
      }

      final ingredientPayload = eligibleIngredients.map((ingredient) {
        final data = ingredient.toAIFormat();
        return data;
      }).toList();

      final userAllergies = allergySet.isNotEmpty ? allergySet.join(', ') : '';

      final dietLines = <String>[];
      if (dietGoals.isNotEmpty) {
        dietLines.add('ข้อจำกัดการกิน: ${dietGoals.join(', ')}');
      }
      if (minCalories != null || maxCalories != null) {
        final buffer = StringBuffer('แคลอรี่ต่อมื้อ');
        if (minCalories != null) {
          buffer.write(' ≥$minCalories');
        }
        if (maxCalories != null) {
          if (minCalories != null) buffer.write(' และ');
          buffer.write(' ≤$maxCalories');
        }
        dietLines.add(buffer.toString());
      }
      if (minProtein != null) {
        dietLines.add('โปรตีนขั้นต่ำ ${minProtein}g');
      }
      if (maxCarbs != null) {
        dietLines.add('คาร์บสูงสุด ${maxCarbs}g');
      }
      if (maxFat != null) {
        dietLines.add('ไขมันสูงสุด ${maxFat}g');
      }

      final dietaryGuidance = dietLines.isEmpty
          ? 'ไม่มีข้อจำกัดเพิ่มเติม'
          : dietLines.join(' • ');

      final filterPrompt =
          '''
คุณเป็นผู้ช่วยจัดการวัตถุดิบ
ภารกิจ: เลือกวัตถุดิบจำนวนระหว่าง ${minCap} ถึง ${maxCap} รายการที่ควรหยิบมาใช้ก่อนที่สุด โดยให้คำนึงถึงภูมิแพ้และความใกล้หมดอายุอย่างเข้มงวด

ข้อมูลสุขภาพ:
- $dietaryGuidance

แนวทางการตัดสินใจ:
0) ห้ามเลือกวัตถุดิบที่อยู่ในรายการภูมิแพ้ของผู้ใช้ (ถ้ามี) และห้ามเลือกวัตถุดิบที่ `is_expired` = true
1) จัดลำดับความสำคัญตาม `days_to_expiry` จากน้อยไปมาก โดยเฉพาะลำดับ 0 (วันนี้) → 1 → 2 → 3 → ...
2) หากยังไม่ครบ ${minCap} ให้เติมจากวัตถุดิบที่เหลือ โดยพิจารณา `priority_score` สูงกว่า และยังไม่หมดอายุ
3) ห้ามสร้างชื่อใหม่ ต้องเลือกเฉพาะ `name` ที่ให้ไว้เท่านั้น

ข้อมูลวัตถุดิบ (JSON):
${jsonEncode(ingredientPayload)}

รายการภูมิแพ้ของผู้ใช้ (เว้นว่างได้ถ้าไม่ทราบ):
${userAllergies}

ตอบกลับเป็น JSON รูปแบบเดียวเท่านั้น:
{
  "priority_ingredients": ["ชื่อวัตถุดิบ1", "ชื่อวัตถุดิบ2", ...]
}

อย่าใส่คำอธิบายเพิ่มเติม หรือข้อความอื่นนอกเหนือ JSON
''';

      List<IngredientModel> selectedIngredients;
      String selectionLogLabel = 'Picked';
      List<IngredientModel>? manualOverride;
      if (manualSelectedIngredients != null &&
          manualSelectedIngredients.isNotEmpty) {
        final seen = <String>{};
        final filtered = <IngredientModel>[];
        final skipped = <String>[];
        for (final manual in manualSelectedIngredients) {
          final matched = _matchEligible(manual.name);
          if (matched == null) {
            skipped.add(manual.name);
            continue;
          }
          final key = _normalizeName(matched.name);
          if (key.isEmpty || !seen.add(key)) continue;
          filtered.add(matched);
          if (filtered.length >= maxCap) break;
        }
        if (filtered.isNotEmpty) {
          manualOverride = filtered;
          print(
            "👤 ผู้ใช้เลือกวัตถุดิบเอง: ${manualOverride.map((i) => i.name).join(', ')}",
          );
          if (skipped.isNotEmpty) {
            print(
              "⚠️ Manual selection ถูกกรองออก (หมดอายุ/ภูมิแพ้/ไม่รองรับ): ${skipped.join(', ')}",
            );
          }
        } else if (skipped.isNotEmpty) {
          print(
            "⚠️ Manual ingredient selections ทั้งหมดถูกกรองออก: ${skipped.join(', ')}",
          );
        }
      }

      if (manualOverride != null && manualOverride.isNotEmpty) {
        selectedIngredients = manualOverride;
        selectionLogLabel = 'Picked(Manual)';
      } else {
        if (useAiIngredientSelector) {
          final priorityIngredients = await _getPriorityIngredientNames(
            prompt: filterPrompt,
          );
          print("✅ Gemini เลือกวัตถุดิบที่ควรใช้ก่อน: $priorityIngredients");
          _logIngredientOrderFromNames(
            orderedNames: priorityIngredients,
            source: eligibleIngredients,
            label: 'Order',
          );

          // รวมวัตถุดิบหมดอายุวันนี้ (day=0) ทั้งหมดก่อน จากนั้นเติมตามลำดับที่ Gemini ให้มาจนถึงเพดาน (AI_MAX_INGREDIENTS, ดีฟอลต์ 6)
          final usable = List<IngredientModel>.from(eligibleIngredients);
          final dayZero = usable.where((i) => i.daysToExpiry == 0).toList();
          final selected = <IngredientModel>[];
          final seen = <String>{};
          String norm(String s) => s.trim().toLowerCase();
          for (final i in dayZero) {
            if (selected.length >= maxCap) break;
            final k = norm(i.name);
            if (seen.add(k)) selected.add(i);
          }

          if (selected.length < maxCap) {
            final nearExpiry =
                usable
                    .where((i) => i.isNearExpiry && i.daysToExpiry > 0)
                    .toList()
                  ..sort((a, b) => a.daysToExpiry.compareTo(b.daysToExpiry));
            for (final i in nearExpiry) {
              if (selected.length >= maxCap) break;
              final key = norm(i.name);
              if (seen.add(key)) {
                selected.add(i);
              }
            }
          }

          final lookup = {for (final i in usable) norm(i.name): i};
          if (selected.length < maxCap) {
            for (final n in priorityIngredients) {
              if (selected.length >= maxCap) break;
              final key = norm(n);
              if (key.isEmpty || seen.contains(key)) continue;
              IngredientModel? pick = lookup[key];
              if (pick == null) {
                for (final e in lookup.entries) {
                  if (e.key.contains(key) || key.contains(e.key)) {
                    pick = e.value;
                    break;
                  }
                }
              }
              if (pick != null) {
                seen.add(norm(pick.name));
                selected.add(pick);
              }
            }
          }
          if (selected.length < minCap) {
            final remainder = usable
                .where((i) => !seen.contains(norm(i.name)))
                .toList()
              ..sort((a, b) {
                final expiryCompare = a.daysToExpiry.compareTo(b.daysToExpiry);
                if (expiryCompare != 0) return expiryCompare;
                return b.priorityScore.compareTo(a.priorityScore);
              });
            for (final item in remainder) {
              if (selected.length >= minCap && selected.length >= maxCap) break;
              final key = norm(item.name);
              if (seen.add(key)) {
                selected.add(item);
              }
            }
          }
          selectedIngredients = selected;
          selectionLogLabel = 'Picked(AI)';
        } else {
          // Rule-based: sort by daysToExpiry asc, then priorityScore desc
          final usable = List<IngredientModel>.from(eligibleIngredients);
          usable.sort((a, b) {
            final c = a.daysToExpiry.compareTo(b.daysToExpiry);
            if (c != 0) return c;
            return b.priorityScore.compareTo(a.priorityScore);
          });
          selectedIngredients = usable.take(maxCap).toList();
          print(
            "🧭 Rule-based เลือกวัตถุดิบ: ${selectedIngredients.map((i) => i.name).join(', ')}",
          );
          selectionLogLabel = 'Picked(Rule)';
        }
      }
      if (selectedIngredients.length < minCap) {
        final filler = eligibleIngredients
            .where((i) => !selectedIngredients.contains(i))
            .toList()
          ..sort((a, b) {
            final expiryCompare = a.daysToExpiry.compareTo(b.daysToExpiry);
            if (expiryCompare != 0) return expiryCompare;
            return b.priorityScore.compareTo(a.priorityScore);
          });
        for (final item in filler) {
          if (selectedIngredients.length >= minCap &&
              selectedIngredients.length >= maxCap) {
            break;
          }
          selectedIngredients.add(item);
        }
      }
      _logIngredientOrderFromModels(
        selectedIngredients,
        label: selectionLogLabel,
      );
      print(
        "📦 ใช้วัตถุดิบ ${selectedIngredients.length} รายการสำหรับ RapidAPI: ${selectedIngredients.map((i) => i.name).join(', ')}",
      );

      // ✅ 2) ดึงเมนูจาก RapidAPI (ตั้งเป้าอย่างน้อย 12 เมนู) โดยใช้วัตถุดิบที่คัดกรองแล้ว
      if (selectedIngredients.isEmpty) {
        print('⚠️ ไม่มีวัตถุดิบที่ผ่านเกณฑ์สำหรับ RapidAPI');
        result.externalRecipes = [];
      } else {
        result.externalRecipes = await _rapidApiService
            .searchRecipesByIngredients(
              selectedIngredients,
              maxResults: maxExternalRecipes,
              ranking:
                  1, // prioritize using as many selected ingredients as possible
              cuisineFilters: cuisineFilters,
              dietGoals: dietGoals,
              minCalories: minCalories,
              maxCalories: maxCalories,
              minProtein: minProtein,
              maxCarbs: maxCarbs,
              maxFat: maxFat,
              excludeIngredients: excludeIngredients,
            );
      }
      result.externalFetchTime = DateTime.now();

      // ✅ 3) รวมผลลัพธ์ (ใช้ RapidAPI เท่านั้น แต่ผ่าน AI filter)
      result.externalRecipes = result.externalRecipes.where((recipe) {
        if (_isDessertRecipe(recipe)) {
          print('🍮 ข้ามเมนูของหวาน: ${recipe.name}');
          return false;
        }
        return true;
      }).toList();
      result.combinedRecommendations = [...result.externalRecipes];

      // Log current API usage summary to help monitor quotas
      final usage = await ApiUsageService.summary();
      print('📊 $usage');

      // ✅ 4) วิเคราะห์ผลลัพธ์
      result.hybridAnalysis = HybridAnalysis.analyze(
        aiRecipes: [], // เราใช้ AI แค่ช่วยคัดกรอง ไม่ generate เมนู
        externalRecipes: result.externalRecipes,
        urgentIngredientsCount: ingredients
            .where((i) => i.isUrgentExpiry)
            .length,
      );

      result.isSuccess = true;
    } catch (e) {
      result.error = e.toString();
      result.isSuccess = false;
      print("❌ HybridRecommendation Error: $e");
    }

    return result;
  }

  /// Helper: parse priority_ingredients JSON
  List<String> _parsePriorityIngredients(String? responseText) {
    if (responseText == null || responseText.isEmpty) return [];
    try {
      final clean = responseText
          .replaceAll("```json", "")
          .replaceAll("```", "")
          .trim();
      final Map<String, dynamic> parsed = jsonDecode(clean);
      final list = parsed['priority_ingredients'] as List?;
      return list?.map((e) => e.toString()).toList() ?? [];
    } catch (e) {
      print("⚠️ Parse priority ingredients error: $e");
      return [];
    }
  }

  Future<List<String>> _getPriorityIngredientNames({
    required String prompt,
  }) async {
    final cached = _priorityCache[prompt];
    if (cached != null && cached.isNotEmpty) {
      print('♻️ ใช้ cache priority ingredients');
      return List<String>.from(cached);
    }
    // First try smart generator which handles SDK + REST fallback
    try {
      final smartText = await _aiService.generateTextSmart(prompt);
      final smartParsed = _parsePriorityIngredients(smartText);
      if (smartParsed.isNotEmpty) {
        _priorityCache[prompt] = List<String>.from(smartParsed);
        return smartParsed;
      }
    } catch (_) {}

    bool _geminiEnabled() {
      final v = (dotenv.env['AI_GEMINI_ENABLED'] ?? 'true')
          .trim()
          .toLowerCase();
      return !(v == 'false' || v == '0' || v == 'off');
    }

    if (!_geminiEnabled()) {
      print('ℹ️ Gemini disabled via env — skip AI filtering');
      return [];
    }
    Future<List<String>> runModel(GenerativeModel model, String label) async {
      try {
        final response = await model.generateContent([Content.text(prompt)]);
        final parsed = _parsePriorityIngredients(response.text);
        if (parsed.isNotEmpty) {
          return parsed;
        }
        print('⚠️ $label model returned empty list, will fallback');
      } on GenerativeAIException catch (e) {
        final message = e.message;
        print('⚠️ $label model error: $message');
        final isOverloaded =
            message.contains('503') ||
            message.toLowerCase().contains('unavailable') ||
            message.toLowerCase().contains('overloaded');
        final isQuota =
            message.toLowerCase().contains('quota') ||
            message.toLowerCase().contains('limit');
        if (isOverloaded) {
          print('ℹ️ Model overloaded, attempting fallback model');
        }
        if (isQuota) {
          print('ℹ️ Rotating Gemini API key due to quota limit');
          try {
            _aiService.rotateApiKey();
          } catch (err) {
            print('⚠️ Unable to rotate key: $err');
          }
        }
      } catch (e) {
        print('⚠️ $label model unexpected error: $e');
      }
      return [];
    }

    final primary = await runModel(_aiService.primaryModel, 'Primary');
    if (primary.isNotEmpty) {
      _priorityCache[prompt] = List<String>.from(primary);
      return primary;
    }

    final fallback = await runModel(_aiService.fallbackModel, 'Fallback');
    if (fallback.isNotEmpty) {
      _priorityCache[prompt] = List<String>.from(fallback);
      return fallback;
    }

    print('ℹ️ ใช้วิธีเรียงตามวันหมดอายุแทน เนื่องจาก Gemini ใช้งานไม่ได้');
    final cachedAgain = _priorityCache[prompt];
    if (cachedAgain != null && cachedAgain.isNotEmpty) {
      print('♻️ ใช้ cache priority ingredients หลังจาก Gemini ล้มเหลว');
      return List<String>.from(cachedAgain);
    }
    return [];
  }

  void _logIngredientOrderFromNames({
    required Iterable<String> orderedNames,
    required List<IngredientModel> source,
    String label = 'Order',
  }) {
    final names = orderedNames.toList();
    if (names.isEmpty) {
      print('🐞 [$label] (empty)');
      return;
    }

    final normalizedLookup = <String, IngredientModel>{};
    for (final ingredient in source) {
      normalizedLookup[_normalizeName(ingredient.name)] = ingredient;
    }

    final seen = <String>{};
    var printedAny = false;

    for (final rawName in names) {
      final normalized = _normalizeName(rawName);
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }

      final ingredient = _findIngredientByName(
        normalizedLookup: normalizedLookup,
        searchPool: source,
        normalizedName: normalized,
      );

      if (ingredient == null) {
        print('🐞 [$label] $rawName → not_found');
        printedAny = true;
        continue;
      }

      _logIngredientDetail(ingredient, label);
      printedAny = true;
    }

    if (!printedAny) {
      print('🐞 [$label] (no matches)');
    }
  }

  void _logIngredientOrderFromModels(
    List<IngredientModel> items, {
    String label = 'Order',
  }) {
    if (items.isEmpty) {
      print('🐞 [$label] (empty)');
      return;
    }

    for (final ingredient in items) {
      _logIngredientDetail(ingredient, label);
    }
  }

  void _logIngredientDetail(IngredientModel ingredient, String label) {
    final urgent = ingredient.isUrgentExpiry ? 'true' : 'false';
    final near = ingredient.isNearExpiry ? 'true' : 'false';
    final expired = ingredient.isExpired ? 'true' : 'false';
    final days = ingredient.daysToExpiry;
    final score = ingredient.priorityScore;
    final expiryNote = expired == 'true' ? ', expired=true' : '';
    print(
      '🐞 [$label] ${ingredient.name} → days=$days, urgent=$urgent, near=$near, score=$score$expiryNote',
    );
  }

  IngredientModel? _findIngredientByName({
    required Map<String, IngredientModel> normalizedLookup,
    required List<IngredientModel> searchPool,
    required String normalizedName,
  }) {
    if (normalizedLookup.containsKey(normalizedName)) {
      return normalizedLookup[normalizedName];
    }

    for (final entry in normalizedLookup.entries) {
      if (entry.key.contains(normalizedName) ||
          normalizedName.contains(entry.key)) {
        return entry.value;
      }
    }

    for (final ingredient in searchPool) {
      final ingredientName = _normalizeName(ingredient.name);
      if (ingredientName == normalizedName) {
        return ingredient;
      }
    }

    return null;
  }

  bool _isDessertIngredient(IngredientModel ingredient) {
    final category = Categories.normalize(ingredient.category).toLowerCase();
    if (category.isNotEmpty) {
      for (final keyword in _dessertCategoryKeywords) {
        if (category.contains(keyword)) return true;
      }
    }

    final name = ingredient.name.trim().toLowerCase();
    for (final keyword in _dessertNameKeywords) {
      if (name.contains(keyword)) return true;
    }
    return false;
  }

  bool _isDessertRecipe(RecipeModel recipe) {
    final category = recipe.category.trim().toLowerCase();
    if (category.isNotEmpty) {
      for (final keyword in _dessertCategoryKeywords) {
        if (category.contains(keyword)) return true;
      }
    }
    for (final tag in recipe.tags) {
      final lower = tag.trim().toLowerCase();
      if (lower.isEmpty) continue;
      for (final keyword in _dessertCategoryKeywords) {
        if (lower.contains(keyword)) return true;
      }
      for (final keyword in _dessertNameKeywords) {
        if (lower.contains(keyword)) return true;
      }
    }
    final name = recipe.name.trim().toLowerCase();
    for (final keyword in _dessertNameKeywords) {
      if (name.contains(keyword)) return true;
    }
    final description = recipe.description.trim().toLowerCase();
    for (final keyword in _dessertNameKeywords) {
      if (description.contains(keyword)) return true;
    }
    return false;
  }

  static const Set<String> _dessertCategoryKeywords = {
    'ขนม',
    'เบเกอรี่',
    'ของหวาน',
    'dessert',
    'sweet',
    'snack',
    'เบเกอรี',
  };

  static const Set<String> _dessertNameKeywords = {
    'เค้ก',
    'คุกกี้',
    'บราวนี่',
    'พาย',
    'โดนัท',
    'วาฟเฟิล',
    'แพนเค้ก',
    'พุดดิ้ง',
    'ไอศกรีม',
    'ไอศครีม',
    'ของหวาน',
    'ขนม',
    'คาราเมล',
    'มาร์ชเมลโล่',
    'มาชเมลโล่',
    'ลูกอม',
    'ช็อกโกแลต',
    'คัสตาร์ด',
    'ทอฟฟี่',
    'ครีมพัฟ',
    'บิสกิต',
    'biscuit',
    'cookie',
    'cake',
    'brownie',
    'dessert',
    'sweet',
    'donut',
    'waffle',
    'pancake',
    'candy',
    'ice cream',
    'pudding',
    'custard',
    'marshmallow',
    'chocolate',
  };

  String _normalizeName(String name) => name.trim().toLowerCase();
}
