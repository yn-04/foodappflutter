import '../models/recipe/recipe_model.dart';

class RecipeImageHelper {
  static const String fallbackAsset = 'assets/images/recipe_placeholder.jpg';

  static String imageFor(RecipeModel recipe) {
    final url = recipe.imageUrl?.trim();
    if (url == null || url.isEmpty) return '';
    return url;
  }

  static bool hasNetworkImage(RecipeModel recipe) {
    final url = recipe.imageUrl?.trim();
    return url != null && url.isNotEmpty;
  }
}

extension RecipeModelImageExt on RecipeModel {
  String get displayImageUrl => RecipeImageHelper.imageFor(this);
  bool get hasDisplayImage => RecipeImageHelper.hasNetworkImage(this);
}
