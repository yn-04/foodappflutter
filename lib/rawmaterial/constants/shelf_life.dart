// lib/rawmaterial/constants/shelf_life.dart
// ข้อมูล Shelf Life และ helper functions สำหรับระบบเพิ่มวัตถุดิบ

import 'package:my_app/rawmaterial/constants/shelf_life_dataset.dart';

class ShelfLifeRange {
  const ShelfLifeRange({required this.minDays, required this.maxDays});

  final int minDays;
  final int maxDays;

  Duration get minDuration => Duration(days: minDays);
  Duration get maxDuration => Duration(days: maxDays);
  bool get hasMeaning => maxDays > 0;
}

class ShelfLifeEntry {
  const ShelfLifeEntry({
    required this.category,
    this.room,
    this.fridge,
    this.freezer,
    required this.items,
  });

  final String category;
  final ShelfLifeRange? room;
  final ShelfLifeRange? fridge;
  final ShelfLifeRange? freezer;
  final Map<String, String> items;

  factory ShelfLifeEntry.fromRaw(Map<String, Object?> raw) {
    ShelfLifeRange? parseRange(String key) {
      final value = (raw['storage'] as Map?)?[key];
      if (value is List && value.isNotEmpty) {
        final list = value.cast<int>();
        final minDays = list.first;
        final maxDays = list.length > 1 ? list.last : list.first;
        return ShelfLifeRange(minDays: minDays, maxDays: maxDays);
      }
      return null;
    }

    final mappedItems = <String, String>{};
    final itemsRaw = raw['items'];
    if (itemsRaw is Map) {
      itemsRaw.forEach((key, value) {
        final name = key?.toString().trim() ?? '';
        if (name.isEmpty) return;
        final unit = value?.toString().trim() ?? '';
        mappedItems[name] = unit;
      });
    }

    return ShelfLifeEntry(
      category: (raw['category'] as String?)?.trim() ?? '',
      room: parseRange('room'),
      fridge: parseRange('fridge'),
      freezer: parseRange('freezer'),
      items: Map.unmodifiable(mappedItems),
    );
  }
}

class ShelfLife {
  static final Map<String, ShelfLifeEntry> _entries = Map.unmodifiable({
    for (final entry in shelfLifeSubcategoryData.entries)
      entry.key: ShelfLifeEntry.fromRaw(entry.value),
  });

  static final Map<String, List<String>> _normalizedItemIndex =
      Map.unmodifiable({
        for (final entry in shelfLifeItemIndex.entries)
          entry.key: List.unmodifiable(entry.value),
      });

  static final Map<String, String> _exactItemToSubcategory = Map.unmodifiable({
    for (final entry in _entries.entries)
      for (final item in entry.value.items.keys) item: entry.key,
  });

  static final Map<String, String> _itemUnits = Map.unmodifiable({
    for (final entry in _entries.values)
      for (final item in entry.items.entries)
        if (item.value.isNotEmpty) item.key: item.value,
  });

  static final RegExp _normalizePattern = RegExp(r'[\s\-_/()]+');
  static ShelfLifeEntry? entry(String? subcategory) {
    if (subcategory == null || subcategory.trim().isEmpty) return null;
    return _entries[subcategory.trim()];
  }

  static Duration? forFridge(String? subcategory) =>
      entry(subcategory)?.fridge?.maxDuration;
  static Duration? forFreezer(String? subcategory) =>
      entry(subcategory)?.freezer?.maxDuration;
  static Duration? forRoom(String? subcategory) =>
      entry(subcategory)?.room?.maxDuration;

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(_normalizePattern, '');

  static String? detectSubcategory(String? itemName) {
    if (itemName == null || itemName.trim().isEmpty) return null;
    final normalized = _normalize(itemName);
    if (normalized.isEmpty) return null;
    final matches = _normalizedItemIndex[normalized];
    if (matches == null || matches.isEmpty) return null;
    return matches.first;
  }

  static String? subcategoryForItem(String? itemName) {
    if (itemName == null || itemName.trim().isEmpty) return null;
    final trimmed = itemName.trim();
    final exact = _exactItemToSubcategory[trimmed];
    if (exact != null) return exact;
    final detected = detectSubcategory(trimmed);
    if (detected != null) return detected;

    final normalized = _normalize(trimmed);
    for (final entry in _entries.entries) {
      for (final item in entry.value.items.keys) {
        if (_normalize(item) == normalized) return entry.key;
      }
    }
    return null;
  }

  static String? defaultUnitForItem(String? itemName) {
    if (itemName == null || itemName.trim().isEmpty) return null;
    final trimmed = itemName.trim();
    final direct = _itemUnits[trimmed];
    if (direct != null && direct.isNotEmpty) return direct;

    final sub = subcategoryForItem(trimmed);
    if (sub == null) return null;
    final entry = _entries[sub];
    if (entry == null) return null;

    final normalized = _normalize(trimmed);
    for (final item in entry.items.entries) {
      if (item.value.isEmpty) continue;
      if (_normalize(item.key) == normalized) {
        return item.value;
      }
    }
    return null;
  }

  static List<String> get dictionaryTerms {
    final set = <String>{..._entries.keys};
    for (final entry in _entries.values) {
      set.addAll(entry.items.keys);
    }
    final list = set.toList()..sort((a, b) => a.compareTo(b));
    return List.unmodifiable(list);
  }

  static String formatDuration(Duration duration) {
    final days = duration.inDays;
    if (days >= 365 && days % 365 == 0) {
      final years = days ~/ 365;
      return years > 1 ? '$years ปี' : '1 ปี';
    }
    if (days >= 30 && days % 30 == 0) {
      final months = days ~/ 30;
      return months > 1 ? '$months เดือน' : '1 เดือน';
    }
    if (days >= 7 && days % 7 == 0) {
      final weeks = days ~/ 7;
      return weeks > 1 ? '$weeks สัปดาห์' : '1 สัปดาห์';
    }
    if (days <= 1) {
      return days <= 0 ? 'ภายในวันนี้' : '1 วัน';
    }
    return '$days วัน';
  }

  static List<String> storageGuidance({String? category, String? subcategory}) {
    final key = subcategory?.trim().isNotEmpty == true
        ? subcategory!.trim()
        : CategoriesHelper.defaultSubcategoryForCategory(category);
    if (key == null || key.isEmpty) return const [];
    final entry = _entries[key];
    if (entry == null) return const [];

    final tips = <String>[];
    void addTip(String label, ShelfLifeRange? range) {
      if (range == null) return;
      tips.add(
        range.hasMeaning
            ? '$label ~${formatDuration(range.maxDuration)}'
            : '$label: ควรใช้ทันทีหรือไม่เหมาะกับโหมดนี้',
      );
    }

    addTip('ครัว', entry.room);
    addTip('ตู้เย็น', entry.fridge);
    addTip('ช่องแช่แข็ง', entry.freezer);
    return tips;
  }
}

class CategoriesHelper {
  static final Map<String, List<String>> categoryToSubcategories =
      Map.unmodifiable(_buildMap());

  static Map<String, List<String>> _buildMap() {
    final map = <String, Set<String>>{};
    for (final entry in shelfLifeSubcategoryData.entries) {
      final category = (entry.value['category'] as String?)?.trim();
      if (category == null || category.isEmpty) continue;
      map.putIfAbsent(category, () => <String>{}).add(entry.key);
    }
    return {
      for (final e in map.entries)
        e.key: List.unmodifiable(
          e.value.toList()..sort((a, b) => a.compareTo(b)),
        ),
    };
  }

  static String? defaultSubcategoryForCategory(String? category) {
    if (category == null) return null;
    final subs = categoryToSubcategories[category.trim()];
    if (subs == null || subs.isEmpty) return null;
    return subs.first;
  }

  static String? categoryForSubcategory(String? subcategory) {
    if (subcategory == null || subcategory.trim().isEmpty) return null;
    final target = subcategory.trim();
    for (final entry in categoryToSubcategories.entries) {
      if (entry.value.contains(target)) return entry.key;
      for (final value in entry.value) {
        if (value.toLowerCase() == target.toLowerCase()) return entry.key;
      }
    }
    return null;
  }
}
