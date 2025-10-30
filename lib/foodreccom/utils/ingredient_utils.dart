//lib/foodreccom/utils/ingredient_utils.dart
import '../models/cooking_history_model.dart';
import '../models/ingredient_model.dart';
import 'ingredient_translator.dart';

/// ---- Ingredient Matching ----
bool ingredientsMatch(String available, String required) {
  final availableVariants = _expandIngredientVariants(available);
  final requiredVariants = _expandIngredientVariants(required);

  if (availableVariants.isEmpty || requiredVariants.isEmpty) {
    return _basicMatch(available, required);
  }

  if (availableVariants.intersection(requiredVariants).isNotEmpty) {
    return true;
  }

  for (final a in availableVariants) {
    for (final r in requiredVariants) {
      if (a.contains(r) || r.contains(a)) return true;
    }
  }

  return _basicMatch(available, required);
}

/// คืนชุด keyword/alias สำหรับใช้จับคู่วัตถุดิบ
Set<String> ingredientKeywords(String raw) {
  return _expandIngredientVariants(raw);
}

/// ---- Utilization Rate ----
double calculateNewUtilizationRate(
  double currentRate,
  double usedAmount,
  double initialQuantity,
) {
  final usageRatio = usedAmount / initialQuantity;
  return ((currentRate * 0.8) + (usageRatio * 0.2)).clamp(0.0, 1.0);
}

/// ---- Cooking History Helpers ----
Map<String, int> summarizeFavoriteCategories(List<CookingHistory> history) {
  final categories = <String, int>{};
  for (final record in history) {
    categories[record.recipeCategory] =
        (categories[record.recipeCategory] ?? 0) + 1;
  }
  return Map.fromEntries(
    categories.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );
}

List<String> findLessUsedIngredients(
  List<CookingHistory> history,
  List<IngredientModel> available,
) {
  final usage = <String, int>{};

  for (final record in history) {
    for (final ing in record.usedIngredients) {
      usage[ing.name] = (usage[ing.name] ?? 0) + 1;
    }
  }

  return available
      .where((ing) => (usage[ing.name] ?? 0) == 0)
      .map((ing) => ing.name)
      .toList();
}

/// ---- Internal Helpers ----

bool _basicMatch(String available, String required) {
  final a = _normalizeText(available, keepSpaces: true);
  final r = _normalizeText(required, keepSpaces: true);
  if (a.isEmpty || r.isEmpty) return false;
  return a.contains(r) || r.contains(a);
}

Set<String> _expandIngredientVariants(String raw) {
  final candidates = <String>{};

  void addVariant(String value) {
    final withSpaces = _normalizeText(value, keepSpaces: true);
    final withoutSpaces = _normalizeText(value, keepSpaces: false);
    if (withSpaces.isNotEmpty) candidates.add(withSpaces);
    if (withoutSpaces.isNotEmpty) candidates.add(withoutSpaces);
  }

  addVariant(raw);

  final cleaned = _normalizeText(raw, keepSpaces: true);
  final tokens = _tokenize(cleaned);
  if (tokens.isNotEmpty) {
    addVariant(tokens.join(' '));
    for (final token in tokens) {
      addVariant(token);
    }
  }

  final translation = IngredientTranslator.translate(raw);
  if (translation.trim().isNotEmpty &&
      translation.trim().toLowerCase() != raw.trim().toLowerCase()) {
    addVariant(translation);
    final translationTokens = _tokenize(
      _normalizeText(translation, keepSpaces: true),
    );
    if (translationTokens.isNotEmpty) {
      addVariant(translationTokens.join(' '));
      for (final token in translationTokens) {
        addVariant(token);
      }
    }
  }

  final synonymCandidates = <String>{};
  for (final variant in candidates.toList()) {
    final key = _normalizeText(variant, keepSpaces: false);
    final group = _synonymLookup[key];
    if (group != null) {
      synonymCandidates.addAll(group);
    }
  }
  for (final synonym in synonymCandidates) {
    addVariant(synonym);
  }

  return candidates
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet();
}

String _normalizeText(String input, {required bool keepSpaces}) {
  var out = input.toLowerCase();
  out = out.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  out = out.replaceAll(RegExp(r'[\[\]{}]'), ' ');
  out = out.replaceAll(RegExp(r'[^\u0E00-\u0E7Fa-z0-9\s/]'), ' ');
  out = out.replaceAll(RegExp(r'[0-9]'), ' ');
  out = _stripThaiMarks(out);
  out = out.replaceAll('/', ' ');
  out = out.replaceAll(RegExp(r'\s+'), keepSpaces ? ' ' : '');
  return keepSpaces ? out.trim() : out.replaceAll(' ', '');
}

String _stripThaiMarks(String input) {
  return input.replaceAll(RegExp(r'[\u0E31\u0E34-\u0E3A\u0E47-\u0E4E]'), '');
}

List<String> _tokenize(String normalized) {
  final parts = normalized
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty);
  final filtered = <String>[];
  for (final token in parts) {
    if (_stopWords.contains(token)) continue;
    filtered.add(token);
  }
  return filtered;
}

final Set<String> _stopWords = {
  'ใบ',
  'ต้น',
  'สด',
  'แห้ง',
  'อ่อน',
  'แก่',
  'ดิบ',
  'สุก',
  'หั่น',
  'ซอย',
  'ซอยบาง',
  'ซอยละเอียด',
  'สับ',
  'บด',
  'ป่น',
  'หมัก',
  'แผ่น',
  'แบบ',
  'ชนิด',
  'กลีบ',
  'เม็ด',
  'หัว',
  'ก้าน',
  'สำหรับ',
  'หรือ',
  'และ',
  'เนื้อ',
  'การ',
  'เสิร์ฟ',
  'cup',
  'cups',
  'tbsp',
  'tablespoon',
  'tablespoons',
  'tsp',
  'teaspoon',
  'teaspoons',
  'ounce',
  'ounces',
  'oz',
  'gram',
  'grams',
  'g',
  'kg',
  'ml',
  'l',
  'liter',
  'liters',
  'piece',
  'pieces',
  'clove',
  'cloves',
  'bunch',
  'bunches',
  'sprig',
  'sprigs',
  'stalk',
  'stalks',
  'slice',
  'slices',
  'ground',
  'minced',
  'sliced',
  'chopped',
  'diced',
  'shredded',
  'peeled',
  'seeded',
  'crushed',
  'fresh',
  'dried',
  'boneless',
  'skinless',
  'fillet',
  'fillets',
  'whole',
  'medium',
  'large',
  'small',
  'thai',
  'leaves',
  'leaf',
  'powder',
  'powdered',
};

final List<Set<String>> _synonymGroups = [
  {
    'ไก่',
    'อกไก่',
    'สะโพกไก่',
    'น่องไก่',
    'chicken',
    'chicken breast',
    'chicken thigh',
    'chicken drumstick',
    'poultry',
  },
  {
    'หมู',
    'หมูสับ',
    'หมูบด',
    'หมูสามชั้น',
    'pork',
    'ground pork',
    'minced pork',
    'pork belly',
  },
  {'เนื้อ', 'เนื้อวัว', 'beef', 'beef steak', 'ground beef', 'sirloin'},
  {'กุ้ง', 'shrimp', 'prawn'},
  {'ปลาหมึก', 'หมึก', 'squid', 'calamari'},
  {
    'ปลา',
    'ปลาแซลมอน',
    'ปลาทูน่า',
    'ปลานิล',
    'ปลาทู',
    'fish',
    'salmon',
    'tuna',
    'mackerel',
    'tilapia',
  },
  {'ใบกะเพรา', 'กะเพรา', 'holy basil', 'holy basil leaves', 'bai kra prao'},
  {'ใบโหระพา', 'โหระพา', 'thai basil', 'sweet basil', 'bai horapha'},
  {'ผักชี', 'coriander', 'cilantro'},
  {'ตะไคร้', 'lemongrass'},
  {'ข่า', 'galangal'},
  {'ใบมะกรูด', 'kaffir lime leaves'},
  {'มะกรูด', 'kaffir lime'},
  {'มะนาว', 'lime', 'lemon'},
  {'ขิง', 'ginger'},
  {'กระเทียม', 'garlic'},
  {'หอมแดง', 'shallot', 'shallots'},
  {'หอมใหญ่', 'onion', 'yellow onion', 'white onion'},
  {'มะเขือเทศ', 'tomato', 'tomatoes'},
  {'แตงกวา', 'cucumber'},
  {'ผักกาดขาว', 'napa cabbage', 'chinese cabbage'},
  {'คะน้า', 'chinese kale', 'kai lan'},
  {'แครอท', 'carrot', 'carrots'},
  {'พริกขี้หนู', 'พริก', 'chili', 'chilli', 'bird chili', 'thai chili'},
  {'พริกไทย', 'pepper', 'black pepper'},
  {'เห็ดฟาง', 'straw mushroom'},
  {'เห็ดหอม', 'shiitake mushroom', 'shiitake'},
  {'เห็ดเข็มทอง', 'enoki mushroom', 'enoki'},
  {'เห็ดนางรม', 'oyster mushroom'},
  {'ฟักทอง', 'pumpkin'},
  {'ถั่วฝักยาว', 'yardlong beans', 'long beans'},
  {'ถั่วงอก', 'bean sprouts'},
  {'ถั่วลิสง', 'peanut', 'peanuts', 'groundnut'},
  {'น้ำปลา', 'fish sauce'},
  {'ซีอิ๊วขาว', 'light soy sauce', 'soy sauce'},
  {'ซีอิ๊วดำ', 'dark soy sauce'},
  {'ซอสหอยนางรม', 'oyster sauce'},
  {'น้ำตาล', 'sugar', 'granulated sugar'},
  {'น้ำตาลทราย', 'white sugar'},
  {'น้ำตาลปี๊บ', 'palm sugar'},
  {'กะทิ', 'coconut milk', 'coconut cream'},
  {'น้ำมันพืช', 'vegetable oil', 'cooking oil', 'canola oil', 'sunflower oil'},
  {'น้ำมันงา', 'sesame oil'},
  {'ข้าวหอมมะลิ', 'jasmine rice'},
  {'ข้าวสวย', 'cooked rice'},
  {'ข้าวสาร', 'uncooked rice'},
  {'เส้นหมี่', 'vermicelli', 'rice vermicelli'},
  {'วุ้นเส้น', 'glass noodles', 'mung bean noodles'},
  {'เส้นใหญ่', 'wide rice noodles', 'sen yai'},
  {'นมสด', 'milk', 'fresh milk'},
  {'เนย', 'butter'},
  {'ชีส', 'cheese'},
  {'ไข่', 'eggs', 'egg'},
  {'ไข่ไก่', 'chicken egg'},
  {'ไข่เป็ด', 'duck egg'},
  {'น้ำมะพร้าว', 'coconut water'},
  {'กุ้งแห้ง', 'dried shrimp'},
  {'น้ำซุป', 'stock', 'broth'},
  {'ใบสะระแหน่', 'mint leaves', 'mint'},
  {'ปลากะพง', 'seabass', 'barramundi'},
  {'เนยจืด', 'unsalted butter'},
];

final Map<String, Set<String>> _synonymLookup = () {
  final map = <String, Set<String>>{};
  for (final group in _synonymGroups) {
    final normalizedGroup = group
        .map((value) => _normalizeText(value, keepSpaces: false))
        .where((value) => value.isNotEmpty)
        .toSet();
    for (final key in normalizedGroup) {
      map.putIfAbsent(key, () => <String>{}).addAll(group);
    }
  }
  return map;
}();
