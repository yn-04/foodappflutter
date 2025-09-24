import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recipe/recipe.dart';
import '../models/ingredient_model.dart';
import '../utils/recipe_parser.dart';
import '../utils/ingredient_translator.dart';

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
    int maxResults = 10,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ingredientNames = ingredients.map((i) => i.name).toList();

      // ✅ แปลวัตถุดิบไทย → อังกฤษ
      final translatedNames = IngredientTranslator.translateList(
        ingredientNames,
      );

      final cacheKey = '${_cacheKey}_${translatedNames.join(",")}';

      final url = Uri.parse(
        '$_spoonacularBase/recipes/findByIngredients'
        '?ingredients=${Uri.encodeComponent(translatedNames.join(","))}'
        '&number=$maxResults&ranking=1',
      );

      print("🌍 Calling RapidAPI: $url");
      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);

        // ✅ Auto-learn mapping ถ้า RapidAPI แนะนำ
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

        // ✅ ดึงรายละเอียดแต่ละเมนู
        final futures = data.map((r) => _getRecipeDetails(r['id']));
        final detailed = await Future.wait(futures);

        final recipes = detailed.whereType<RecipeModel>().toList();

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
      } else {
        throw Exception(
          'RapidAPI Error: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('❌ Error searchRecipesByIngredients: $e');
      return [];
    }
  }

  /// 📌 ดึงรายละเอียดสูตรอาหาร
  Future<RecipeModel?> _getRecipeDetails(int recipeId) async {
    try {
      final url = Uri.parse(
        '$_spoonacularBase/recipes/$recipeId/information?includeNutrition=true',
      );

      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return RecipeParser.parseSpoonacularRecipe(data);
      }
      return null;
    } catch (e) {
      print('❌ Error getRecipeDetails: $e');
      return null;
    }
  }
}
