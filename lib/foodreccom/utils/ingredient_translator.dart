import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IngredientTranslator {
  /// 📌 Dictionary ไทย → อังกฤษ (static)
  static final Map<String, String> _translationMap = {
    // 🍚 คาร์โบไฮเดรต
    'ข้าว': 'rice',
    'ข้าวหอมมะลิ': 'jasmine rice',
    'ข้าวสวย': 'cooked rice',
    'ข้าวสาร': 'uncooked rice',
    'เส้นก๋วยเตี๋ยว': 'rice noodles',
    'เส้นหมี่': 'vermicelli',
    'วุ้นเส้น': 'glass noodles',
    'ขนมปัง': 'bread',
    'มันฝรั่ง': 'potato',
    'มันเทศ': 'sweet potato',
    'ฟักทอง': 'pumpkin',
    'ข้าวโพด': 'corn',

    // 🥩 เนื้อสัตว์
    'ไก่': 'chicken',
    'น่องไก่': 'chicken drumstick',
    'ปีกไก่': 'chicken wings',
    'หมู': 'pork',
    'หมูสับ': 'ground pork',
    'หมูสามชั้น': 'pork belly',
    'เนื้อ': 'beef',
    'กุ้ง': 'shrimp',
    'ปลาหมึก': 'squid',
    'ปลา': 'fish',
    'ปลาแซลมอน': 'salmon',
    'ปลาทู': 'mackerel',
    'ปลานิล': 'tilapia',
    'ปลาทูน่า': 'tuna',
    'ปู': 'crab',
    'หอยแมลงภู่': 'mussels',
    'หอยแครง': 'cockles',
    'ไข่': 'egg',
    'ไข่ไก่': 'egg',
    'ไข่เป็ด': 'duck egg',

    // 🥦 ผัก
    'กะเพรา': 'holy basil',
    'โหระพา': 'thai basil',
    'ผักชี': 'coriander',
    'คะน้า': 'chinese kale',
    'ผักกาดขาว': 'napa cabbage',
    'กะหล่ำปลี': 'cabbage',
    'บรอกโคลี': 'broccoli',
    'แครอท': 'carrot',
    'หอมใหญ่': 'onion',
    'หอมแดง': 'shallot',
    'กระเทียม': 'garlic',
    'มะเขือเทศ': 'tomato',
    'แตงกวา': 'cucumber',
    'ถั่วฝักยาว': 'yardlong beans',
    'ถั่วงอก': 'bean sprouts',
    'เห็ดฟาง': 'straw mushroom',
    'เห็ดหอม': 'shiitake mushroom',
    'เห็ดเข็มทอง': 'enoki mushroom',
    'ฟัก': 'winter melon',
    'มะเขือเปราะ': 'thai eggplant',
    'มะเขือยาว': 'eggplant',

    // 🌶️ เครื่องเทศ/สมุนไพร
    'พริก': 'chili',
    'พริกแดง': 'red chili',
    'พริกเขียว': 'green chili',
    'พริกแห้ง': 'dried chili',
    'พริกไทย': 'pepper',
    'ตะไคร้': 'lemongrass',
    'ข่า': 'galangal',
    'ใบมะกรูด': 'kaffir lime leaves',
    'มะนาว': 'lime',
    'ขิง': 'ginger',

    // 🥫 เครื่องปรุงรส
    'เต้าเจี้ยว': 'soybean paste',
    'น้ำปลา': 'fish sauce',
    'ซีอิ๊ว': 'soy sauce',
    'ซอสหอยนางรม': 'oyster sauce',
    'น้ำตาล': 'sugar',
    'กะทิ': 'coconut milk',
    'นมสด': 'milk',
    'นมข้นหวาน': 'condensed milk',
    'เนย': 'butter',
    'เกลือ': 'salt',
    'ชีส': 'cheese',
    'น้ำมัน': 'oil',
  };

  /// 📌 Cache (เรียนรู้จาก RapidAPI)
  static final Map<String, String> _learnedCache = {};

  static const _prefsKey = 'ingredient_translator_cache';

  /// โหลด cache จาก SharedPreferences
  static Future<void> loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final map = prefs.getStringList(_prefsKey) ?? [];
    for (final entry in map) {
      final parts = entry.split('::');
      if (parts.length == 2) {
        _learnedCache[parts[0]] = parts[1];
      }
    }
    debugPrint("🗂️ Loaded ${_learnedCache.length} learned mappings");
  }

  /// เซฟ cache ลง SharedPreferences
  static Future<void> saveCache() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _learnedCache.entries
        .map((e) => "${e.key}::${e.value}")
        .toList();
    await prefs.setStringList(_prefsKey, list);
  }

  /// แปลชื่อวัตถุดิบ → อังกฤษ
  static String translate(String name) {
    final normalized = name.trim().toLowerCase();

    if (_learnedCache.containsKey(normalized)) {
      return _learnedCache[normalized]!;
    }

    if (_translationMap.containsKey(normalized)) {
      return _translationMap[normalized]!;
    }

    for (final entry in _translationMap.entries) {
      if (normalized.contains(entry.key)) return entry.value;
    }

    return name;
  }

  /// แปลลิสต์
  static List<String> translateList(List<String> names) {
    return names.map(translate).toList();
  }

  /// Auto-learn mapping จาก RapidAPI
  static Future<void> learnMapping(String original, String suggested) async {
    final key = original.trim().toLowerCase();
    final value = suggested.trim().toLowerCase();
    _learnedCache[key] = value;
    debugPrint("🧠 Learned mapping: $original → $suggested");
    await saveCache();
  }
}
