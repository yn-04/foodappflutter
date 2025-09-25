import '../services/ai_translation_service.dart';

class ThaiLocalizer {
  static const Map<String, String> _unitMap = {
    'cup': 'ถ้วย',
    'cups': 'ถ้วย',
    'tbsp': 'ช้อนโต๊ะ',
    'tablespoon': 'ช้อนโต๊ะ',
    'tablespoons': 'ช้อนโต๊ะ',
    'tsp': 'ช้อนชา',
    'teaspoon': 'ช้อนชา',
    'teaspoons': 'ช้อนชา',
    'g': 'กรัม',
    'gram': 'กรัม',
    'grams': 'กรัม',
    'kg': 'กิโลกรัม',
    'ml': 'มิลลิลิตร',
    'l': 'ลิตร',
    'slice': 'แผ่น',
    'slices': 'แผ่น',
    'piece': 'ชิ้น',
    'pieces': 'ชิ้น',
    'pinch': 'หยิบมือ',
    'clove': 'กลีบ',
    'cloves': 'กลีบ',
  };

  static const Map<String, String> _ingredientMap = {
    'chili': 'พริก',
    'chilli': 'พริก',
    'red chili': 'พริกแดง',
    'green chili': 'พริกเขียว',
    'chicken': 'ไก่',
    'pork': 'หมู',
    'beef': 'เนื้อ',
    'egg': 'ไข่',
    'eggs': 'ไข่',
    'rice': 'ข้าว',
    'sticky rice': 'ข้าวเหนียว',
    'garlic': 'กระเทียม',
    'onion': 'หอมใหญ่',
    'shallot': 'หอมแดง',
    'basil': 'โหระพา',
    'holy basil': 'กะเพรา',
    'thai basil': 'โหระพา',
    'chinese kale': 'คะน้า',
    'kale': 'คะน้า',
    'lime': 'มะนาว',
    'lemon': 'เลมอน',
    'fish sauce': 'น้ำปลา',
    'soy sauce': 'ซีอิ๊ว',
    'oyster sauce': 'ซอสหอยนางรม',
    'sugar': 'น้ำตาล',
    'pepper': 'พริกไทย',
    'ginger': 'ขิง',
  };

  static const Map<String, String> _cuisineMap = {
    'thai': 'ไทย',
    'chinese': 'จีน',
    'japanese': 'ญี่ปุ่น',
    'korean': 'เกาหลี',
    'vietnamese': 'เวียดนาม',
    'indian': 'อินเดีย',
    'italian': 'อิตาเลียน',
    'mexican': 'เม็กซิกัน',
    'european': 'ฝรั่ง',
  };

  static String toThaiUnit(String unit) {
    final key = unit.trim().toLowerCase();
    return _unitMap[key] ?? unit;
  }

  static Future<String> toThaiText(String text) async {
    final t = text.trim();
    if (t.isEmpty) return t;
    // Lightweight heuristic: if mostly ASCII letters, try AI translate
    final asciiLetters = RegExp(r'^[ -~]+');
    if (asciiLetters.hasMatch(t)) {
      final res = await AITranslationService.translateToThai(t);
      return res;
    }
    return t;
  }

  static Future<String> toThaiIngredient(String name) async {
    final key = name.trim().toLowerCase();
    if (_ingredientMap.containsKey(key)) return _ingredientMap[key]!;
    return toThaiText(name);
  }

  static String toThaiCuisineTag(String tag) {
    final key = tag.trim().toLowerCase();
    return _cuisineMap[key] ?? tag;
  }
}

