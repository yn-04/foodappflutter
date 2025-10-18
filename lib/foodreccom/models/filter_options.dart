class RecipeFilterOptions {
  final List<String> cuisineEn; // e.g., ['chinese','japanese','korean'] lowercased
  final Set<String> dietGoals; // e.g., 'vegan','vegetarian','ketogenic','low-fat','gluten-free','dairy-free','high-protein','low-carb'
  final int? minCalories;
  final int? maxCalories;
  // Macro thresholds (per serving)
  final int? minProtein; // grams
  final int? maxCarbs;   // grams
  final int? maxFat;     // grams

  // If provided, these ingredients override AI selection for RapidAPI
  final List<String>? manualIngredientNames;

  const RecipeFilterOptions({
    this.cuisineEn = const [],
    this.dietGoals = const {},
    this.minCalories,
    this.maxCalories,
    this.minProtein,
    this.maxCarbs,
    this.maxFat,
    this.manualIngredientNames,
  });

  RecipeFilterOptions copyWith({
    List<String>? cuisineEn,
    Set<String>? dietGoals,
    int? minCalories,
    int? maxCalories,
    int? minProtein,
    int? maxCarbs,
    int? maxFat,
    List<String>? manualIngredientNames,
  }) {
    return RecipeFilterOptions(
      cuisineEn: cuisineEn ?? this.cuisineEn,
      dietGoals: dietGoals ?? this.dietGoals,
      minCalories: minCalories ?? this.minCalories,
      maxCalories: maxCalories ?? this.maxCalories,
      minProtein: minProtein ?? this.minProtein,
      maxCarbs: maxCarbs ?? this.maxCarbs,
      maxFat: maxFat ?? this.maxFat,
      manualIngredientNames:
          manualIngredientNames ?? this.manualIngredientNames,
    );
  }
}

String mapCuisineToEn(String input) {
  final s = input.trim().toLowerCase();
  const map = {
    'จีน': 'chinese',
    'ญี่ปุ่น': 'japanese',
    'เกาหลี': 'korean',
    'ไทย': 'thai',
    'เวียดนาม': 'vietnamese',
    'อินเดีย': 'indian',
    'ฝรั่ง': 'european',
    'อิตาเลียน': 'italian',
    'เม็กซิกัน': 'mexican',
  };
  return map[s] ?? s;
}

String normalizeDietGoal(String input) {
  switch (input.trim().toLowerCase()) {
    case 'vegan':
      return 'vegan';
    case 'vegetarian':
    case 'มังสวิรัติ':
      return 'vegetarian';
    case 'lacto-vegetarian':
      return 'lacto-vegetarian';
    case 'ovo-vegetarian':
      return 'ovo-vegetarian';
    case 'ketogenic':
      return 'ketogenic';
    case 'paleo':
      return 'paleo';
    case 'low-fat':
    case 'ไขมันต่ำ':
      return 'low-fat';
    case 'gluten-free':
    case 'ปลอดกลูเตน':
      return 'gluten-free';
    case 'dairy-free':
    case 'ปลอดนม':
      return 'dairy-free';
    case 'high-protein':
    case 'โปรตีนสูง':
      return 'high-protein';
    case 'low-carb':
    case 'คาร์โบไฮเดรตต่ำ':
      return 'low-carb';
    default:
      return input.trim().toLowerCase();
  }
}
