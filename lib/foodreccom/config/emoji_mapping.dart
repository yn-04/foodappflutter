// lib/config/emoji_mapping.dart
class EmojiMapping {
  static final Map<String, String> ingredientEmoji = {
    // ธัญพืช/แป้ง
    'ข้าว': '🍚',
    'ขนมปัง': '🍞',
    'เส้น': '🍜',
    'ก๋วยเตี๋ยว': '🍜',

    // โปรตีน
    'ไข่': '🥚',
    'ไก่': '🍗',
    'หมู': '🥩',
    'เนื้อ': '🥩',
    'ปลา': '🐟',
    'กุ้ง': '🦐',
    'ปู': '🦀',
    'ปลาหมึก': '🦑',

    // ผัก
    'ผัก': '🥦',
    'คะน้า': '🥬',
    'กะหล่ำ': '🥬',
    'กุยช่าย': '🥬',
    'แตงกวา': '🥒',
    'มะเขือเทศ': '🍅',
    'กะเพรา': '🌿',
    'โหระพา': '🌿',
    'กระเทียม': '🧄',
    'หอม': '🧅',
    'พริก': '🌶️',

    // ผลไม้
    'มะนาว': '🍋',
    'มะม่วง': '🥭',
    'มะพร้าว': '🥥',
    'ส้ม': '🍊',
    'กล้วย': '🍌',

    // dairy
    'ชีส': '🧀',
    'นม': '🥛',
    'เนย': '🧈',
  };

  static String getEmoji(String name) {
    final lower = name.toLowerCase();
    for (final entry in ingredientEmoji.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }
    return '🥢'; // default
  }
}
