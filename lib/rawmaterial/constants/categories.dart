// lib/rawmaterial/constants/categories.dart
// ยูทิลิตี้จัดการรายชื่อหมวดหมู่ + หมวดย่อย

import 'package:flutter/material.dart';

import 'package:my_app/rawmaterial/constants/shelf_life_dataset.dart';

class Categories {
  static const String allLabel = 'ทั้งหมด';

  static final Map<String, List<String>> _categoryToSubcategories =
      _buildCategoryMap();

  static final List<String> list = List.unmodifiable(
    _categoryToSubcategories.keys.toList()..sort((a, b) => a.compareTo(b)),
  );

  static const IconData _defaultIcon = Icons.category_outlined;

  // ใช้ normalize ทั้งกับข้อความที่ผู้ใช้พิมพ์ และตอนสร้างดัชนีค้นหา
  static final RegExp _normalizePattern = RegExp(r'[\s\-_/()]+');

  /// ดัชนีไอเท็ม (normalize แล้ว) -> รายการหมวดย่อย (เหมือน shelfLifeItemIndex แต่ค้นหาแม่นกว่า)
  static final Map<String, List<String>> _normalizedItemIndex = () {
    final out = <String, List<String>>{};
    for (final entry in shelfLifeItemIndex.entries) {
      final key = _normalizeKey(entry.key);
      out[key] = entry.value;
    }
    return out;
  }();

  static String _normalizeKey(String input) =>
      input.trim().toLowerCase().replaceAll(_normalizePattern, '');

  static Map<String, List<String>> _buildCategoryMap() {
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

  /// ส่งรายการหมวดทั้งหมด โดยมี "ทั้งหมด" อยู่หัวรายการ
  static List<String> withAll([List<String>? extras]) {
    final set = <String>{...list, ...?extras};
    return [allLabel, ...set.toList()..sort((a, b) => a.compareTo(b))];
  }

  static bool isKnown(String category) => list.contains(category);

  /// คืนชื่อหมวดที่ตรงกับที่ระบบรู้จัก (case-insensitive) ถ้าไม่รู้จักคืนค่าดั้งเดิม
  static String normalize(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return value;
    if (isKnown(value) || value == allLabel) return value;
    for (final existing in list) {
      if (existing.toLowerCase() == value.toLowerCase()) return existing;
    }
    return value;
  }

  /// คืนรายการหมวดย่อยของหมวด
  static List<String> subcategoriesOf(String category) {
    final normalized = normalize(category);
    return _categoryToSubcategories[normalized] ?? const <String>[];
  }

  /// คืนหมวดย่อยแรกของหมวดนั้น ๆ (ใช้เป็นค่าเริ่มต้น)
  static String? defaultSubcategoryFor(String? category) {
    if (category == null) return null;
    final subs = subcategoriesOf(category);
    if (subs.isEmpty) return null;
    return subs.first;
  }

  /// หา "หมวดหลัก" จากชื่อหมวดย่อย
  static String? categoryForSubcategory(String? subcategory) {
    if (subcategory == null || subcategory.trim().isEmpty) return null;
    final target = subcategory.trim();
    for (final entry in _categoryToSubcategories.entries) {
      if (entry.value.contains(target)) return entry.key;
      for (final value in entry.value) {
        if (value.toLowerCase() == target.toLowerCase()) return entry.key;
      }
    }
    return null;
  }

  /// ตรวจหมวด/หมวดย่อยจากชื่อที่ผู้ใช้พิมพ์
  static Map<String, String?> autoDetect(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return {'category': null, 'subcategory': null};

    // 1) พยายามหาแม่นยำจากดัชนี normalize แล้วก่อน
    final normalized = _normalizeKey(cleaned);
    final matches = _normalizedItemIndex[normalized];
    if (matches != null && matches.isNotEmpty) {
      final sub = matches.first;
      return {'category': categoryForSubcategory(sub), 'subcategory': sub};
    }

    // 2) เผื่อชื่อหมวดถูกพิมพ์ติดมากับชื่อวัตถุดิบ เช่น "ผักผลไม้สด - แอปเปิ้ล"
    for (final entry in _categoryToSubcategories.entries) {
      if (cleaned.contains(entry.key)) {
        return {
          'category': entry.key,
          'subcategory': defaultSubcategoryFor(entry.key),
        };
      }
    }

    return {'category': null, 'subcategory': null};
  }

  /// ไอคอนสำหรับชื่อหมวดที่ "ตรงกับ dataset ปัจจุบัน"
  static IconData iconFor(String category) {
    switch (normalize(category)) {
      case 'ผักผลไม้สด':
        return Icons.eco;
      case 'เนื้อสัตว์/อาหารทะเล':
        return Icons.set_meal;
      case 'นม/ชีส/ไข่':
        return Icons.egg_alt_outlined;
      case 'ของแห้ง/เครื่องปรุง':
        return Icons.rice_bowl;
      case 'กับข้าว/พร้อมทาน':
        return Icons.restaurant_menu;
      case 'เบเกอรี่/ขนม':
        return Icons.bakery_dining;
      case 'เครื่องดื่ม':
        return Icons.local_drink_outlined;
      case 'น้ำมัน':
        return Icons.oil_barrel;
      default:
        return _defaultIcon;
    }
  }
}
