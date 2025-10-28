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
  }) async {
    if (!_isAiGenerationEnabled()) {
      print('ℹ️ AI generation disabled → ใช้ fallback');
      return _fallbackAiRecommendations();
    }
    if (selectedIngredients.isEmpty) return [];

    final hostToSource = <String, String>{};
    for (final site in _trustedReferenceSites) {
      final url = site['url']!;
      final host = Uri.parse(url).host.replaceFirst('www.', '').toLowerCase();
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

    final nearExpiry = inventory
        .where((i) => i.isUrgentExpiry || i.isNearExpiry)
        .map((i) => i.name)
        .toList();

    final allergyLine = allergyNames.isEmpty
        ? 'ไม่มี'
        : allergyNames.join(', ');
    final cuisineLine = cuisineFilters.isEmpty
        ? 'เน้นอาหารไทยหรือ Asian comfort food'
        : cuisineFilters.join(', ');
    final dietLine = dietGoals.isEmpty ? 'ไม่มี' : dietGoals.join(', ');

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

    final prompt =
        '''
คุณคือเชฟอาหารไทยและนักโภชนาการมืออาชีพ ช่วยแนะนำ 5 เมนูที่ทำได้จริงจากคลังวัตถุดิบด้านล่างนี้

วัตถุดิบหลักที่ควรใช้:
$ingredientLines

วัตถุดิบใกล้หมดอายุ: ${nearExpiry.isEmpty ? 'ไม่มี' : nearExpiry.join(', ')}
ข้อจำกัดภูมิแพ้: $allergyLine
ข้อจำกัดโภชนาการ: $nutritionLine
ลักษณะอาหารที่ต้องการ: $cuisineLine
เป้าหมายด้านไลฟ์สไตล์/อาหาร: $dietLine

กฎสำคัญ:
1. ใช้วัตถุดิบจากรายการผู้ใช้ให้มากที่สุด หลีกเลี่ยงของที่ไม่มี
2. อนุญาตเฉพาะของครัวพื้นฐาน (น้ำปลา น้ำตาล น้ำมัน พริก กระเทียม ซีอิ๊ว) หากจำเป็น
3. คำนวณ match_ratio = (จำนวนวัตถุดิบที่ผู้ใช้มี) / (จำนวนวัตถุดิบทั้งหมดของเมนู) และ match_score = match_ratio * 100
4. ให้เหตุผลว่าทำไมเมนูนี้เหมาะ พร้อมสรุปว่าขาดอะไรบ้าง (ถ้ามี)
5. อ้างอิงเว็บไซต์ที่น่าเชื่อถือจากรายการนี้เท่านั้น:
${_trustedReferenceSites.map((site) => "- ${site['name']} (${site['url']})").join('\n')}
6. source_url ต้องเป็นลิงก์หน้าเมนูนั้นโดยตรง (เช่น https://www.wongnai.com/recipes/ชื่อเมนู) ห้ามใช้หน้ารวม/หน้าหลัก/หน้าค้นหา
7. หลีกเลี่ยงเมนูของหวานหรือทอดมัน ๆ
8. ตอบกลับเป็น JSON เดียวที่มีคีย์ "recipes" เท่านั้น ไม่มีคำอธิบายอื่น

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
      final filtered = _filterAiRecipesByTrustedSources(parsed, hostToSource);
      if (filtered.isNotEmpty) {
        final enriched = _applyNutritionEstimates(filtered);
        return _ensureFiveRecommendations(enriched);
      }
    } catch (e, st) {
      print('⚠️ generateTextSmart error: $e');
      debugPrintStack(stackTrace: st);
    }

    return _fallbackAiRecommendations();
  }

  List<RecipeModel> _filterAiRecipesByTrustedSources(
    List<RecipeModel> recipes,
    Map<String, String> hostToSource,
  ) {
    final filtered = <RecipeModel>[];
    for (final recipe in recipes) {
      final rawUrl = recipe.sourceUrl ?? '';
      if (rawUrl.isEmpty) continue;
      Uri? uri = Uri.tryParse(rawUrl);
      if (uri == null || uri.host.isEmpty) {
        uri = Uri.tryParse('https://$rawUrl');
      }
      if (uri == null || uri.host.isEmpty) continue;
      final baseHost = uri.host.replaceFirst('www.', '').toLowerCase();
      MapEntry<String, String>? matched;
      for (final entry in hostToSource.entries) {
        if (baseHost.contains(entry.key)) {
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

      final tags = {...recipe.tags, 'ai', 'trusted'};
      filtered.add(
        recipe.copyWith(
          source: matched.value,
          sourceUrl: uri.toString(),
          tags: tags.toList(),
        ),
      );
    }
    return _dedupeRecipes(filtered).take(5).toList();
  }

  List<RecipeModel> _ensureFiveRecommendations(List<RecipeModel> current) {
    if (current.length >= 5) {
      return _applyNutritionEstimates(current.take(5).toList());
    }
    final merged = [...current];
    final existing = merged.map((r) => _normalizeName(r.name)).toSet();
    for (final recipe in _fallbackAiRecommendations()) {
      if (merged.length >= 5) break;
      final key = _normalizeName(recipe.name);
      if (existing.add(key)) {
        merged.add(recipe);
      }
    }
    return _applyNutritionEstimates(merged.take(5).toList());
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

  List<RecipeModel> _fallbackAiRecommendations() {
    final recipes = _fallbackAiRecipeMaps.map(RecipeModel.fromAI).toList();
    return _applyNutritionEstimates(recipes);
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
  ];

  static const Map<String, String> _knownRecipeLinks = {
    'ผัดกะเพราไก่ไข่ดาว':
        'https://www.wongnai.com/recipes/stir-fried-minced-chicken-with-holy-basil-and-fried-egg',
    'ต้มยำกุ้งน้ำใส': 'https://krua.co/recipe/tom-yam-goong-clear-soup/',
    'แกงเขียวหวานไก่': 'https://www.maeban.co.th/menu_detail.php?bl=1&id=563',
    'ไข่เจียวหมูสับฟูกรอบ':
        'https://cookpad.com/th/recipes/5292085-ไข่เจียวหมูสับฟูกรอบ',
    'ยำเห็ดรวมสมุนไพร':
        'https://www.pholfoodmafia.com/recipe/spicy-mushroom-salad/',
  };

  static const List<Map<String, dynamic>> _fallbackAiRecipeMaps = [
    {
      'id': 'ai_wongnai_pad_kra_prao',
      'name': 'ผัดกะเพราไก่ไข่ดาว',
      'description':
          'ผัดกะเพราไก่รสจัดจ้าน เสิร์ฟพร้อมไข่ดาวกรอบและข้าวสวยร้อน',
      'reason':
          'ใช้ไก่ กระเทียม พริก และไข่ที่มีอยู่แล้ว ปรุงเสร็จในเวลาไม่นาน เหมาะสำหรับมือใหม่',
      'category': 'อาหารจานเดียว',
      'tags': ['thai', 'ai', 'quick', 'stir-fry'],
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
        'ใส่อกไก่สับลงผัดจนสุก ปรุงรสด้วยน้ำปลา ซีอิ๊วขาว และน้ำตาลทราย ชิมรส',
        'ปิดไฟแล้วใส่ใบกะเพราผัดคลุกให้เข้ากัน',
        'ทอดไข่ดาวในน้ำมันร้อนจนขอบกรอบ',
        'ตักเสิร์ฟผัดกะเพรา คู่กับข้าวสวยและไข่ดาว',
      ],
      'cooking_time': 12,
      'prep_time': 8,
      'servings': 2,
      'source': 'Wongnai',
      'source_url':
          'https://www.wongnai.com/recipes/stir-fried-minced-chicken-with-holy-basil-and-fried-egg',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_kruaco_tom_yum_goong',
      'name': 'ต้มยำกุ้งน้ำใส',
      'description':
          'ซุปต้มยำกุ้งน้ำใสหอมสมุนไพร เผ็ดเปรี้ยวร้อนแรงตามแบบฉบับไทย',
      'reason':
          'ใช้กุ้งสด เห็ด และสมุนไพรไทยที่เก็บในครัวอยู่แล้ว เหมาะกับผู้ที่ต้องการเมนูซดร้อน',
      'category': 'ซุป',
      'tags': ['thai', 'ai', 'soup', 'seafood'],
      'match_score': 88,
      'match_ratio': 0.88,
      'ingredients': [
        {'name': 'กุ้งขนาดกลาง', 'amount': 6, 'unit': 'ตัว'},
        {'name': 'เห็ดฟางหรือเห็ดนางรม', 'amount': 120, 'unit': 'กรัม'},
        {'name': 'ตะไคร้หั่นท่อน', 'amount': 2, 'unit': 'ต้น'},
        {'name': 'ใบมะกรูดฉีก', 'amount': 4, 'unit': 'ใบ'},
        {'name': 'ข่าแก่หั่นแว่น', 'amount': 4, 'unit': 'แว่น'},
        {'name': 'พริกขี้หนูสวนบุบ', 'amount': 6, 'unit': 'เม็ด'},
        {'name': 'น้ำปลา', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำมะนาว', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำซุปกระดูก', 'amount': 600, 'unit': 'มิลลิลิตร'},
        {'name': 'ผักชีลาวหรือผักชีไทยซอย', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
      ],
      'steps': [
        'ตั้งหม้อใส่น้ำซุป ตะไคร้ ข่า และใบมะกรูด ต้มจนหอม',
        'ใส่เห็ดและกุ้ง ต้มจนกุ้งเริ่มสุก ปรุงรสด้วยน้ำปลา',
        'ปิดไฟก่อนใส่น้ำมะนาวและพริกขี้หนูบุบ เพื่อรักษากลิ่นหอม',
        'โรยผักชีซอยก่อนเสิร์ฟ พร้อมข้าวสวยหรือทานเปล่า ๆ',
      ],
      'cooking_time': 18,
      'prep_time': 10,
      'servings': 2,
      'source': 'Krua.co',
      'source_url': 'https://krua.co/recipe/tom-yam-goong-clear-soup/',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_maeban_green_curry',
      'name': 'แกงเขียวหวานไก่',
      'description':
          'แกงเขียวหวานไก่หอมกะทิ ใส่มะเขือพวงและโหระพา เสิร์ฟกับข้าวหรือเส้นขนมจีน',
      'reason':
          'ใช้สะโพกไก่ กะทิ น้ำพริกแกง และผักสวนครัวที่มีอยู่ เตรียมล่วงหน้าได้สำหรับหลายมื้อ',
      'category': 'แกงกะทิ',
      'tags': ['thai', 'ai', 'curry'],
      'match_score': 86,
      'match_ratio': 0.86,
      'ingredients': [
        {'name': 'สะโพกไก่หั่นชิ้น', 'amount': 300, 'unit': 'กรัม'},
        {'name': 'น้ำพริกแกงเขียวหวาน', 'amount': 70, 'unit': 'กรัม'},
        {'name': 'หัวกะทิ', 'amount': 250, 'unit': 'มิลลิลิตร'},
        {'name': 'หางกะทิหรือ น้ำซุป', 'amount': 300, 'unit': 'มิลลิลิตร'},
        {'name': 'มะเขือพวง', 'amount': 50, 'unit': 'กรัม'},
        {'name': 'ใบโหระพา', 'amount': 30, 'unit': 'กรัม'},
        {'name': 'น้ำปลา', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำตาลปี๊บ', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'ใบมะกรูด', 'amount': 3, 'unit': 'ใบ'},
      ],
      'steps': [
        'ผัดน้ำพริกแกงเขียวหวานกับหัวกะทิให้แตกมัน',
        'ใส่ไก่ผัดจนตึงตัว เติมหางกะทิ เคี่ยวจนไก่นุ่ม',
        'ปรุงรสด้วยน้ำปลาและน้ำตาลปี๊บ ใส่มะเขือพวงเคี่ยวต่อพอสุก',
        'ปิดไฟ โรยใบโหระพาและใบมะกรูดฉีก เสิร์ฟคู่ข้าวสวยหรือเส้นขนมจีน',
      ],
      'cooking_time': 25,
      'prep_time': 15,
      'servings': 4,
      'source': 'Maeban',
      'source_url': 'https://www.maeban.co.th/menu_detail.php?bl=1&id=563',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_cookpad_pork_omelette',
      'name': 'ไข่เจียวหมูสับฟูกรอบ',
      'description': 'ไข่เจียวหมูสับเนื้อแน่นฟูกรอบ ทำง่าย ใช้วัตถุดิบพื้นฐาน',
      'reason':
          'ใช้ไข่ หมูสับ และเครื่องปรุงทั่วไป เหมาะสำหรับมื้อเร่งด่วนหรือเด็ก ๆ',
      'category': 'อาหารจานเดียว',
      'tags': ['thai', 'ai', 'omelette', 'quick'],
      'match_score': 94,
      'match_ratio': 0.94,
      'ingredients': [
        {'name': 'ไข่ไก่', 'amount': 3, 'unit': 'ฟอง'},
        {'name': 'หมูสับ', 'amount': 120, 'unit': 'กรัม'},
        {'name': 'ซอสปรุงรส', 'amount': 1, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำปลา', 'amount': 0.5, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำมันพืช', 'amount': 1.5, 'unit': 'ถ้วยตวง'},
        {'name': 'หอมใหญ่ซอย', 'amount': 30, 'unit': 'กรัม'},
      ],
      'steps': [
        'ตีไข่ในชาม ใส่หมูสับ หอมใหญ่ และปรุงรสด้วยซอสปรุงรส น้ำปลา',
        'ตีให้ฟูเพื่อให้ไข่ขึ้นฟอง',
        'ตั้งน้ำมันให้ร้อนจัด เทไข่ลงทอดกลับสองด้านจนเหลืองกรอบ',
        'ตักพักน้ำมัน เสิร์ฟคู่ซอสพริกและข้าวสวย',
      ],
      'cooking_time': 10,
      'prep_time': 5,
      'servings': 2,
      'source': 'Cookpad Thailand',
      'source_url':
          'https://cookpad.com/th/recipes/5292085-ไข่เจียวหมูสับฟูกรอบ',
      'missing_ingredients': [],
    },
    {
      'id': 'ai_pholfood_mafia_spicy_mushroom_salad',
      'name': 'ยำเห็ดรวมสมุนไพร',
      'description':
          'ยำเห็ดรวมรสจัดจ้าน หอมสมุนไพร เหมาะสำหรับมื้อเบา ๆ หรือทานคู่กับข้าว',
      'reason':
          'ใช้เห็ด ผักสด และน้ำปรุงยำที่มีอยู่ เสริมสมุนไพรเพื่อเพิ่มรสชาติและกลิ่นหอม',
      'category': 'ยำ',
      'tags': ['thai', 'ai', 'salad', 'healthy'],
      'match_score': 84,
      'match_ratio': 0.84,
      'ingredients': [
        {'name': 'เห็ดออรินจิหั่นชิ้น', 'amount': 80, 'unit': 'กรัม'},
        {'name': 'เห็ดเข็มทอง', 'amount': 70, 'unit': 'กรัม'},
        {'name': 'เห็ดนางรม', 'amount': 70, 'unit': 'กรัม'},
        {'name': 'หอมแดงซอย', 'amount': 2, 'unit': 'หัว'},
        {'name': 'ตะไคร้ซอย', 'amount': 1, 'unit': 'ต้น'},
        {'name': 'พริกขี้หนูซอย', 'amount': 5, 'unit': 'เม็ด'},
        {'name': 'น้ำปลา', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำมะนาว', 'amount': 2, 'unit': 'ช้อนโต๊ะ'},
        {'name': 'น้ำตาลปี๊บ', 'amount': 1, 'unit': 'ช้อนชา'},
        {'name': 'ใบสะระแหน่', 'amount': 10, 'unit': 'ใบ'},
      ],
      'steps': [
        'ลวกเห็ดต่าง ๆ ในน้ำเดือดให้สุก พักให้สะเด็ดน้ำ',
        'ผสมน้ำปลา น้ำมะนาว น้ำตาลปี๊บ คนให้น้ำตาลละลาย',
        'คลุกเห็ดกับน้ำยำ ใส่หอมแดง ตะไคร้ และพริกขี้หนู คลุกให้เข้ากัน',
        'โรยใบสะระแหน่ก่อนเสิร์ฟ เพิ่มความหอมสดชื่น',
      ],
      'cooking_time': 12,
      'prep_time': 8,
      'servings': 2,
      'source': 'Phol Food Mafia',
      'source_url':
          'https://www.pholfoodmafia.com/recipe/spicy-mushroom-salad/',
      'missing_ingredients': [],
    },
  ];

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
