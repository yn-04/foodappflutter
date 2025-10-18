import '../models/recipe/recipe_model.dart';

class RecipeImageHelper {
  static const String _defaultImage =
      'https://images.unsplash.com/photo-1466637574441-749b8f19452f?auto=format&fit=crop&w=900&q=80';

  static String get defaultImage => _defaultImage;

  static const Map<String, String> _categoryImages = {
    'อาหารจานหลัก':
        'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=900&q=80',
    'ของหวาน':
        'https://images.unsplash.com/photo-1505253217343-41af6ba0577b?auto=format&fit=crop&w=900&q=80',
    'อาหารเรียกน้ำย่อย':
        'https://images.unsplash.com/photo-1525755662778-989d0524087e?auto=format&fit=crop&w=900&q=80',
    'สลัด':
        'https://images.unsplash.com/photo-1525755662778-989d0524087e?auto=format&fit=crop&w=900&q=80',
    'ซุป':
        'https://images.unsplash.com/photo-1543353071-873f17a7a088?auto=format&fit=crop&w=900&q=80',
    'ขนม':
        'https://images.unsplash.com/photo-1499636136210-6f4ee915583e?auto=format&fit=crop&w=900&q=80',
    'เครื่องดื่ม':
        'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=900&q=80',
  };

  static const Map<String, String> _tagImages = {
    'thai':
        'https://images.unsplash.com/photo-1608032361953-166224245012?auto=format&fit=crop&w=900&q=80',
    'japanese':
        'https://images.unsplash.com/photo-1498654896293-37aacf113fd9?auto=format&fit=crop&w=900&q=80',
    'korean':
        'https://images.unsplash.com/photo-1554998171-89445e31c52b?auto=format&fit=crop&w=900&q=80',
    'chinese':
        'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=900&q=80',
    'italian':
        'https://images.unsplash.com/photo-1473093226795-af9932fe5856?auto=format&fit=crop&w=900&q=80',
    'mexican':
        'https://images.unsplash.com/photo-1604909052858-94e03e9f4a56?auto=format&fit=crop&w=900&q=80',
    'american':
        'https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?auto=format&fit=crop&w=900&q=80',
    'vegan':
        'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=900&q=80',
    'vegetarian':
        'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=900&q=80',
    'seafood':
        'https://images.unsplash.com/photo-1514516345957-556ca7c18bae?auto=format&fit=crop&w=900&q=80',
    'dessert':
        'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=900&q=80',
    'salad':
        'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&w=900&q=80',
    'soup':
        'https://images.unsplash.com/photo-1543353071-873f17a7a088?auto=format&fit=crop&w=900&q=80',
  };

  static String imageFor(RecipeModel recipe) {
    final url = recipe.imageUrl;
    if (url != null && url.trim().isNotEmpty) return url;

    final query = _buildQueryImage(recipe.name);
    if (query != null) return query;

    for (final tag in recipe.tags) {
      final key = tag.toLowerCase().trim();
      if (_tagImages.containsKey(key)) return _tagImages[key]!;
    }

    final categoryKey = recipe.category.trim().toLowerCase();
    for (final entry in _categoryImages.entries) {
      if (entry.key.toLowerCase() == categoryKey) return entry.value;
    }

    return _defaultImage;
  }

  static String? _buildQueryImage(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^a-zA-Z0-9ก-๙\\s]'), '').trim();
    if (cleaned.isEmpty) return null;
    final encoded = Uri.encodeComponent(cleaned);
    return 'https://source.unsplash.com/900x600/?food,$encoded';
  }
}

extension RecipeModelImageExt on RecipeModel {
  String get displayImageUrl => RecipeImageHelper.imageFor(this);
}
