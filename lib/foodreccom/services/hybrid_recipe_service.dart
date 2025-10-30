// lib/foodreccom/services/hybrid_recipe_service.dart
import 'dart:convert';
import '../models/cooking_history_model.dart';
import '../models/hybrid_models.dart';
import '../models/ingredient_model.dart';
import '../models/recipe/recipe_model.dart';
import '../utils/allergy_utils.dart';
import '../utils/ingredient_translator.dart';
import '../utils/ingredient_utils.dart';
import 'nutrition_estimator.dart';
import 'enhanced_ai_recommendation_service.dart';
import 'rapidapi_recipe_service.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'api_usage_service.dart';

class HybridRecipeService {
  static const int _aiRecommendationTarget = 7;
  static const int _externalRecommendationTarget = 5;
  static const int _urgentExpiryDayThreshold = 0;

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
    int maxExternalRecipes = 10,
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

      final allergyExpansion = AllergyUtils.expandAllergens(excludeIngredients);
      final allergySet = allergyExpansion.all;

      final eligibleIngredients = <IngredientModel>[];
      var allergyFiltered = 0;
      var expiredFiltered = 0;
      var dessertFiltered = 0;
      for (final ingredient in ingredients) {
        final isAllergy = AllergyUtils.matchesAllergen(
          ingredient.name,
          allergySet,
        );
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
          final skipAllergy = AllergyUtils.matchesAllergen(
            ing.name,
            allergySet,
          );
          print(
            '🐞 [Stock] ${ing.name} → days=${ing.daysToExpiry}, urgent=${ing.isUrgentExpiry}, near=${ing.isNearExpiry}, expired=${ing.isExpired}, allergySkip=$skipAllergy',
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
      final urgentToday = eligibleIngredients
          .where((ingredient) =>
              ingredient.daysToExpiry <= _urgentExpiryDayThreshold)
          .toList();
      final baseMaxCap = maxCap;
      if (urgentToday.length > maxCap) {
        maxCap = urgentToday.length;
      }
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

      final mustUseAllUrgent = urgentToday.length > baseMaxCap;

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

      final allergyList = allergySet.toList()..sort();
      final allergyJson = jsonEncode(allergyList);
      final allergyCoverage = describeAllergyCoverage(excludeIngredients);

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

ข้อมูลภูมิแพ้ (ตีความครอบคลุมทุกคำพ้อง/ผลิตภัณฑ์เกี่ยวเนื่อง):
$allergyCoverage

แนวทางการตัดสินใจ:
0) ห้ามเลือกวัตถุดิบที่อยู่ในรายการภูมิแพ้ของผู้ใช้ และห้ามเลือกวัตถุดิบที่ `is_expired` = true
   - แต่ละรายการภูมิแพ้ให้ตีความครอบคลุมทั้งวัตถุดิบโดยตรงและผลิตภัณฑ์/ส่วนประกอบที่มีต้นกำเนิดจากสารนั้น (เช่น แพ้นมวัว → งดนม เนย ชีส โยเกิร์ต เวย์ เคซีน, แพ้ถั่วลิสง → งดถั่วลิสง เนยถั่ว ซอส/เครื่องจิ้มที่ทำจากถั่วลิสง, ฯลฯ)
   - ตรวจสอบซอส เครื่องปรุง ผงปรุงรส เส้น และอาหารหมักหรือบ่ม เช่น ซีอิ๊วขาว/ซีอิ๊วดำ/ซอสถั่วเหลือง (soy sauce, shoyu, ponzu), ซอสเทอริยากิ, ซอสฮอยซิน, วูสเตอร์เชอร์, น้ำซุปก้อน, ซอสพริก/น้ำพริก/น้ำมันพริก (sriracha, hot sauce, gochujang, sambal), เกล็ดขนมปัง, เส้นพาสต้า/ราเมน/อุด้ง/โซบะ, บะหมี่กึ่งสำเร็จรูป (มาม่า/ไวไว/ยำยำ/แบรนด์อื่น), ขนมปัง/พิซซ่า/เบเกอรี่หมัก, โยเกิร์ต, ชีส, ไวน์, เบียร์, คอมบูชะ — หากมีสารก่อภูมิแพ้ต้องตัดออกทั้งหมด
   - ใช้รายการ `allergy_keywords` ที่ให้มา (และคำอธิบายด้านบน) เป็น canonical list เพื่อตรวจสอบคำพ้อง ศัพท์แสลง และชื่อการค้าของสารก่อภูมิแพ้ทุกชนิด
   - ถ้าชื่อวัตถุดิบหรือภูมิแพ้เป็นภาษาไทย ให้พิจารณาคำแปลหรือชื่อภาษาอังกฤษ รวมถึงคำย่อ ชื่อการค้า และคำที่สื่อถึงวัตถุดิบเดียวกัน
1) จัดลำดับความสำคัญตาม `days_to_expiry` จากน้อยไปมาก โดยเฉพาะลำดับ 0 (วันนี้) → 1 → 2 → 3 → ...
2) หากยังไม่ครบ ${minCap} ให้เติมจากวัตถุดิบที่เหลือ โดยพิจารณา `priority_score` สูงกว่า และยังไม่หมดอายุ
3) ห้ามสร้างชื่อใหม่ ต้องเลือกเฉพาะ `name` ที่ให้ไว้เท่านั้น

ข้อมูลวัตถุดิบ (JSON):
${jsonEncode(ingredientPayload)}

รายการภูมิแพ้ของผู้ใช้ (JSON array; รวมคำพ้องและคำแปล, [] หมายถึงไม่มีข้อมูล):
${allergyJson}

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
        selectedIngredients =
            _ensureUrgentIngredientCoverage(manualOverride, urgentToday);
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
                if (!_shouldFavorForPrioritySelection(pick) &&
                    selected.length >= minCap) {
                  continue;
                }
                seen.add(norm(pick.name));
                selected.add(pick);
              }
            }
          }
          if (selected.length < minCap) {
            final remainder =
                usable.where((i) => !seen.contains(norm(i.name))).toList()
                  ..sort((a, b) {
                    final expiryCompare = a.daysToExpiry.compareTo(
                      b.daysToExpiry,
                    );
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
          selectedIngredients =
              _ensureUrgentIngredientCoverage(selected, urgentToday);
          selectedIngredients = _enforceSelectionCap(
            selectedIngredients,
            urgentToday,
            maxCap,
          );
          selectionLogLabel = 'Picked(AI)';
        } else {
          // Rule-based: sort by daysToExpiry asc, then priorityScore desc
          final usable = List<IngredientModel>.from(eligibleIngredients);
          usable.sort((a, b) {
            final c = a.daysToExpiry.compareTo(b.daysToExpiry);
            if (c != 0) return c;
            return b.priorityScore.compareTo(a.priorityScore);
          });
          selectedIngredients =
              _ensureUrgentIngredientCoverage(
                usable.take(maxCap).toList(),
                urgentToday,
              );
          selectedIngredients = _enforceSelectionCap(
            selectedIngredients,
            urgentToday,
            maxCap,
          );
          print(
            "🧭 Rule-based เลือกวัตถุดิบ: ${selectedIngredients.map((i) => i.name).join(', ')}",
          );
          selectionLogLabel = 'Picked(Rule)';
        }
      }
      if (selectedIngredients.length < minCap) {
        final filler =
            eligibleIngredients
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
      selectedIngredients =
          _ensureUrgentIngredientCoverage(selectedIngredients, urgentToday);
      selectedIngredients = _enforceSelectionCap(
        selectedIngredients,
        urgentToday,
        maxCap,
      );
      }
      _logIngredientOrderFromModels(
        selectedIngredients,
        label: selectionLogLabel,
      );
      print(
        "📦 ใช้วัตถุดิบ ${selectedIngredients.length} รายการสำหรับ RapidAPI: ${selectedIngredients.map((i) => i.name).join(', ')}",
      );

      // ✅ 2) ดึงเมนูจาก RapidAPI (ตั้งเป้าอย่างน้อย 5 เมนู) โดยใช้วัตถุดิบที่คัดกรองแล้ว
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
              excludeIngredients: allergyExpansion.englishOnly.toList(),
            );
      }
      result.externalFetchTime = DateTime.now();

      // ✅ 3) ขอเมนูจาก AI (เพิ่มความหลากหลาย + อ้างอิงเว็บไซต์ที่เชื่อถือได้)
      if (selectedIngredients.isNotEmpty) {
        try {
          result.aiRecommendations = await _generateAiRecipes(
            selectedIngredients: selectedIngredients,
            inventory: eligibleIngredients,
            allergyNames: allergySet.toList(),
            cuisineFilters: cuisineFilters,
            dietGoals: dietGoals,
            minCalories: minCalories,
            maxCalories: maxCalories,
            minProtein: minProtein,
            maxCarbs: maxCarbs,
            maxFat: maxFat,
            urgentIngredientNames: urgentToday.map((e) => e.name).toList(),
            mustUseAllUrgent: mustUseAllUrgent,
          );
          result.aiGenerationTime = DateTime.now();
        } catch (e, st) {
          print('⚠️ AI recommendation failed: $e');
          debugPrintStack(stackTrace: st);
          result.aiRecommendations = [];
        }
      }

      result.aiRecommendations = result.aiRecommendations.where((recipe) {
        if (_isDessertRecipe(recipe)) {
          print('🍮 ข้ามเมนูของหวาน (AI): ${recipe.name}');
          return false;
        }
        return true;
      }).toList();

      // ✅ 4) รวมผลลัพธ์พร้อมคำนวณ Match Score
      result.aiRecommendations = _prioritizeRecipesBySelectedCoverage(
        result.aiRecommendations,
        selectedIngredients,
      );
      result.aiRecommendations = _applyNutritionEstimates(
        result.aiRecommendations.take(_aiRecommendationTarget).toList(),
      );

      result.externalRecipes = result.externalRecipes.where((recipe) {
        if (_isDessertRecipe(recipe)) {
          print('🍮 ข้ามเมนูของหวาน: ${recipe.name}');
          return false;
        }
        return true;
      }).toList();

      result.externalRecipes = _prioritizeRecipesBySelectedCoverage(
        result.externalRecipes,
        selectedIngredients,
      );
      result.externalRecipes =
          result.externalRecipes.take(_externalRecommendationTarget).toList();

      result.combinedRecommendations = _dedupeRecipes([
        ...result.aiRecommendations,
        ...result.externalRecipes,
      ]);

      // Log current API usage summary to help monitor quotas
      final usage = await ApiUsageService.summary();
      print('📊 $usage');

      // ✅ 5) วิเคราะห์ผลลัพธ์
      result.hybridAnalysis = HybridAnalysis.analyze(
        aiRecipes: result.aiRecommendations,
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

  Future<List<RecipeModel>> _generateAiRecipes({
    required List<IngredientModel> selectedIngredients,
    required List<IngredientModel> inventory,
    required List<String> allergyNames,
    required List<String> cuisineFilters,
    required Set<String> dietGoals,
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
    List<String> urgentIngredientNames = const [],
    bool mustUseAllUrgent = false,
    int? targetCount,
  }) async {
    if (!_isAiGenerationEnabled()) {
      print('ℹ️ AI generation disabled → ใช้ fallback');
      return _fallbackAiRecommendations(
        selectedIngredients,
        cuisineFilters: cuisineFilters,
        dietGoals: dietGoals,
        minCalories: minCalories,
        maxCalories: maxCalories,
        minProtein: minProtein,
        maxCarbs: maxCarbs,
        maxFat: maxFat,
        urgentIngredientNames: urgentIngredientNames,
        mustUseAllUrgent: mustUseAllUrgent,
        targetCount: targetCount ?? _aiRecommendationTarget,
      );
    }
    if (selectedIngredients.isEmpty) return [];

    final hasStrictFilters =
        cuisineFilters.isNotEmpty ||
        dietGoals.isNotEmpty ||
        minCalories != null ||
        maxCalories != null ||
        minProtein != null ||
        maxCarbs != null ||
        maxFat != null;
    final int desiredCount = targetCount ??
        (hasStrictFilters ? 5 : _aiRecommendationTarget);

    final hostToSource = <String, String>{};
    for (final site in _trustedReferenceSites) {
      final url = site['url']!;
      final host = _normalizeHost(Uri.parse(url).host);
      hostToSource[host] = site['name']!;
    }

    final ingredientLines = selectedIngredients
        .map((ingredient) {
          final qty = ingredient.quantity % 1 == 0
              ? ingredient.quantity.toStringAsFixed(0)
              : ingredient.quantity.toStringAsFixed(1);
          final unit = ingredient.unit.trim().isEmpty
              ? ''
              : ' ${ingredient.unit}';
          final expiry = ingredient.expiryDate != null
              ? ' (หมดอายุใน ${ingredient.daysToExpiry} วัน)'
              : '';
          return '- ${ingredient.name}$unit x $qty$expiry';
        })
        .join('\n');

    final urgentTodayNames = (urgentIngredientNames.isNotEmpty
            ? urgentIngredientNames
            : selectedIngredients
                .where(
                  (ingredient) =>
                      ingredient.daysToExpiry <= _urgentExpiryDayThreshold,
                )
                .map((ingredient) => ingredient.name)
                .toList())
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final nearExpiry = inventory
        .where((i) => i.isUrgentExpiry || i.isNearExpiry)
        .map((i) => i.name)
        .toList();

    final allergyLine = allergyNames.isEmpty
        ? 'ไม่มี'
        : allergyNames.join(', ');
    final hasCuisineFilters = cuisineFilters.isNotEmpty;
    final cuisineLine = hasCuisineFilters
        ? '${cuisineFilters.join(', ')} (จำกัดเฉพาะสัญชาติเหล่านี้)'
        : 'เน้นอาหารไทยหรือ Asian comfort food';
    final dietLine = dietGoals.isEmpty ? 'ไม่มี' : dietGoals.join(', ');

    final hasDietGoals = dietGoals.isNotEmpty;
    final nutritionParts = <String>[];
    if (minCalories != null || maxCalories != null) {
      final min = minCalories != null ? '≥$minCalories' : '';
      final max = maxCalories != null ? '≤$maxCalories' : '';
      nutritionParts.add('แคลอรี่ $min $max'.trim());
    }
    if (minProtein != null) {
      nutritionParts.add('โปรตีน ≥$minProtein g');
    }
    if (maxCarbs != null) {
      nutritionParts.add('คาร์บ ≤$maxCarbs g');
    }
    if (maxFat != null) {
      nutritionParts.add('ไขมัน ≤$maxFat g');
    }
    final nutritionLine = nutritionParts.isEmpty
        ? 'ไม่กำหนด'
        : nutritionParts.join(', ');

    final cuisineRule = hasCuisineFilters
        ? 'เลือกเมนูจากสัญชาติที่ผู้ใช้เลือกเท่านั้น (${cuisineFilters.join(', ')}) ห้ามแนะนำสัญชาติอื่น'
        : 'เลือกเมนูให้ครอบคลุมอย่างน้อย 3 สัญชาติที่แตกต่างกันจากรายการนี้ (ไทย, จีน, ญี่ปุ่น, เกาหลี, เวียดนาม, อินเดีย, อเมริกา, อังกฤษ, ฝรั่งเศส, เยอรมัน, อิตาเลียน, เม็กซิกัน, สเปน) โดยเลือกสัญชาติที่เข้ากับวัตถุดิบมากที่สุด (ไม่จำเป็นต้องใช้ครบทั้งหมดหากวัตถุดิบไม่เอื้อ)';
    final cuisineTagRule = hasCuisineFilters
        ? 'แท็กของแต่ละเมนูต้องมีชื่อสัญชาติจากตัวเลือกที่ผู้ใช้เลือก (เช่น "${cuisineFilters.map((c) => c.toLowerCase()).join('", "')}")'
        : 'เติมแท็กแท็กหลักของแต่ละเมนูให้มีคีย์เวิร์ดของสัญชาตินั้น ๆ (เช่น "thai", "japanese", "mexican")';

    final hasNutritionTargets =
        minCalories != null ||
        maxCalories != null ||
        minProtein != null ||
        maxCarbs != null ||
        maxFat != null;
    final dietRule = hasDietGoals
        ? 'ทุกเมนูต้องสอดคล้องกับข้อจำกัดไลฟ์สไตล์/อาหาร (${dietGoals.join(', ')}) และใส่แท็กที่สะท้อนข้อจำกัดเหล่านี้ เช่น "${dietGoals.map((d) => d.toLowerCase()).join('", "')}"'
        : 'หากเมนูใหม่ตรงกับแนวทางพิเศษ เช่น vegan หรือ low-carb ให้เพิ่มแท็กสอดคล้องกัน';
    final nutritionRule = hasNutritionTargets
        ? 'ปริมาณโภชนาการต้องอยู่ในช่วงที่กำหนด (แคลอรี่ ${minCalories != null ? '≥$minCalories' : ''}${minCalories != null && maxCalories != null ? ' และ ' : ''}${maxCalories != null ? '≤$maxCalories' : ''}, โปรตีน${minProtein != null ? ' ≥$minProtein g' : ''}${maxCarbs != null ? ', คาร์บ ≤$maxCarbs g' : ''}${maxFat != null ? ', ไขมัน ≤$maxFat g' : ''}) โดยระบุค่าที่คำนวณไว้ในผลลัพธ์'
        : 'ระบุโภชนาการหลัก (แคลอรี่ โปรตีน คาร์บ ไขมัน) ของแต่ละเมนูถ้ามีข้อมูลที่เชื่อถือได้';

    final prompt =
        '''
คุณคือเชฟอาหารไทยและนักโภชนาการมืออาชีพ ช่วยแนะนำ $desiredCount เมนูที่ทำได้จริงจากคลังวัตถุดิบด้านล่างนี้

วัตถุดิบหลักที่ควรใช้:
$ingredientLines

วัตถุดิบหมดอายุวันนี้: ${urgentTodayNames.isEmpty ? 'ไม่มี' : urgentTodayNames.join(', ')}${mustUseAllUrgent && urgentTodayNames.isNotEmpty ? ' (ต้องใช้ให้หมด)' : ''}
วัตถุดิบใกล้หมดอายุ: ${nearExpiry.isEmpty ? 'ไม่มี' : nearExpiry.join(', ')}
ข้อจำกัดภูมิแพ้: $allergyLine
ข้อจำกัดโภชนาการ: $nutritionLine
ลักษณะอาหารที่ต้องการ: $cuisineLine
เป้าหมายด้านไลฟ์สไตล์/อาหาร: $dietLine

กฎสำคัญ:
1. ใช้วัตถุดิบจากรายการผู้ใช้ให้มากที่สุด หลีกเลี่ยงของที่ไม่มี${mustUseAllUrgent && urgentTodayNames.isNotEmpty ? ' และต้องใช้วัตถุดิบที่หมดอายุวันนี้ทั้งหมดในชุดเมนูนี้' : ''}
2. อนุญาตเฉพาะของครัวพื้นฐาน (น้ำปลา น้ำตาล น้ำมัน พริก กระเทียม ซีอิ๊ว) หากจำเป็น
3. คำนวณ match_ratio = (จำนวนวัตถุดิบที่ผู้ใช้มี) / (จำนวนวัตถุดิบทั้งหมดของเมนู) และ match_score = match_ratio * 100
4. ให้เหตุผลว่าทำไมเมนูนี้เหมาะ พร้อมสรุปว่าขาดอะไรบ้าง (ถ้ามี)
5. อ้างอิงเว็บไซต์ที่น่าเชื่อถือจากรายการนี้เท่านั้น:
${_trustedReferenceSites.map((site) => "- ${site['name']} (${site['url']})").join('\n')}
6. $cuisineRule
7. $cuisineTagRule
8. source_url ต้องเป็นลิงก์หน้าเมนูนั้นโดยตรง (เช่น https://www.wongnai.com/recipes/ชื่อเมนู) ห้ามใช้หน้ารวม/หน้าหลัก/หน้าค้นหา
9. image_url ต้องเป็นลิงก์รูปภาพ (jpg/png/webp) ที่อยู่บนโดเมนเดียวกับ source_url หรือ CDN ทางการของเมนูนั้น หลีกเลี่ยงลิงก์ค้นหา/ stock photo
10. $dietRule
11. $nutritionRule
12. หลีกเลี่ยงเมนูของหวานหรือทอดมัน ๆ
13. ตอบกลับเป็น JSON เดียวที่มีคีย์ "recipes" เท่านั้น ไม่มีคำอธิบายอื่น

โครงสร้าง JSON ที่ต้องส่งกลับ:
{
  "recipes": [
    {
      "id": "unique_string",
      "name": "ชื่อเมนู",
      "description": "คำอธิบายสั้น ๆ",
      "reason": "เหตุผลว่าทำไมเมนูนี้เหมาะกับวัตถุดิบ",
      "category": "หมวดหมู่อาหาร",
      "tags": ["thai", "ai", ...],
      "match_score": 0-100,
      "match_ratio": 0-1,
      "ingredients": [
        {"name": "ชื่อวัตถุดิบ", "amount": 120, "unit": "กรัม"}
      ],
      "image_url": "https://ตัวอย่างโดเมนที่เชื่อถือได้/ชื่อภาพ.jpg",
      "missing_ingredients": [],
      "steps": [
        "เตรียม...", "ปรุง..."
      ],
      "cooking_time": 15,
      "prep_time": 10,
      "servings": 2,
      "source": "ชื่อเว็บไซต์จากรายการที่อนุญาต",
      "source_url": "ลิงก์หน้าเมนูบนเว็บไซต์นั้น"
    }
  ]
}
''';

    try {
      final response = await _aiService.generateTextSmart(prompt);
      final parsed = _parseAiRecipeResponse(response);
      final filtered = _filterAiRecipesByTrustedSources(
        parsed,
        hostToSource,
        limit: desiredCount,
      );
      if (filtered.isNotEmpty) {
        final enriched = _applyNutritionEstimates(filtered);
        final filteredByUser = _applyUserFilters(
          enriched,
          cuisineFilters: cuisineFilters,
          dietGoals: dietGoals,
          minCalories: minCalories,
          maxCalories: maxCalories,
          minProtein: minProtein,
          maxCarbs: maxCarbs,
          maxFat: maxFat,
        );
        return _ensureAiRecommendationCount(
          filteredByUser,
          selectedIngredients,
          cuisineFilters: cuisineFilters,
          dietGoals: dietGoals,
          minCalories: minCalories,
          maxCalories: maxCalories,
          minProtein: minProtein,
          maxCarbs: maxCarbs,
          maxFat: maxFat,
          targetCount: desiredCount,
        );
      }
    } catch (e, st) {
      print('⚠️ generateTextSmart error: $e');
      debugPrintStack(stackTrace: st);
    }

    return _fallbackAiRecommendations(
      selectedIngredients,
      cuisineFilters: cuisineFilters,
      dietGoals: dietGoals,
      minCalories: minCalories,
      maxCalories: maxCalories,
      minProtein: minProtein,
      maxCarbs: maxCarbs,
      maxFat: maxFat,
      urgentIngredientNames: urgentTodayNames,
      mustUseAllUrgent: mustUseAllUrgent,
      targetCount: desiredCount,
    );
  }

  List<RecipeModel> _filterAiRecipesByTrustedSources(
    List<RecipeModel> recipes,
    Map<String, String> hostToSource, {
    int? limit,
  }) {
    final filtered = <RecipeModel>[];
    for (final recipe in recipes) {
      final rawUrl = recipe.sourceUrl ?? '';
      if (rawUrl.isEmpty) continue;
      Uri? uri = Uri.tryParse(rawUrl);
      if (uri == null || uri.host.isEmpty) {
        uri = Uri.tryParse('https://$rawUrl');
      }
      if (uri == null || uri.host.isEmpty) continue;
      final normalizedHost = _normalizeHost(uri.host);
      MapEntry<String, String>? matched;
      for (final entry in hostToSource.entries) {
        final trustedHost = entry.key;
        if (normalizedHost == trustedHost ||
            normalizedHost.endsWith('.$trustedHost') ||
            trustedHost.endsWith('.$normalizedHost')) {
          matched = entry;
          break;
        }
      }
      if (matched == null) continue;

      final invalidPaths = {
        '',
        '/',
        '/recipes',
        '/recipes/',
        '/menu.php',
        '/menu.php/',
      };

      if (invalidPaths.contains(uri.path.toLowerCase())) {
        final knownUrl = _knownRecipeLinks[_normalizeName(recipe.name)];
        if (knownUrl == null) {
          continue;
        }
        uri = Uri.tryParse(knownUrl);
        if (uri == null || uri.host.isEmpty) continue;
      }

      final imageUrl = (recipe.imageUrl ?? '').trim();
      if (imageUrl.isEmpty) continue;
      Uri? imageUri = Uri.tryParse(imageUrl);
      if (imageUri == null || imageUri.host.isEmpty) {
        imageUri = Uri.tryParse('https://$imageUrl');
      }
      if (imageUri == null || imageUri.host.isEmpty) continue;
      final imageHost = _normalizeHost(imageUri.host);
      if (!_isTrustedImageHost(imageHost, matched.key)) continue;

      final tags = {...recipe.tags, 'ai', 'trusted'};
      filtered.add(
        recipe.copyWith(
          source: matched.value,
          sourceUrl: uri.toString(),
          imageUrl: imageUri.toString(),
          tags: tags.toList(),
        ),
      );
    }
    final cap = limit ?? _aiRecommendationTarget;
    return _dedupeRecipes(filtered).take(cap).toList();
  }

  List<RecipeModel> _ensureAiRecommendationCount(
    List<RecipeModel> current,
    List<IngredientModel> selectedIngredients, {
    List<String> cuisineFilters = const [],
    Set<String> dietGoals = const {},
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
    required int targetCount,
  }) {
    if (current.length >= targetCount) {
      return _applyNutritionEstimates(
        current.take(targetCount).toList(),
      );
    }
    final merged = [...current];
    final existing = merged.map((r) => _normalizeName(r.name)).toSet();
    for (final recipe in _fallbackAiRecommendations(
      selectedIngredients,
      cuisineFilters: cuisineFilters,
      dietGoals: dietGoals,
      minCalories: minCalories,
      maxCalories: maxCalories,
      minProtein: minProtein,
      maxCarbs: maxCarbs,
      maxFat: maxFat,
      targetCount: targetCount,
    )) {
      if (merged.length >= targetCount) break;
      final key = _normalizeName(recipe.name);
      if (existing.add(key)) {
        merged.add(recipe);
      }
    }

    if (merged.length < targetCount) {
      for (final recipe in _fallbackAiRecommendations(
        selectedIngredients,
        cuisineFilters: const [],
        dietGoals: dietGoals,
        minCalories: minCalories,
        maxCalories: maxCalories,
        minProtein: minProtein,
        maxCarbs: maxCarbs,
        maxFat: maxFat,
        preferThaiWhenUnfiltered: false,
        targetCount: targetCount,
      )) {
        if (merged.length >= targetCount) break;
        final key = _normalizeName(recipe.name);
        if (existing.add(key)) {
          merged.add(recipe);
        }
      }
    }
    return _applyNutritionEstimates(
      merged.take(targetCount).toList(),
    );
  }

  List<IngredientModel> _ensureUrgentIngredientCoverage(
    List<IngredientModel> current,
    List<IngredientModel> urgentToday,
  ) {
    if (urgentToday.isEmpty) return current;
    final normalized = <String>{};
    final enriched = <IngredientModel>[];
    for (final ingredient in current) {
      final key = _normalizeName(ingredient.name);
      if (key.isEmpty || normalized.contains(key)) continue;
      normalized.add(key);
      enriched.add(ingredient);
    }
    for (final urgent in urgentToday) {
      final key = _normalizeName(urgent.name);
      if (key.isEmpty || normalized.contains(key)) continue;
      normalized.add(key);
      enriched.add(urgent);
    }
    return enriched;
  }

  List<IngredientModel> _enforceSelectionCap(
    List<IngredientModel> items,
    List<IngredientModel> urgentToday,
    int maxCap,
  ) {
    if (items.length <= maxCap) return items;
    final urgentSet = urgentToday
        .map((e) => _normalizeName(e.name))
        .where((e) => e.isNotEmpty)
        .toSet();
    final result = <IngredientModel>[];
    final seen = <String>{};

    void addIfPossible(IngredientModel item) {
      if (result.length >= maxCap) return;
      final key = _normalizeName(item.name);
      if (key.isEmpty || seen.contains(key)) return;
      seen.add(key);
      result.add(item);
    }

    for (final item in items) {
      if (urgentSet.contains(_normalizeName(item.name))) {
        addIfPossible(item);
      }
    }
    for (final item in items) {
      if (result.length >= maxCap) break;
      addIfPossible(item);
    }
    return result;
  }

  bool _shouldFavorForPrioritySelection(IngredientModel ingredient) {
    if (ingredient.isUrgentExpiry || ingredient.isNearExpiry) return true;
    if (_isShelfStable(ingredient) && ingredient.daysToExpiry > 7) {
      return false;
    }
    return true;
  }

  bool _isShelfStable(IngredientModel ingredient) {
    final name = _normalizeName(ingredient.name);
    final category = _normalizeName(ingredient.category);
    final unit = _normalizeName(ingredient.unit);

    bool _containsAny(String target, Set<String> keywords) {
      if (target.isEmpty) return false;
      for (final keyword in keywords) {
        if (keyword.isEmpty) continue;
        if (target.contains(keyword)) return true;
      }
      return false;
    }

    if (ingredient.expiryDate == null) return true;
    if (ingredient.daysToExpiry > 90 && !ingredient.isUnderutilized) return true;
    if (_containsAny(category, _pantryCategoryKeywords)) return true;
    if (_containsAny(name, _pantryNameKeywords)) return true;
    if (_containsAny(unit, _pantryUnitKeywords)) return true;
    return false;
  }

  List<RecipeModel> _parseAiRecipeResponse(String? responseText) {
    if (responseText == null || responseText.trim().isEmpty) return [];
    try {
      final clean = responseText
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();
      final decoded = jsonDecode(clean);
      final recipesJson = decoded is Map<String, dynamic>
          ? decoded['recipes']
          : decoded;
      if (recipesJson is! List) return [];
      final list = <RecipeModel>[];
      for (final item in recipesJson) {
        if (item is! Map<String, dynamic>) continue;
        final tags = <String>{
          ...((item['tags'] as List?)?.map((e) => e.toString()) ?? const []),
          'ai',
        }.toList();
        final recipe = RecipeModel.fromAI({...item, 'tags': tags});
        list.add(recipe);
      }
      return list;
    } catch (e) {
      print('⚠️ Parse AI recipe response error: $e');
      return [];
    }
  }

  List<RecipeModel> _fallbackAiRecommendations(
    List<IngredientModel> selectedIngredients, {
    List<String> cuisineFilters = const [],
    Set<String> dietGoals = const {},
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
    bool preferThaiWhenUnfiltered = true,
    List<String> urgentIngredientNames = const [],
    bool mustUseAllUrgent = false,
    int targetCount = _aiRecommendationTarget,
  }) {
    final inventoryNames = selectedIngredients
        .map((ingredient) => ingredient.name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final urgentSet = urgentIngredientNames
        .map((name) => _normalizeName(name))
        .where((name) => name.isNotEmpty)
        .toSet();

    bool _hasIngredient(String requiredName) {
      if (inventoryNames.isEmpty) return false;
      for (final stock in inventoryNames) {
        if (ingredientsMatch(stock, requiredName) ||
            ingredientsMatch(requiredName, stock)) {
          return true;
        }
      }
      return false;
    }

    final normalizedCuisineFilters = cuisineFilters
        .map((value) => _normalizeName(value))
        .where((value) => value.isNotEmpty)
        .toSet();
    final normalizedDietGoals = dietGoals
        .map((value) => _normalizeName(value))
        .where((value) => value.isNotEmpty)
        .toSet();

    final candidates = <_FallbackCandidate>[];
    for (final data in _fallbackAiRecipeMaps) {
      final recipe = RecipeModel.fromAI(data);
      final uniqueKeys = <String>{};
      final matchedNames = <String>{};
      final missing = <String>[];
      var matched = 0;

      for (final ingredient in recipe.ingredients) {
        final name = ingredient.name.trim();
        if (name.isEmpty) continue;
        final normalized = _normalizeName(name);
        if (!uniqueKeys.add(normalized)) continue;
        if (_hasIngredient(name)) {
          matched++;
          matchedNames.add(normalized);
        } else {
          missing.add(name);
        }
      }

      final total = uniqueKeys.length;
      final ratio = total == 0 ? 0.0 : matched / total;
      final score = (ratio * 100).round().clamp(0, 100);
      final cuisine = _primaryCuisineTag(recipe.tags);

      final unmatchedUrgent =
          urgentSet.where((u) => !matchedNames.contains(u)).toList();
      if (mustUseAllUrgent && urgentSet.isNotEmpty && unmatchedUrgent.isNotEmpty) {
        continue;
      }

      final enrichedRecipe = recipe.copyWith(
        matchRatio: ratio,
        matchScore: score,
        missingIngredients: missing,
      );

      if (!_matchesCuisineFilters(enrichedRecipe, normalizedCuisineFilters)) {
        continue;
      }
      if (!_matchesDietGoals(enrichedRecipe, normalizedDietGoals)) {
        continue;
      }
      if (!_matchesNutritionTargets(
        enrichedRecipe,
        minCalories: minCalories,
        maxCalories: maxCalories,
        minProtein: minProtein,
        maxCarbs: maxCarbs,
        maxFat: maxFat,
      )) {
        continue;
      }

      candidates.add(
        _FallbackCandidate(
          recipe: enrichedRecipe,
          cuisine: cuisine,
          ratio: ratio,
          matchedCount: matched,
          totalCount: total,
        ),
      );
    }

    if (mustUseAllUrgent &&
        urgentSet.isNotEmpty &&
        candidates.isEmpty) {
      return _fallbackAiRecommendations(
        selectedIngredients,
        cuisineFilters: cuisineFilters,
        dietGoals: dietGoals,
        minCalories: minCalories,
        maxCalories: maxCalories,
        minProtein: minProtein,
        maxCarbs: maxCarbs,
        maxFat: maxFat,
        preferThaiWhenUnfiltered: preferThaiWhenUnfiltered,
        urgentIngredientNames: urgentIngredientNames,
        mustUseAllUrgent: false,
        targetCount: targetCount,
      );
    }

    candidates.sort((a, b) {
      final ratioCompare = b.ratio.compareTo(a.ratio);
      if (ratioCompare != 0) return ratioCompare;
      final matchedCompare = b.matchedCount.compareTo(a.matchedCount);
      if (matchedCompare != 0) return matchedCompare;
      final totalCompare = a.totalCount.compareTo(b.totalCount);
      if (totalCompare != 0) return totalCompare;
      return a.recipe.name.toLowerCase().compareTo(b.recipe.name.toLowerCase());
    });

    final selected = <RecipeModel>[];
    final selectedKeys = <String>{};
    final usedCuisines = <String>{};
    final requireThaiEmphasis = preferThaiWhenUnfiltered &&
        (normalizedCuisineFilters.isEmpty ||
            normalizedCuisineFilters.contains('thai'));

    int thaiCount() =>
        selected.where((recipe) => _primaryCuisineTag(recipe.tags) == 'thai').length;

    if (requireThaiEmphasis) {
      for (final candidate in candidates.where((c) => c.cuisine == 'thai')) {
        if (selected.length >= targetCount) break;
        if (thaiCount() >= 2) break;
        final key = _normalizeName(candidate.recipe.name);
        if (selectedKeys.add(key)) {
          selected.add(candidate.recipe);
          usedCuisines.add('thai');
        }
      }
    }

    // Pass 1: เก็บเมนูที่ให้สัญชาติไม่ซ้ำจนได้อย่างน้อย 3 ประเทศ
    for (final candidate in candidates) {
      if (selected.length >= targetCount) break;
      if (usedCuisines.length >= 3) break;
      final cuisine = candidate.cuisine;
      if (cuisine == null || usedCuisines.contains(cuisine)) continue;
      final key = _normalizeName(candidate.recipe.name);
      if (selectedKeys.add(key)) {
        selected.add(candidate.recipe);
        usedCuisines.add(cuisine);
      }
    }

    // Pass 2: เติมเมนูให้ครบตามจำนวนเป้าหมาย โดยยังพยายามเพิ่มสัญชาติที่ยังขาด
    for (final candidate in candidates) {
      if (selected.length >= targetCount) break;
      final key = _normalizeName(candidate.recipe.name);
      if (selectedKeys.contains(key)) continue;
      final cuisine = candidate.cuisine;
      if (usedCuisines.length < 3 &&
          cuisine != null &&
          !usedCuisines.contains(cuisine)) {
        selected.add(candidate.recipe);
        selectedKeys.add(key);
        usedCuisines.add(cuisine);
        continue;
      }
      if (selected.length < targetCount) {
        selected.add(candidate.recipe);
        selectedKeys.add(key);
        if (cuisine != null) usedCuisines.add(cuisine);
      }
    }

    // Pass 3: หากยังไม่ครบจำนวนเป้าหมายให้เติมจากตัวเลือกที่เหลือ
    for (final candidate in candidates) {
      if (selected.length >= targetCount) break;
      final key = _normalizeName(candidate.recipe.name);
      if (selectedKeys.contains(key)) continue;
      selected.add(candidate.recipe);
      selectedKeys.add(key);
    }

    return _applyNutritionEstimates(
      selected.take(targetCount).toList(),
    );
  }

  List<RecipeModel> _dedupeRecipes(List<RecipeModel> recipes) {
    final seen = <String>{};
    final output = <RecipeModel>[];
    for (final recipe in recipes) {
      final key = _normalizeName(recipe.name);
      if (key.isEmpty) continue;
      if (seen.add(key)) {
        output.add(recipe);
      }
    }
    return output;
  }

  List<RecipeModel> _applyNutritionEstimates(List<RecipeModel> recipes) {
    return recipes.map((recipe) {
      final info = recipe.nutrition;
      final hasData =
          info.calories > 0 ||
          info.protein > 0 ||
          info.carbs > 0 ||
          info.fat > 0 ||
          info.fiber > 0 ||
          info.sodium > 0;
      if (hasData) return recipe;

      final estimated = NutritionEstimator.estimateForRecipe(recipe);
      final hasEstimate =
          estimated.calories > 0 ||
          estimated.protein > 0 ||
          estimated.carbs > 0 ||
          estimated.fat > 0 ||
          estimated.fiber > 0 ||
          estimated.sodium > 0;
      if (!hasEstimate) return recipe;

      return recipe.copyWith(nutrition: estimated);
    }).toList();
  }

  List<RecipeModel> _applyUserFilters(
    List<RecipeModel> recipes, {
    required List<String> cuisineFilters,
    required Set<String> dietGoals,
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
  }) {
    if (recipes.isEmpty) return recipes;
    final normalizedCuisine = cuisineFilters
        .map((value) => _normalizeName(value))
        .where((value) => value.isNotEmpty)
        .toSet();
    final normalizedDietGoals = dietGoals
        .map((value) => _normalizeName(value))
        .where((value) => value.isNotEmpty)
        .toSet();

    final filtered = <RecipeModel>[];
    for (final recipe in recipes) {
      if (!_matchesCuisineFilters(recipe, normalizedCuisine)) continue;
      if (!_matchesDietGoals(recipe, normalizedDietGoals)) continue;
      if (!_matchesNutritionTargets(
        recipe,
        minCalories: minCalories,
        maxCalories: maxCalories,
        minProtein: minProtein,
        maxCarbs: maxCarbs,
        maxFat: maxFat,
      )) continue;
      filtered.add(recipe);
    }
    return filtered;
  }

  bool _matchesCuisineFilters(
    RecipeModel recipe,
    Set<String> cuisineFilters,
  ) {
    if (cuisineFilters.isEmpty) return true;
    final tags = recipe.tags
        .map((tag) => _normalizeName(tag))
        .where((tag) => tag.isNotEmpty)
        .toSet();
    if (tags.any(cuisineFilters.contains)) return true;
    final primary = _primaryCuisineTag(recipe.tags);
    if (primary != null && cuisineFilters.contains(primary)) return true;
    final category = _normalizeName(recipe.category);
    if (category.isNotEmpty && cuisineFilters.contains(category)) return true;
    return false;
  }

  bool _matchesDietGoals(
    RecipeModel recipe,
    Set<String> dietGoals,
  ) {
    if (dietGoals.isEmpty) return true;
    final tags = recipe.tags
        .map((tag) => _normalizeName(tag))
        .where((tag) => tag.isNotEmpty)
        .toSet();
    final tagBasedGoals =
        dietGoals.where((goal) => !_macroDietGoals.contains(goal)).toSet();
    for (final goal in tagBasedGoals) {
      final synonyms = _dietTagSynonyms[goal] ?? {goal};
      if (!synonyms.any(tags.contains)) {
        return false;
      }
    }
    return true;
  }

  bool _matchesNutritionTargets(
    RecipeModel recipe, {
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
  }) {
    double? _positiveOrNull(double value) => value > 0 ? value : null;
    final info = recipe.nutrition;
    final calories = _positiveOrNull(info.calories);
    final protein = _positiveOrNull(info.protein);
    final carbs = _positiveOrNull(info.carbs);
    final fat = _positiveOrNull(info.fat);

    if (minCalories != null) {
      if (calories == null || calories < minCalories) return false;
    }
    if (maxCalories != null && calories != null && calories > maxCalories) {
      return false;
    }
    if (minProtein != null) {
      if (protein == null || protein < minProtein) return false;
    }
    if (maxCarbs != null && carbs != null && carbs > maxCarbs) {
      return false;
    }
    if (maxFat != null && fat != null && fat > maxFat) {
      return false;
    }
    return true;
  }

  bool _isAiGenerationEnabled() {
    final flag = (dotenv.env['AI_GEMINI_ENABLED'] ?? 'true')
        .trim()
        .toLowerCase();
    return !(flag == 'false' || flag == '0' || flag == 'off' || flag == 'no');
  }

  List<RecipeModel> _prioritizeRecipesBySelectedCoverage(
    List<RecipeModel> recipes,
    List<IngredientModel> selectedIngredients,
  ) {
    if (recipes.isEmpty || selectedIngredients.isEmpty) {
      return recipes;
    }

    final profiles = _buildSelectedProfiles(selectedIngredients);
    if (profiles.isEmpty) return recipes;

    final scored = <_CoverageScoredRecipe>[];
    for (final recipe in recipes) {
      final info = _calculateCoverage(recipe, profiles);
      final coveragePercent = (info.coverageRatio * 100).round();

      var adjustedScore = coveragePercent;
      if (adjustedScore < recipe.matchScore) {
        adjustedScore = recipe.matchScore;
      }
      adjustedScore -= info.missingCount * 5;
      adjustedScore = adjustedScore.clamp(0, 100);
      final boundedScore = adjustedScore.toInt();

      final updatedRecipe = recipe.copyWith(
        matchScore: boundedScore,
        matchRatio: (boundedScore / 100).clamp(0.0, 1.0),
        reason: _mergeCoverageReason(recipe.reason, info),
      );

      scored.add(
        _CoverageScoredRecipe(
          recipe: updatedRecipe,
          matchedCount: info.matchedCount,
          missingCount: info.missingCount,
          coveragePercent: coveragePercent,
        ),
      );
    }

    scored.sort((a, b) {
      final missingCompare = a.missingCount.compareTo(b.missingCount);
      if (missingCompare != 0) return missingCompare;
      final matchedCompare = b.matchedCount.compareTo(a.matchedCount);
      if (matchedCompare != 0) return matchedCompare;
      final percentCompare = b.coveragePercent.compareTo(a.coveragePercent);
      if (percentCompare != 0) return percentCompare;
      return b.recipe.matchScore.compareTo(a.recipe.matchScore);
    });

    return scored.map((entry) => entry.recipe).toList();
  }

  List<_SelectedIngredientProfile> _buildSelectedProfiles(
    List<IngredientModel> selectedIngredients,
  ) {
    final profiles = <_SelectedIngredientProfile>[];
    final seen = <String>{};
    for (final ingredient in selectedIngredients) {
      final original = ingredient.name.trim();
      if (original.isEmpty) continue;
      final normalized = _normalizeName(original);
      if (normalized.isEmpty || !seen.add(normalized)) continue;

      final variants = _expandVariants(normalized);
      final translated = _normalizeName(
        IngredientTranslator.translate(original),
      );
      if (translated.isNotEmpty) {
        variants.addAll(_expandVariants(translated));
      }

      profiles.add(
        _SelectedIngredientProfile(originalName: original, variants: variants),
      );
    }
    return profiles;
  }

  _CoverageInfo _calculateCoverage(
    RecipeModel recipe,
    List<_SelectedIngredientProfile> profiles,
  ) {
    final matched = <String>[];
    final missing = <String>[];

    for (final profile in profiles) {
      final hasMatch = recipe.ingredients.any(
        (ingredient) => _matchesProfile(ingredient.name, profile),
      );
      if (hasMatch) {
        matched.add(profile.originalName);
      } else {
        missing.add(profile.originalName);
      }
    }

    return _CoverageInfo(
      totalSelected: profiles.length,
      matchedNames: matched,
      missingNames: missing,
    );
  }

  bool _matchesProfile(
    String recipeIngredientName,
    _SelectedIngredientProfile profile,
  ) {
    final variants = _expandVariants(_normalizeName(recipeIngredientName));
    final translated = _normalizeName(
      IngredientTranslator.translate(recipeIngredientName),
    );
    if (translated.isNotEmpty) {
      variants.addAll(_expandVariants(translated));
    }

    for (final recipeVariant in variants) {
      for (final profileVariant in profile.variants) {
        if (_namesRoughlyMatch(recipeVariant, profileVariant)) {
          return true;
        }
      }
    }

    return false;
  }

  bool _namesRoughlyMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    if (a.contains(b) || b.contains(a)) return true;
    if (ingredientsMatch(a, b)) return true;
    if (ingredientsMatch(b, a)) return true;
    return false;
  }

  Set<String> _expandVariants(String value) {
    final base = value.trim();
    if (base.isEmpty) return <String>{};

    final variants = <String>{base};
    final spaceNormalized = base.replaceAll(RegExp(r'[_-]+'), ' ');
    final collapsed = spaceNormalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    final noSpace = collapsed.replaceAll(' ', '');

    variants.add(spaceNormalized.trim());
    variants.add(collapsed);
    if (noSpace.isNotEmpty) {
      variants.add(noSpace);
    }

    variants.add(_stripPlural(base));
    variants.add(_stripPlural(collapsed));
    if (noSpace.isNotEmpty) {
      variants.add(_stripPlural(noSpace));
    }

    variants.removeWhere((element) => element.trim().isEmpty);
    return variants;
  }

  String _stripPlural(String value) {
    if (value.endsWith('ies') && value.length > 3) {
      return value.substring(0, value.length - 3) + 'y';
    }
    if (value.endsWith('es') && value.length > 2) {
      return value.substring(0, value.length - 2);
    }
    if (value.endsWith('s') && value.length > 1) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }

  String _mergeCoverageReason(String originalReason, _CoverageInfo info) {
    if (info.totalSelected <= 0) return originalReason;

    final buffer = StringBuffer()
      ..write('ใช้วัตถุดิบที่เลือก ${info.matchedCount}/${info.totalSelected}');

    if (info.missingCount == 0) {
      buffer.write(' • ครบทุกอย่างที่เลือก');
    } else {
      if (info.matchedNames.isNotEmpty) {
        buffer.write(' • ใช้ ${_summarizeNames(info.matchedNames)}');
      }
      if (info.missingNames.isNotEmpty) {
        buffer.write(' • ยังขาด ${_summarizeNames(info.missingNames)}');
      }
    }

    final trimmed = originalReason.trim();
    if (trimmed.isNotEmpty &&
        !trimmed.toLowerCase().contains('ใช้วัตถุดิบที่เลือก')) {
      buffer.write(' | $trimmed');
    }

    return buffer.toString();
  }

  String _summarizeNames(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length <= 3) {
      return names.join(', ');
    }
    final head = names.take(3).join(', ');
    final remaining = names.length - 3;
    return '$head +$remaining รายการ';
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
    if (!_aiService.canUseSdk) {
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

  static const List<Map<String, String>> _trustedReferenceSites = [
    {'name': 'Wongnai', 'url': 'https://www.wongnai.com/recipes'},
    {'name': 'Maeban', 'url': 'https://www.maeban.co.th/menu.php'},
    {'name': 'Cookpad Thailand', 'url': 'https://cookpad.com/th'},
    {'name': 'Krua.co', 'url': 'https://krua.co/recipes/'},
    {
      'name': 'Phol Food Mafia',
      'url': 'https://www.pholfoodmafia.com/recipes/',
    },
    {
      'name': 'China Sichuan Food',
      'url': 'https://www.chinasichuanfood.com/',
    },
    {
      'name': 'Just One Cookbook',
      'url': 'https://www.justonecookbook.com/',
    },
    {
      'name': 'Korean Bapsang',
      'url': 'https://www.koreanbapsang.com/',
    },
    {
      'name': 'Vicky Pham',
      'url': 'https://www.vickypham.com/',
    },
    {
      'name': 'Swasthi\'s Recipes',
      'url': 'https://www.indianhealthyrecipes.com/',
    },
    {
      'name': 'Serious Eats',
      'url': 'https://www.seriouseats.com/',
    },
    {
      'name': 'BBC Good Food',
      'url': 'https://www.bbcgoodfood.com/recipes',
    },
    {
      'name': 'Saveur',
      'url': 'https://www.saveur.com/recipes/',
    },
    {
      'name': 'The Daring Gourmet',
      'url': 'https://www.daringgourmet.com/',
    },
    {
      'name': 'Giallo Zafferano',
      'url': 'https://www.giallozafferano.com/recipes/',
    },
    {
      'name': 'Mexico in My Kitchen',
      'url': 'https://www.mexicoinmykitchen.com/',
    },
    {
      'name': 'Spanish Sabores',
      'url': 'https://spanishsabores.com/',
    },
  ];

  static const Map<String, Set<String>> _trustedImageHosts = {
    'wongnai.com': {'wongnai.com', 'img.wongnai.com', 'static.wongnai.com'},
    'maeban.co.th': {'maeban.co.th'},
    'cookpad.com': {'cookpad.com', 'img.cookpad.com'},
    'krua.co': {'krua.co'},
    'pholfoodmafia.com': {'pholfoodmafia.com'},
    'chinasichuanfood.com': {'chinasichuanfood.com'},
    'justonecookbook.com': {'justonecookbook.com', 'cdn.justonecookbook.com'},
    'koreanbapsang.com': {'koreanbapsang.com'},
    'vickypham.com': {'vickypham.com'},
    'indianhealthyrecipes.com': {'indianhealthyrecipes.com'},
    'seriouseats.com': {'seriouseats.com', 'images.ctfassets.net'},
    'bbcgoodfood.com': {'bbcgoodfood.com', 'images.immediate.co.uk'},
    'saveur.com': {'saveur.com', 'www.saveur.com'},
    'daringgourmet.com': {'daringgourmet.com'},
    'giallozafferano.com': {'giallozafferano.com'},
    'mexicoinmykitchen.com': {'mexicoinmykitchen.com'},
    'spanishsabores.com': {'spanishsabores.com'},
  };

  static const Set<String> _pantryCategoryKeywords = {
    'เครื่องปรุง',
    'ปรุงรส',
    'ซอส',
    'sauce',
    'seasoning',
    'condiment',
    'น้ำมัน',
    'น้ำตาล',
    'เกลือ',
    'ผง',
    'แป้ง',
    'เครื่องเทศ',
    'spice',
    'flour',
    'sugar',
    'salt',
    'oil',
    'vinegar',
    'dressing',
  };

  static const Set<String> _pantryNameKeywords = {
    'น้ำตาล',
    'น้ำปลา',
    'น้ำมัน',
    'เกลือ',
    'ผงชูรส',
    'ซีอิ๊ว',
    'ซอส',
    'พริกแกง',
    'กะปิ',
    'ออริกาโน',
    'oregano',
    'sugar',
    'salt',
    'oil',
    'sauce',
    'seasoning',
    'fish sauce',
    'soy sauce',
    'vinegar',
    'flour',
    'starch',
    'cornstarch',
  };

  static const Set<String> _pantryUnitKeywords = {
    'ช้อนชา',
    'ช้อนโต๊ะ',
    'ช้อนหวาน',
    'ช้อนกินข้าว',
    'tsp',
    'tbsp',
    'teaspoon',
    'tablespoon',
  };

  static const Set<String> _supportedCuisineTags = {
    'thai',
    'chinese',
    'japanese',
    'korean',
    'vietnamese',
    'indian',
    'american',
    'british',
    'french',
    'german',
    'italian',
    'mexican',
    'spanish',
  };

  String? _primaryCuisineTag(List<String> tags) {
    for (final tag in tags) {
      final normalized = _normalizeName(tag);
      if (_supportedCuisineTags.contains(normalized)) {
        return normalized;
      }
    }
    return null;
  }

  static const Map<String, Set<String>> _dietTagSynonyms = {
    'vegan': {'vegan', 'plant-based'},
    'vegetarian': {'vegetarian', 'ovo-vegetarian', 'lacto-vegetarian', 'plant-based'},
    'lacto-vegetarian': {'lacto-vegetarian', 'vegetarian'},
    'ovo-vegetarian': {'ovo-vegetarian', 'vegetarian'},
    'pescatarian': {'pescatarian'},
    'gluten-free': {'gluten-free', 'glutenfree'},
    'dairy-free': {'dairy-free', 'dairyfree', 'non-dairy', 'lactose-free'},
    'paleo': {'paleo'},
    'ketogenic': {'ketogenic', 'keto'},
  };

  static const Set<String> _macroDietGoals = {
    'high-protein',
    'low-carb',
    'low-fat',
    'ketogenic',
  };

  static const List<Map<String, dynamic>> _fallbackAiRecipeMaps = [
    {
      'id': 'ai_thai_pad_kra_prao',
      'name': 'ผัดกะเพราไก่ไข่ดาว',
      'description': 'ผัดกะเพรารสจัดจ้าน เสิร์ฟพร้อมไข่ดาวกรอบและข้าวสวยร้อน',
      'reason':
          'วัตถุดิบหลักเป็นไก่ กระเทียม พริก และไข่ ที่พบในครัวทั่วไป เหมาะกับมื้อเร่งด่วนแบบไทยแท้',
      'category': 'Stir-fry',
      'tags': ['thai', 'ai', 'stir-fry'],
      'match_score': 92,
      'match_ratio': 0.92,
      'ingredients': [
        {'name': 'อกไก่สับ', 'amount': 250, 'unit': 'กรัม'},
        {'name': 'ใบกะเพรา', 'amount': 40, 'unit': 'กรัม'},
        {'name': 'กระเทียมสับ', 'amount': 3, 'unit': 'กลีบ'},
        {'name': 'พริกจินดาแดงสับ', 'amount': 4, 'unit': 'เม็ด'},
        {'name': 'น้ำปลา', 'amount': 1.5, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'ซีอิ๊วขาว', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำตาลทราย', 'amount': 0.5, 'unit': 'ช้อนชา'},
        {'name': 'น้ำมันพืช', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'ไข่ไก่', 'amount': 2, 'unit': 'ฟอง'},
      ],
      'steps': [
        'โขลกหรือสับกระเทียมและพริกให้พอหยาบ ตั้งกระทะใส่น้ำมัน เจียวให้หอม',
        'ใส่อกไก่สับลงผัดจนสุก ปรุงรสด้วยน้ำปลา ซีอิ๊วขาว และน้ำตาลทราย',
        'ปิดไฟแล้วใส่ใบกะเพราผัดคลุกให้เข้ากัน',
        'ทอดไข่ดาวจนขอบกรอบ เสิร์ฟพร้อมข้าวสวย',
      ],
      'cooking_time': 15,
      'prep_time': 10,
      'servings': 2,
      'source': 'Wongnai',
      'source_url':
          'https://www.wongnai.com/recipes/stir-fried-minced-chicken-with-holy-basil-and-fried-egg',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_thai_tom_yum',
      'name': 'ต้มยำกุ้งน้ำใส',
      'description': 'ซุปต้มยำกุ้งรสจัดกลมกล่อม หอมสมุนไพรไทยสด',
      'reason':
          'ใช้กุ้ง สมุนไพร และเครื่องปรุงที่มีในครัวไทย ช่วยใช้ของสดที่ใกล้หมดอายุ',
      'category': 'Soup',
      'tags': ['thai', 'ai', 'soup'],
      'match_score': 90,
      'match_ratio': 0.9,
      'ingredients': [
        {'name': 'กุ้งแม่น้ำแกะเปลือก', 'amount': 300, 'unit': 'กรัม'},
        {'name': 'ตะไคร้หั่นท่อน', 'amount': 2, 'unit': 'ต้น'},
        {'name': 'ใบมะกรูดฉีก', 'amount': 5, 'unit': 'ใบ'},
        {'name': 'ข่าหั่นแว่น', 'amount': 4, 'unit': 'แว่น'},
        {'name': 'เห็ดฟางผ่าครึ่ง', 'amount': 120, 'unit': 'กรัม'},
        {'name': 'น้ำปลา', 'amount': 3, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำมะนาว', 'amount': 3, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'พริกขี้หนูสวนบุบ', 'amount': 8, 'unit': 'เม็ด'},
        {'name': 'น้ำซุปไก่', 'amount': 800, 'unit': 'มิลลิลิตร'},
        {'name': 'ผักชีฝรั่งซอย', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
      ],
      'steps': [
        'ตั้งหม้อน้ำซุปให้เดือด ใส่ตะไคร้ ข่า และใบมะกรูดเคี่ยวให้น้ำหอม',
        'เติมเห็ดฟางลงต้มจนสุก จากนั้นใส่กุ้งให้พอสุกเด้ง',
        'ปรุงรสด้วยน้ำปลา น้ำมะนาว และพริกขี้หนูบุบ ชิมให้รสกลมกล่อม',
        'ปิดไฟโรยผักชีฝรั่งซอย เสิร์ฟร้อน ๆ',
      ],
      'cooking_time': 20,
      'prep_time': 10,
      'servings': 3,
      'source': 'Krua.co',
      'source_url': 'https://krua.co/recipe/tom-yam-goong-clear-soup/',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_thai_green_curry',
      'name': 'แกงเขียวหวานไก่',
      'description': 'แกงเขียวหวานรสเข้มข้น หอมกะทิและใบโหระพา',
      'reason':
          'เหมาะกับการใช้ไก่ กะทิ และเครื่องแกงที่มีติดครัว พร้อมเสิร์ฟคู่ข้าวสวย',
      'category': 'Curry',
      'tags': ['thai', 'ai', 'curry'],
      'match_score': 88,
      'match_ratio': 0.88,
      'ingredients': [
        {'name': 'สะโพกไก่หั่นชิ้น', 'amount': 400, 'unit': 'กรัม'},
        {'name': 'หัวกะทิ', 'amount': 200, 'unit': 'มิลลิลิตร'},
        {'name': 'หางกะทิ', 'amount': 300, 'unit': 'มิลลิลิตร'},
        {'name': 'พริกแกงเขียวหวาน', 'amount': 50, 'unit': 'กรัม'},
        {'name': 'มะเขือเปราะผ่าครึ่ง', 'amount': 120, 'unit': 'กรัม'},
        {'name': 'ลูกชิ้นปลาเส้น', 'amount': 100, 'unit': 'กรัม'},
        {'name': 'ใบโหระพา', 'amount': 30, 'unit': 'กรัม'},
        {'name': 'น้ำปลา', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำตาลปี๊บ', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'พริกชี้ฟ้าหั่นเฉียง', 'amount': 2, 'unit': 'เม็ด'},
      ],
      'steps': [
        'เคี่ยวหัวกะทิกับพริกแกงเขียวหวานให้แตกมัน',
        'ใส่เนื้อไก่ลงผัดให้สุกแล้วเติมหางกะทิ',
        'ใส่มะเขือเปราะและลูกชิ้นปลา เคี่ยวจนผักนุ่ม',
        'ปรุงรสด้วยน้ำปลา น้ำตาลปี๊บ ใส่ใบโหระพาและพริกชี้ฟ้าก่อนปิดไฟ',
      ],
      'cooking_time': 25,
      'prep_time': 15,
      'servings': 4,
      'source': 'Maeban',
      'source_url': 'https://www.maeban.co.th/menu_detail.php?bl=1&id=563',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_thai_pad_se-ew',
      'name': 'ผัดซีอิ๊วเส้นใหญ่หมู',
      'description': 'เส้นใหญ่ผัดไฟแรงกับหมูและคะน้า กลิ่นกระทะหอม ๆ',
      'reason':
          'ใช้เส้นใหญ่ ไข่ และผักคะน้าที่เหลือในตู้เย็น ทำง่ายได้พลังงานครบถ้วน',
      'category': 'Noodle',
      'tags': ['thai', 'ai', 'stir-fry'],
      'match_score': 87,
      'match_ratio': 0.87,
      'ingredients': [
        {'name': 'เส้นใหญ่', 'amount': 400, 'unit': 'กรัม'},
        {'name': 'หมูหมักหั่นชิ้น', 'amount': 250, 'unit': 'กรัม'},
        {'name': 'ไข่ไก่', 'amount': 2, 'unit': 'ฟอง'},
        {'name': 'คะน้าซอย', 'amount': 150, 'unit': 'กรัม'},
        {'name': 'ซีอิ๊วดำหวาน', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'ซีอิ๊วขาว', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำตาลทราย', 'amount': 1, 'unit': 'ช้อนชา'},
        {'name': 'น้ำมันพืช', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'กระเทียมสับ', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'พริกไทยป่น', 'amount': 0.5, 'unit': 'ช้อนชา'},
      ],
      'steps': [
        'ตั้งกระทะไฟแรงใส่น้ำมัน เจียวกระเทียมหอมแล้วใส่หมูผัดจนสุก',
        'ตอกไข่ลงไปยีให้กระจาย ใส่เส้นใหญ่และคะน้าลงผัด',
        'ปรุงรสด้วยซีอิ๊วขาว ซีอิ๊วดำ น้ำตาล พริกไทย คลุกให้เข้ากัน',
        'ผัดจนเส้นหอมกลิ่นกระทะ เสิร์ฟร้อน ๆ',
      ],
      'cooking_time': 15,
      'prep_time': 10,
      'servings': 2,
      'source': 'Wongnai',
      'source_url':
          'https://www.wongnai.com/recipes/stir-fried-flat-noodles-with-pork',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_thai_pa_lo',
      'name': 'ไข่พะโล้หมูสามชั้น',
      'description': 'พะโล้รสหวานเค็มหอมเครื่องเทศ กินคู่ข้าวสวยร้อน',
      'reason':
          'ช่วยเคลียร์ไข่และหมูสามชั้นในสต็อก พร้อมเก็บทานได้หลายมื้อ',
      'category': 'Stew',
      'tags': ['thai', 'ai', 'stew'],
      'match_score': 85,
      'match_ratio': 0.85,
      'ingredients': [
        {'name': 'หมูสามชั้นหั่นชิ้น', 'amount': 400, 'unit': 'กรัม'},
        {'name': 'ไข่ไก่ต้มสุก', 'amount': 4, 'unit': 'ฟอง'},
        {'name': 'น้ำตาลปี๊บ', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำปลา', 'amount': 3, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'ซอสซีอิ๊วดำ', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'อบเชย', 'amount': 1, 'unit': 'ท่อน'},
        {'name': 'โป๊ยกั๊ก', 'amount': 2, 'unit': 'ดอก'},
        {'name': 'กระเทียมไทยทุบ', 'amount': 8, 'unit': 'กลีบ'},
        {'name': 'น้ำซุปหมู', 'amount': 800, 'unit': 'มิลลิลิตร'},
        {'name': 'ผักชีรากทุบ', 'amount': 3, 'unit': 'ราก'},
      ],
      'steps': [
        'คาราเมลน้ำตาลปี๊บจนเป็นสีน้ำตาลเข้ม ใส่หมูสามชั้นผัดให้เคลือบ',
        'เติมน้ำซุป ปรุงรสด้วยน้ำปลา ซีอิ๊วดำ และใส่เครื่องเทศทั้งหมด',
        'เคี่ยวไฟอ่อนจนหมูนุ่ม จากนั้นใส่ไข่ต้มลงไปเคี่ยวต่ออีก 10 นาที',
        'ชิมรสหวานเค็มตามชอบ เสิร์ฟพร้อมข้าวสวย',
      ],
      'cooking_time': 60,
      'prep_time': 15,
      'servings': 4,
      'source': 'Phol Food Mafia',
      'source_url':
          'https://www.pholfoodmafia.com/recipe/five-spice-stewed-eggs-and-pork/',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_chinese_kung_pao',
      'name': 'Kung Pao Chicken',
      'description':
          'ไก่ผัดพริกถั่วลิสงสไตล์เสฉวน เผ็ดหวานเค็มหอมกลิ่นพริกแห้ง',
      'reason':
          'เลือกใช้ไก่ ถั่วลิสง และเครื่องปรุงที่คล้ายครัวไทย เพื่อเพิ่มสีสันแบบจีน',
      'category': 'Stir-fry',
      'tags': ['chinese', 'ai', 'stir-fry'],
      'match_score': 85,
      'match_ratio': 0.85,
      'ingredients': [
        {'name': 'อกไก่หั่นเต๋า', 'amount': 350, 'unit': 'กรัม'},
        {'name': 'พริกแห้งหั่นท่อน', 'amount': 6, 'unit': 'เม็ด'},
        {'name': 'ถั่วลิสงคั่ว', 'amount': 60, 'unit': 'กรัม'},
        {'name': 'กระเทียมสับ', 'amount': 3, 'unit': 'กลีบ'},
        {'name': 'ขิงสับ', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'ต้นหอม', 'amount': 2, 'unit': 'ต้น'},
        {'name': 'ซีอิ๊วขาว', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'ซีอิ๊วดำ', 'amount': 1, 'unit': 'ช้อนชา'},
        {'name': 'น้ำส้มสายชูดำ', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำตาลทราย', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
      ],
      'steps': [
        'หมักไก่กับซีอิ๊ว น้ำตาล และแป้งมันเล็กน้อยอย่างน้อย 15 นาที',
        'ผัดพริกแห้งกับน้ำมันจนหอม ใส่ไก่ผัดจนเกือบสุก',
        'เติมกระเทียม ขิง ถั่วลิสง และซอสทั้งหมด คลุกจนเข้ากัน',
        'ผัดใส่ต้นหอมเร็ว ๆ แล้วเสิร์ฟทันที',
      ],
      'cooking_time': 20,
      'prep_time': 15,
      'servings': 3,
      'source': 'China Sichuan Food',
      'source_url': 'https://www.chinasichuanfood.com/kung-pao-chicken/',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_japanese_teriyaki',
      'name': 'Chicken Teriyaki',
      'description': 'ไก่เทอริยากิซอสหวานเค็มกลมกล่อม เสิร์ฟแบบญี่ปุ่น',
      'reason': 'ใช้ไก่และซีอิ๊วที่หาได้ง่ายในไทย เสริมรสชาติญี่ปุ่นแท้',
      'category': 'Main',
      'tags': ['japanese', 'ai', 'glaze'],
      'match_score': 83,
      'match_ratio': 0.83,
      'ingredients': [
        {'name': 'สะโพกไก่ไม่มีกระดูก', 'amount': 400, 'unit': 'กรัม'},
        {'name': 'ซีอิ๊วญี่ปุ่น', 'amount': 3, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'มิริน', 'amount': 3, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำตาลทราย', 'amount': 1.5, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'เหล้าสาเก', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'ขิงขูด', 'amount': 1, 'unit': 'ช้อนชา'},
        {'name': 'กระเทียมขูด', 'amount': 1, 'unit': 'กลีบ'},
        {'name': 'น้ำมันงา', 'amount': 1, 'unit': 'ช้อนชา'},
      ],
      'steps': [
        'ผสมน้ำซอสเทอริยากิทั้งหมดให้เข้ากัน',
        'ย่างหรือทอดสะโพกไก่ด้านหนังให้กรอบแล้วกลับอีกด้าน',
        'เทซอสลงกระทะ เคี่ยวจนข้นและเคลือบไก่เป็นเงา',
        'หั่นเสิร์ฟคู่ข้าวญี่ปุ่นและผักลวก',
      ],
      'cooking_time': 18,
      'prep_time': 10,
      'servings': 2,
      'source': 'Just One Cookbook',
      'source_url': 'https://www.justonecookbook.com/chicken-teriyaki/',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_korean_bibimbap',
      'name': 'Bibimbap',
      'description': 'ข้าวยำเกาหลีรวมผักหลากชนิด ไข่ดาว และซอสโกชูจัง',
      'reason':
          'จัดครบทั้งผัก โปรตีน และธัญพืช เหมาะกับการใช้ของเหลือในตู้เย็น',
      'category': 'Rice Bowl',
      'tags': ['korean', 'ai', 'rice-bowl'],
      'match_score': 80,
      'match_ratio': 0.8,
      'ingredients': [
        {'name': 'ข้าวสวย', 'amount': 2, 'unit': 'ถ้วย'},
        {'name': 'เนื้อวัวสไลซ์', 'amount': 200, 'unit': 'กรัม'},
        {'name': 'ผักโขมลวก', 'amount': 120, 'unit': 'กรัม'},
        {'name': 'ถั่วงอกลวก', 'amount': 120, 'unit': 'กรัม'},
        {'name': 'แครอทซอย', 'amount': 80, 'unit': 'กรัม'},
        {'name': 'เห็ดหอมสไลซ์', 'amount': 80, 'unit': 'กรัม'},
        {'name': 'ไข่ไก่', 'amount': 2, 'unit': 'ฟอง'},
        {'name': 'โกชูจัง', 'amount': 3, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำมันงา', 'amount': 2, 'unit': 'ช้อนชา'},
        {'name': 'งาคั่ว', 'amount': 1, 'unit': 'ช้อนชา'},
      ],
      'steps': [
        'ผัดเนื้อกับซีอิ๊ว น้ำมันงา และน้ำตาลจนสุก หอม',
        'ปรุงรสผักแต่ละชนิดด้วยเกลือและน้ำมันงาเล็กน้อย',
        'จัดข้าวลงชาม วางผัก เนื้อ และไข่ดาวด้านบน',
        'เสิร์ฟพร้อมซอสโกชูจัง คลุกก่อนรับประทาน',
      ],
      'cooking_time': 25,
      'prep_time': 20,
      'servings': 2,
      'source': 'Korean Bapsang',
      'source_url': 'https://www.koreanbapsang.com/bibimbap/',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_vietnamese_beef_pho',
      'name': 'Vietnamese Beef Pho',
      'description':
          'เฝอเนื้อเวียดนาม ซุปใสกลิ่นอบเชย โป๊ยกั๊ก และสมุนไพรสด',
      'reason':
          'ใช้กระดูกและเนื้อวัวพร้อมสมุนไพรไทย สร้างรสซุปที่ลุ่มลึก',
      'category': 'Soup',
      'tags': ['vietnamese', 'ai', 'noodle'],
      'match_score': 78,
      'match_ratio': 0.78,
      'ingredients': [
        {'name': 'เส้นก๋วยเตี๋ยวแบน', 'amount': 200, 'unit': 'กรัม'},
        {'name': 'กระดูกวัว', 'amount': 700, 'unit': 'กรัม'},
        {'name': 'เนื้อวัวสไลซ์บาง', 'amount': 200, 'unit': 'กรัม'},
        {'name': 'หอมใหญ่', 'amount': 1, 'unit': 'หัว'},
        {'name': 'ขิงแก่', 'amount': 40, 'unit': 'กรัม'},
        {'name': 'โป๊ยกั๊ก', 'amount': 2, 'unit': 'ดอก'},
        {'name': 'อบเชย', 'amount': 1, 'unit': 'ท่อน'},
        {'name': 'น้ำปลา', 'amount': 3, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำตาลกรวด', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'ผักชีลาวและโหระพา', 'amount': 30, 'unit': 'กรัม'},
      ],
      'steps': [
        'คั่วหอมใหญ่และขิงให้หอม เคี่ยวกับกระดูกและเครื่องเทศ 1-2 ชั่วโมง',
        'ปรุงรสซุปด้วยน้ำปลาและน้ำตาลกรวด ชิมให้กลมกล่อม',
        'ลวกเส้นและเนื้อสไลซ์ จัดลงชามแล้วราดน้ำซุปเดือด',
        'เสิร์ฟพร้อมสมุนไพรสด มะนาว และพริก',
      ],
      'cooking_time': 120,
      'prep_time': 25,
      'servings': 4,
      'source': 'Vicky Pham',
      'source_url': 'https://www.vickypham.com/food/vietnamese-beef-pho',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_indian_tikka_masala',
      'name': 'Chicken Tikka Masala',
      'description':
          'แกงไก่ในซอสมะเขือเทศและเครื่องเทศหอมมัน เสิร์ฟกับข้าวบาสมาติ',
      'reason':
          'ใช้ไก่ โยเกิร์ต มะเขือเทศ และเครื่องเทศที่หาได้ในร้านเอเชียทั่วไป',
      'category': 'Curry',
      'tags': ['indian', 'ai', 'curry'],
      'match_score': 82,
      'match_ratio': 0.82,
      'ingredients': [
        {'name': 'อกไก่หั่นชิ้น', 'amount': 400, 'unit': 'กรัม'},
        {'name': 'โยเกิร์ตธรรมชาติ', 'amount': 120, 'unit': 'กรัม'},
        {'name': 'น้ำมะนาว', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'ผงขมิ้น', 'amount': 0.5, 'unit': 'ช้อนชา'},
        {'name': 'ผงปาปริกา', 'amount': 1, 'unit': 'ช้อนชา'},
        {'name': 'น้ำมันพืช', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'หอมหัวใหญ่สับ', 'amount': 1, 'unit': 'หัว'},
        {'name': 'กระเทียมสับ', 'amount': 4, 'unit': 'กลีบ'},
        {'name': 'ขิงสับ', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'ผงการ์รัมมาซาลา', 'amount': 1, 'unit': 'ช้อนชา'},
        {'name': 'มะเขือเทศบดกระป๋อง', 'amount': 240, 'unit': 'กรัม'},
        {'name': 'ครีมสด', 'amount': 80, 'unit': 'มิลลิลิตร'},
      ],
      'steps': [
        'หมักไก่ด้วยโยเกิร์ต น้ำมะนาว และเครื่องเทศอย่างน้อย 20 นาที',
        'ผัดหอม กระเทียม และขิงจนหอม ใส่มะเขือเทศบดและเครื่องเทศลงเคี่ยว',
        'ใส่ไก่หมักลงเคี่ยวจนสุก เติมครีมสด คนให้เข้ากันแล้วปรับรส',
        'เสิร์ฟพร้อมข้าวบาสมาติหรือแป้งนาน',
      ],
      'cooking_time': 30,
      'prep_time': 20,
      'servings': 4,
      'source': 'Swasthi\'s Recipes',
      'source_url':
          'https://www.indianhealthyrecipes.com/chicken-tikka-masala/',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_american_classic_burger',
      'name': 'Classic Smash Burger',
      'description':
          'เบอร์เกอร์เนื้อบดย่างแผ่นบาง หอมกรอบ เสิร์ฟกับชีสและซอสเรียบง่าย',
      'reason':
          'ใช้เนื้อบด ชีส และขนมปังที่หาได้ทั่วไป เพิ่มตัวเลือกอาหารอเมริกันทำง่าย',
      'category': 'Sandwich',
      'tags': ['american', 'ai', 'grill'],
      'match_score': 79,
      'match_ratio': 0.79,
      'ingredients': [
        {'name': 'เนื้อวัวบด', 'amount': 450, 'unit': 'กรัม'},
        {'name': 'เกลือ', 'amount': 1, 'unit': 'ช้อนชา'},
        {'name': 'พริกไทยดำบด', 'amount': 0.5, 'unit': 'ช้อนชา'},
        {'name': 'ขนมปังเบอร์เกอร์', 'amount': 4, 'unit': 'ชิ้น'},
        {'name': 'ชีสเชดดาร์แผ่น', 'amount': 4, 'unit': 'แผ่น'},
        {'name': 'หัวหอมใหญ่สไลซ์', 'amount': 1, 'unit': 'หัว'},
        {'name': 'เนยจืด', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'มายองเนส', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'ผักกาดหอม', 'amount': 4, 'unit': 'ใบ'},
        {'name': 'มะเขือเทศสไลซ์', 'amount': 1, 'unit': 'ผล'},
      ],
      'steps': [
        'ปั้นเนื้อวัวเป็นก้อนหลวม ๆ โรยเกลือและพริกไทยให้ทั่ว',
        'กดเนื้อบนกระทะร้อนให้แผ่นบาง ย่างจนกรอบ ใส่ชีสให้ละลาย',
        'ปิ้งขนมปังกับเนย ทามายองเนสแล้วประกอบกับผักและเนื้อ',
        'เสิร์ฟทันทีคู่กับมันฝรั่งทอดหรือสลัด',
      ],
      'cooking_time': 15,
      'prep_time': 15,
      'servings': 4,
      'source': 'Serious Eats',
      'source_url':
          'https://www.seriouseats.com/the-burger-lab-smashed-burger-recipe',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_british_fish_and_chips',
      'name': 'Beer-Battered Fish and Chips',
      'description':
          'ปลาชุบแป้งเบียร์ทอดกรอบ เสิร์ฟกับมันฝรั่งทอดและซอสทาร์ทาร์',
      'reason':
          'ใช้ปลาขาว มันฝรั่ง และของแห้งที่หาได้ง่าย สอดคล้องกับห้องครัวคนไทย',
      'category': 'Fried',
      'tags': ['british', 'ai', 'fried'],
      'match_score': 77,
      'match_ratio': 0.77,
      'ingredients': [
        {'name': 'เนื้อปลาค็อดหรือดอรี่', 'amount': 500, 'unit': 'กรัม'},
        {'name': 'แป้งสาลีอเนกประสงค์', 'amount': 160, 'unit': 'กรัม'},
        {'name': 'ผงฟู', 'amount': 1, 'unit': 'ช้อนชา'},
        {'name': 'เบียร์ลาเกอร์เย็น', 'amount': 250, 'unit': 'มิลลิลิตร'},
        {'name': 'มันฝรั่ง', 'amount': 3, 'unit': 'หัว'},
        {'name': 'น้ำมันพืช', 'amount': 1, 'unit': 'ลิตร'},
        {'name': 'เกลือทะเล', 'amount': 1, 'unit': 'ช้อนชา'},
        {'name': 'ซอสทาร์ทาร์', 'amount': 4, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'เลมอน', 'amount': 1, 'unit': 'ผล'},
      ],
      'steps': [
        'หั่นมันฝรั่งเป็นแท่ง ลวกน้ำเดือดแล้วพักให้แห้งก่อนทอด',
        'ผสมแป้ง ผงฟู และเบียร์ให้เป็นแป้งข้น',
        'คลุกปลากับแป้งแห้ง ชุบแป้งเบียร์แล้วทอดจนกรอบสีทอง',
        'ทอดมันฝรั่งจนกรอบ เสิร์ฟพร้อมปลา เลมอน และซอสทาร์ทาร์',
      ],
      'cooking_time': 35,
      'prep_time': 20,
      'servings': 3,
      'source': 'BBC Good Food',
      'source_url': 'https://www.bbcgoodfood.com/recipes/beer-battered-fish-chips',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_french_coq_au_vin',
      'name': 'Coq au Vin',
      'description':
          'สตูว์ไก่ตุ๋นไวน์แดงพร้อมเห็ด เบคอน และหัวหอมมุก กลิ่นหอมลุ่มลึก',
      'reason':
          'ใช้ไก่ทั้งชิ้น ผักราก และไวน์ที่หาได้ในซูเปอร์มาร์เก็ต สร้างความหลากหลายแบบฝรั่งเศส',
      'category': 'Stew',
      'tags': ['french', 'ai', 'stew'],
      'match_score': 76,
      'match_ratio': 0.76,
      'ingredients': [
        {'name': 'ไก่บ้านหั่นชิ้นใหญ่', 'amount': 1.2, 'unit': 'กิโลกรัม'},
        {'name': 'ไวน์แดงแห้ง', 'amount': 500, 'unit': 'มิลลิลิตร'},
        {'name': 'เบคอนหั่นชิ้น', 'amount': 120, 'unit': 'กรัม'},
        {'name': 'เห็ดแชมปิญอง', 'amount': 200, 'unit': 'กรัม'},
        {'name': 'หอมมุก', 'amount': 120, 'unit': 'กรัม'},
        {'name': 'แครอทหั่นท่อน', 'amount': 2, 'unit': 'หัว'},
        {'name': 'กระเทียม', 'amount': 4, 'unit': 'กลีบ'},
        {'name': 'น้ำซุปไก่', 'amount': 250, 'unit': 'มิลลิลิตร'},
        {'name': 'ใบกระวาน', 'amount': 2, 'unit': 'ใบ'},
        {'name': 'ไธม์สด', 'amount': 1, 'unit': 'ช้อนชา'},
      ],
      'steps': [
        'หมักไก่กับไวน์แดงและสมุนไพรอย่างน้อย 4 ชั่วโมง แล้วซับให้แห้ง',
        'ผัดเบคอนให้กรอบ ตักขึ้น ผัดไก่ให้เหลืองแล้วพัก',
        'ผัดผักลงในหม้อ เติมไวน์หมัก ไก่ และน้ำซุป เคี่ยวจนไก่นุ่ม',
        'ใส่เห็ดและเบคอนกลับลง เคี่ยวต่อจนซอสข้น เสิร์ฟกับมันบดหรือขนมปัง',
      ],
      'cooking_time': 90,
      'prep_time': 30,
      'servings': 4,
      'source': 'Saveur',
      'source_url': 'https://www.saveur.com/recipes/coq-au-vin/',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_german_sauerbraten',
      'name': 'Sauerbraten',
      'description':
          'สตูว์เนื้อวัวหมักน้ำส้มและสมุนไพรแบบเยอรมัน เสิร์ฟกับกะหล่ำดองและมันฝรั่ง',
      'reason':
          'ใช้เนื้อวัว สมุนไพรแห้ง และน้ำส้มสายชูที่หาได้ง่าย เหมาะกับมื้อพิเศษ',
      'category': 'Roast',
      'tags': ['german', 'ai', 'roast'],
      'match_score': 74,
      'match_ratio': 0.74,
      'ingredients': [
        {'name': 'เนื้อวัวส่วนสันคอ', 'amount': 1.5, 'unit': 'กิโลกรัม'},
        {'name': 'น้ำส้มสายชูหมัก', 'amount': 500, 'unit': 'มิลลิลิตร'},
        {'name': 'น้ำซุปเนื้อ', 'amount': 500, 'unit': 'มิลลิลิตร'},
        {'name': 'หัวหอมใหญ่', 'amount': 2, 'unit': 'หัว'},
        {'name': 'แครอท', 'amount': 2, 'unit': 'หัว'},
        {'name': 'เซเลอรี่', 'amount': 2, 'unit': 'ก้าน'},
        {'name': 'ใบกระวาน', 'amount': 3, 'unit': 'ใบ'},
        {'name': 'โป๊ยกั๊ก', 'amount': 2, 'unit': 'ดอก'},
        {'name': 'เมล็ดมัสตาร์ด', 'amount': 1, 'unit': 'ช้อนชา'},
        {'name': 'น้ำตาลทรายแดง', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
      ],
      'steps': [
        'หมักเนื้อกับน้ำส้ม สมุนไพร และผักอย่างน้อย 24 ชั่วโมง',
        'นำเนื้อออกมาซับให้แห้ง ย่างในหม้อให้ด้านนอกเป็นสีน้ำตาล',
        'เติมน้ำหมักที่กรองแล้วและน้ำซุป เคี่ยวไฟอ่อนจนเนื้อนุ่ม',
        'ปรุงรสซอสให้กลมกล่อม เสิร์ฟกับกะหล่ำดองหรือมันบด',
      ],
      'cooking_time': 150,
      'prep_time': 30,
      'servings': 6,
      'source': 'The Daring Gourmet',
      'source_url':
          'https://www.daringgourmet.com/traditional-german-sauerbraten/',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_italian_carbonara',
      'name': 'Spaghetti Carbonara',
      'description':
          'สปาเก็ตตี้ซอสครีมชีสจากไข่และพาร์มีซาน หอมกรุ่นแพนเชตตา',
      'reason':
          'ใช้เส้นพาสต้า ไข่ และชีสที่มีในซูเปอร์มาร์เก็ต ทำง่ายแต่รสชาติอิตาเลียนแท้',
      'category': 'Pasta',
      'tags': ['italian', 'ai', 'pasta'],
      'match_score': 81,
      'match_ratio': 0.81,
      'ingredients': [
        {'name': 'สปาเก็ตตี้', 'amount': 320, 'unit': 'กรัม'},
        {'name': 'แพนเชตตาหรือเบคอนรมควัน', 'amount': 150, 'unit': 'กรัม'},
        {'name': 'ไข่ไก่', 'amount': 3, 'unit': 'ฟอง'},
        {'name': 'ไข่แดงเพิ่มเติม', 'amount': 1, 'unit': 'ฟอง'},
        {'name': 'ชีสเพโกริโนขูด', 'amount': 50, 'unit': 'กรัม'},
        {'name': 'ชีสพาร์มีซานขูด', 'amount': 40, 'unit': 'กรัม'},
        {'name': 'พริกไทยดำบดใหม่', 'amount': 1, 'unit': 'ช้อนชา'},
        {'name': 'เกลือ', 'amount': 0.5, 'unit': 'ช้อนชา'},
      ],
      'steps': [
        'ต้มเส้นสปาเก็ตตี้จนเกือบสุก เก็บน้ำต้มเส้นไว้เล็กน้อย',
        'เจียวแพนเชตตาให้กรอบในกระทะใหญ่ ปิดไฟ',
        'ตีไข่กับชีสและพริกไทย เติมลงกระทะพร้อมเส้นและน้ำต้มเส้นเล็กน้อย',
        'คลุกเร็ว ๆ ให้ซอสเคลือบเส้นและข้น เสิร์ฟทันที',
      ],
      'cooking_time': 20,
      'prep_time': 10,
      'servings': 4,
      'source': 'Giallo Zafferano',
      'source_url':
          'https://www.giallozafferano.com/recipes/Spaghetti-Carbonara.html',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_mexican_tinga_tacos',
      'name': 'Chicken Tinga Tacos',
      'description':
          'ทาโก้ไก่ฉีกในซอสมะเขือเทศและชิพอทเล่ รสเผ็ดหอมควัน',
      'reason':
          'ใช้ไก่ต้มฉีก มะเขือเทศ และพริกกระป๋อง หาได้ง่ายสำหรับครัวเม็กซิกันสไตล์บ้าน',
      'category': 'Taco',
      'tags': ['mexican', 'ai', 'taco'],
      'match_score': 80,
      'match_ratio': 0.8,
      'ingredients': [
        {'name': 'อกไก่ต้มฉีก', 'amount': 400, 'unit': 'กรัม'},
        {'name': 'มะเขือเทศบด', 'amount': 240, 'unit': 'กรัม'},
        {'name': 'พริกชิพอทเล่ในซอสดอบลาดโด้', 'amount': 2, 'unit': 'เม็ด'},
        {'name': 'หอมหัวใหญ่สับ', 'amount': 1, 'unit': 'หัว'},
        {'name': 'กระเทียมสับ', 'amount': 3, 'unit': 'กลีบ'},
        {'name': 'น้ำซุปไก่', 'amount': 120, 'unit': 'มิลลิลิตร'},
        {'name': 'น้ำมันพืช', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'เกลือ', 'amount': 1, 'unit': 'ช้อนชา'},
        {'name': 'แป้งตอติญญา', 'amount': 8, 'unit': 'แผ่น'},
        {'name': 'ผักชีและหัวหอมซอย', 'amount': 30, 'unit': 'กรัม'},
      ],
      'steps': [
        'ผัดหัวหอมและกระเทียมในน้ำมันจนใส ใส่มะเขือเทศบดและพริกชิพอทเล่',
        'เติมน้ำซุป เคี่ยวให้ซอสข้นแล้วใส่ไก่ฉีก เคี่ยวต่อจนซึมซับรส',
        'อุ่นตอติญญาบนกระทะแห้ง ตักไส้ไก่ลงกลางแผ่น',
        'โรยผักชีและหัวหอมซอย เสิร์ฟพร้อมมะนาว',
      ],
      'cooking_time': 25,
      'prep_time': 15,
      'servings': 4,
      'source': 'Mexico in My Kitchen',
      'source_url': 'https://www.mexicoinmykitchen.com/chicken-tinga-tacos/',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_spanish_paella_valenciana',
      'name': 'Paella Valenciana',
      'description':
          'ข้าวผัดสเปนหอมเครื่องเทศ ใช้ไก่ กระต่าย (หรือหมู) และถั่วเขียว พร้อมหญ้าฝรั่น',
      'reason':
          'ประยุกต์ใช้ไก่และหมูแทนกระต่ายได้ ใช้ถั่วและข้าวสารที่มีในครัวไทย',
      'category': 'Rice',
      'tags': ['spanish', 'ai', 'rice'],
      'match_score': 75,
      'match_ratio': 0.75,
      'ingredients': [
        {'name': 'ข้าวเมล็ดสั้น', 'amount': 400, 'unit': 'กรัม'},
        {'name': 'สะโพกไก่หั่นชิ้น', 'amount': 400, 'unit': 'กรัม'},
        {'name': 'หมูสามชั้นหั่นชิ้น', 'amount': 150, 'unit': 'กรัม'},
        {'name': 'ถั่วเขียวโทดาโร', 'amount': 150, 'unit': 'กรัม'},
        {'name': 'ถั่วลันเตา', 'amount': 80, 'unit': 'กรัม'},
        {'name': 'มะเขือเทศขูด', 'amount': 150, 'unit': 'กรัม'},
        {'name': 'น้ำสต๊อกไก่', 'amount': 900, 'unit': 'มิลลิลิตร'},
        {'name': 'ผงหญ้าฝรั่น', 'amount': 0.25, 'unit': 'ช้อนชา'},
        {'name': 'น้ำมันมะกอก', 'amount': 3, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'พริกป่นรมควัน', 'amount': 1, 'unit': 'ช้อนชา'},
      ],
      'steps': [
        'ผัดไก่และหมูในกระทะพาเอลล่าให้ผิวเหลือง ตักพัก',
        'ผัดมะเขือเทศกับน้ำมันและพริกป่น ใส่ข้าวลงคลุก',
        'เติมสต๊อก หญ้าฝรั่น เนื้อสัตว์ และถั่ว เคี่ยวให้ข้าวดูดน้ำ',
        'ลดไฟ เคี่ยวจนข้าวสุกและเกิด socarrat เสิร์ฟพร้อมเลมอน',
      ],
      'cooking_time': 45,
      'prep_time': 20,
      'servings': 4,
      'source': 'Spanish Sabores',
      'source_url':
          'https://spanishsabores.com/authentic-spanish-paella-recipe/',
      'missing_ingredients': [],
    },
  ];

  static const Map<String, String> _knownRecipeLinks = {
    'ผัดกะเพราไก่ไข่ดาว':
        'https://www.wongnai.com/recipes/stir-fried-minced-chicken-with-holy-basil-and-fried-egg',
    'ต้มยำกุ้งน้ำใส': 'https://krua.co/recipe/tom-yam-goong-clear-soup/',
    'แกงเขียวหวานไก่': 'https://www.maeban.co.th/menu_detail.php?bl=1&id=563',
    'ผัดซีอิ๊วเส้นใหญ่หมู':
        'https://www.wongnai.com/recipes/stir-fried-flat-noodles-with-pork',
    'ไข่พะโล้หมูสามชั้น':
        'https://www.pholfoodmafia.com/recipe/five-spice-stewed-eggs-and-pork/',
    'kung pao chicken': 'https://www.chinasichuanfood.com/kung-pao-chicken/',
    'chicken teriyaki': 'https://www.justonecookbook.com/chicken-teriyaki/',
    'bibimbap': 'https://www.koreanbapsang.com/bibimbap/',
    'vietnamese beef pho': 'https://www.vickypham.com/food/vietnamese-beef-pho',
    'chicken tikka masala':
        'https://www.indianhealthyrecipes.com/chicken-tikka-masala/',
    'classic smash burger':
        'https://www.seriouseats.com/the-burger-lab-smashed-burger-recipe',
    'beer-battered fish and chips':
        'https://www.bbcgoodfood.com/recipes/beer-battered-fish-chips',
    'coq au vin': 'https://www.saveur.com/recipes/coq-au-vin/',
    'sauerbraten':
        'https://www.daringgourmet.com/traditional-german-sauerbraten/',
    'spaghetti carbonara':
        'https://www.giallozafferano.com/recipes/Spaghetti-Carbonara.html',
    'chicken tinga tacos':
        'https://www.mexicoinmykitchen.com/chicken-tinga-tacos/',
    'paella valenciana':
        'https://spanishsabores.com/authentic-spanish-paella-recipe/',
  };



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

  static String _normalizeHost(String host) =>
      host.trim().toLowerCase().replaceFirst(RegExp(r'^www\.'), '');

  bool _isTrustedImageHost(String imageHost, String baseHost) {
    final normalizedImage = _normalizeHost(imageHost);
    final normalizedBase = _normalizeHost(baseHost);
    if (normalizedImage == normalizedBase) return true;
    if (normalizedImage.endsWith('.$normalizedBase')) return true;
    if (normalizedBase.endsWith('.$normalizedImage')) return true;
    final allowed = _trustedImageHosts[normalizedBase];
    if (allowed != null) {
      for (final host in allowed) {
        final normalizedAllowed = _normalizeHost(host);
        if (normalizedImage == normalizedAllowed ||
            normalizedImage.endsWith('.$normalizedAllowed')) {
          return true;
        }
      }
    }
    return false;
  }

  /// Return a readable description of allergy coverage (expanded synonyms/translations).
  /// Falls back to a simple join of provided excludes if expansion fails or is empty.
  String describeAllergyCoverage(List<String> excludeIngredients) {
    try {
      final expansion = AllergyUtils.expandAllergens(excludeIngredients);
      final list = expansion.all.toList()..sort();
      if (list.isEmpty) return 'ไม่มีข้อมูลภูมิแพ้เพิ่มเติม';
      return list.join(', ');
    } catch (e) {
      // If anything goes wrong, return a reasonable fallback string
      if (excludeIngredients.isEmpty) return 'ไม่มีข้อมูลภูมิแพ้เพิ่มเติม';
      return excludeIngredients.join(', ');
    }
  }
}

class _FallbackCandidate {
  final RecipeModel recipe;
  final String? cuisine;
  final double ratio;
  final int matchedCount;
  final int totalCount;

  const _FallbackCandidate({
    required this.recipe,
    required this.cuisine,
    required this.ratio,
    required this.matchedCount,
    required this.totalCount,
  });
}

class _SelectedIngredientProfile {
  final String originalName;
  final Set<String> variants;

  _SelectedIngredientProfile({
    required this.originalName,
    required this.variants,
  });
}

class _CoverageInfo {
  final int totalSelected;
  final List<String> matchedNames;
  final List<String> missingNames;

  _CoverageInfo({
    required this.totalSelected,
    required this.matchedNames,
    required this.missingNames,
  });

  int get matchedCount => matchedNames.length;
  int get missingCount =>
      totalSelected > matchedCount ? totalSelected - matchedCount : 0;
  double get coverageRatio =>
      totalSelected == 0 ? 0 : matchedCount / totalSelected;
}

class _CoverageScoredRecipe {
  final RecipeModel recipe;
  final int matchedCount;
  final int missingCount;
  final int coveragePercent;

  _CoverageScoredRecipe({
    required this.recipe,
    required this.matchedCount,
    required this.missingCount,
    required this.coveragePercent,
  });
}
