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
    'แซลมอน': 'salmon',
    'แซลม่อน': 'salmon',
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
    'ถั่วลิสง': 'peanut',
    'ถั่วลิสงคั่ว': 'roasted peanut',
    'ถั่วคั่ว': 'roasted peanut',
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

  /// Precomputed map with Thai diacritics stripped from keys for robust matching
  static final Map<String, String> _strippedKeyMap = {
    for (final e in _translationMap.entries)
      _stripThaiMarks(e.key): e.value,
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
    final trimmed = name.trim();
    final normalized = _stripThaiMarks(trimmed.toLowerCase());

    if (_learnedCache.containsKey(normalized)) {
      return _learnedCache[normalized]!;
    }

    if (_translationMap.containsKey(normalized)) {
      return _translationMap[normalized]!;
    }

    // Try stripped-key exact/substring match
    if (_strippedKeyMap.containsKey(normalized)) {
      return _strippedKeyMap[normalized]!;
    }

    for (final entry in _strippedKeyMap.entries) {
      if (normalized.contains(entry.key)) return entry.value;
    }

    if (_containsThai(trimmed)) {
      final romanized = _romanizeThai(trimmed);
      if (romanized.isNotEmpty) {
        return romanized;
      }
    }

    return name;
  }

  /// แปลลิสต์
  static List<String> translateList(List<String> names) {
    return names.map(translate).toList();
  }

  /// Auto-learn mapping จาก RapidAPI
  static Future<void> learnMapping(String original, String suggested) async {
    final key = _stripThaiMarks(original.trim().toLowerCase());
    final value = suggested.trim().toLowerCase();

    bool containsDigit(String s) => RegExp(r"[0-9]").hasMatch(s);
    final noisyWords = {
      'ounces','ounce','oz','cup','cups','tbsp','tablespoon','tsp','teaspoon',
      'g','kg','ml','l','slices','slice','for','garnish','carton','package','pack'
    };
    bool hasNoisyWord(String s) {
      final words = s.split(RegExp(r"\s+"));
      for (final w in words) {
        if (noisyWords.contains(w)) return true;
      }
      return false;
    }

    final tooLong = key.length > 40 || value.length > 40;
    final tooManyWords =
        key.split(RegExp(r"\s+")).length > 5 || value.split(RegExp(r"\s+")).length > 5;

    if (containsDigit(key) ||
        containsDigit(value) ||
        hasNoisyWord(key) ||
        hasNoisyWord(value) ||
        tooLong ||
        tooManyWords) {
      debugPrint("🧠 Skip learning noisy mapping: $original → $suggested");
      return;
    }

    _learnedCache[key] = value;
    debugPrint("🧠 Learned mapping: $original → $suggested");
    await saveCache();
  }

  /// Remove Thai tone/diacritic marks to make matching robust
  static String _stripThaiMarks(String input) {
    // Remove: 31 (mai han-akat), 34-3A (vowels), 47-4E (combining marks)
    return input.replaceAll(RegExp(r"[\u0E31\u0E34-\u0E3A\u0E47-\u0E4E]"), "");
  }

  static bool _containsThai(String input) {
    return RegExp(r"[\u0E00-\u0E7F]").hasMatch(input);
  }

  static String _romanizeThai(String input) {
    final buffer = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      final mapped = _thaiToLatin[char];
      if (mapped != null) {
        buffer.write(mapped);
      } else if (char.codeUnitAt(0) <= 127) {
        buffer.write(char);
      }
    }
    return buffer.toString().replaceAll(RegExp(r"\s+"), ' ').trim();
  }

  static const Map<String, String> _thaiToLatin = {
    'ก': 'k',
    'ข': 'kh',
    'ฃ': 'kh',
    'ค': 'kh',
    'ฅ': 'kh',
    'ฆ': 'kh',
    'ง': 'ng',
    'จ': 'ch',
    'ฉ': 'ch',
    'ช': 'ch',
    'ซ': 's',
    'ฌ': 'ch',
    'ญ': 'y',
    'ฎ': 'd',
    'ฏ': 't',
    'ฐ': 'th',
    'ฑ': 'th',
    'ฒ': 'th',
    'ณ': 'n',
    'ด': 'd',
    'ต': 't',
    'ถ': 'th',
    'ท': 'th',
    'ธ': 'th',
    'น': 'n',
    'บ': 'b',
    'ป': 'p',
    'ผ': 'ph',
    'ฝ': 'f',
    'พ': 'ph',
    'ฟ': 'f',
    'ภ': 'ph',
    'ม': 'm',
    'ย': 'y',
    'ร': 'r',
    'ฤ': 'rue',
    'ล': 'l',
    'ฦ': 'lue',
    'ว': 'w',
    'ศ': 's',
    'ษ': 's',
    'ส': 's',
    'ห': 'h',
    'ฬ': 'l',
    'อ': 'o',
    'ฮ': 'h',
    'ะ': 'a',
    'า': 'a',
    'ำ': 'am',
    'ิ': 'i',
    'ี': 'i',
    'ึ': 'ue',
    'ื': 'ue',
    'ุ': 'u',
    'ู': 'u',
    'เ': 'e',
    'แ': 'ae',
    'โ': 'o',
    'ใ': 'ai',
    'ไ': 'ai',
    'ๅ': 'a',
    'ๆ': '',
    '็': '',
    '่': '',
    '้': '',
    '๊': '',
    '๋': '',
    '์': '',
    'ฺ': '',
    'ฯ': '',
    '฿': 'baht',
    ' ': ' ',
  };
}
