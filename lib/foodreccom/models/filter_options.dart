class RecipeFilterOptions {
  final List<String> cuisineEn; // e.g., ['chinese','japanese','korean'] lowercased
  final Set<String> dietGoals; // 'vegan','high-fiber','high-protein','low-carb'
  final int? minCalories;
  final int? maxCalories;

  // If provided, these ingredients override AI selection for RapidAPI
  final List<String>? manualIngredientNames;

  const RecipeFilterOptions({
    this.cuisineEn = const [],
    this.dietGoals = const {},
    this.minCalories,
    this.maxCalories,
    this.manualIngredientNames,
  });

  RecipeFilterOptions copyWith({
    List<String>? cuisineEn,
    Set<String>? dietGoals,
    int? minCalories,
    int? maxCalories,
    List<String>? manualIngredientNames,
  }) {
    return RecipeFilterOptions(
      cuisineEn: cuisineEn ?? this.cuisineEn,
      dietGoals: dietGoals ?? this.dietGoals,
      minCalories: minCalories ?? this.minCalories,
      maxCalories: maxCalories ?? this.maxCalories,
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
    case 'high-fiber':
    case 'ใยอาหารสูง':
      return 'high-fiber';
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

