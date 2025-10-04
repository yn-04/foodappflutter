// lib/rawmaterial/widgets/category_bar.dart
// Horizontal category chips: แสดงเฉพาะหมวดที่ยังมีวัตถุดิบใช้งานได้ (count > 0)

import 'package:flutter/material.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';

class CategoryBar extends StatelessWidget {
  /// รายการชื่อหมวดหลัก “ทั้งหมด” (ถ้ามี) และลำดับที่อยากให้เรียง
  /// ใช้เพื่อ "จัดลำดับ" เท่านั้น ไม่ได้ใช้กำหนดว่าจะโชว์อะไร
  final List<String> categories;

  /// หมวดที่เลือกอยู่ตอนนี้
  final String selected;

  /// callback เมื่อเลือกหมวด
  final ValueChanged<String> onSelect;

  /// จำนวนวัตถุดิบต่อหมวดหลัก (ต้องเป็นจำนวนที่ใช้งานได้จริงแล้ว)
  /// - upstream ควรตัดรายการที่ลบแล้ว / qty<=0 / หมดอายุ ออกให้เรียบร้อย
  /// - คีย์ = ชื่อหมวดหลัก, ค่า = count ที่พร้อมใช้งาน
  final Map<String, int>? itemCountByCategory;

  const CategoryBar({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelect,
    this.itemCountByCategory,
  });

  int _getCount(Map<String, int> counts, String key) {
    final normalized = Categories.normalize(key);
    return counts[key] ??
        counts[normalized] ??
        counts[key.toLowerCase()] ??
        counts[normalized.toLowerCase()] ??
        0;
  }

  List<String> _buildVisibleCategories() {
    final counts = itemCountByCategory;
    if (counts == null || counts.isEmpty) return const <String>[];

    // 1) เลือกเฉพาะ key ที่ count > 0 เท่านั้น
    final positiveKeys = <String>[];
    counts.forEach((k, v) {
      if (v > 0) {
        positiveKeys.add(Categories.normalize(k));
      }
    });

    // ถ้าไม่มีอะไรเหลือเลย -> ไม่แสดง bar
    if (positiveKeys.isEmpty) return const <String>[];

    // 2) ใส่ "ทั้งหมด" เฉพาะเมื่อ total > 0 และผู้ใช้ต้องการมีปุ่มนี้
    final total = positiveKeys.fold<int>(0, (p, k) => p + _getCount(counts, k));
    final result = <String>[];
    if (total > 0 && categories.contains(Categories.allLabel)) {
      result.add(Categories.allLabel);
    }

    // 3) เรียงตามลำดับที่กำหนดใน `categories` ก่อน (ถ้ามี)
    final order = <String, int>{
      for (var i = 0; i < categories.length; i++)
        Categories.normalize(categories[i]): i,
    };

    // แยกสองกลุ่ม: ที่รู้จักลำดับ กับที่ไม่รู้จักลำดับ
    final known = <String>[];
    final unknown = <String>[];
    for (final k in positiveKeys.toSet()) {
      if (order.containsKey(k)) {
        known.add(k);
      } else {
        unknown.add(k);
      }
    }
    known.sort((a, b) => (order[a] ?? 0).compareTo(order[b] ?? 0));
    unknown.sort((a, b) => a.compareTo(b)); // เรียงตามตัวอักษร

    result.addAll(known);
    result.addAll(unknown);

    // 4) ไม่ “ยื้อ” หมวดที่ count = 0 อีกต่อไป (เพราะเราเลือกจาก count > 0 อยู่แล้ว)
    // ดังนั้น selected ที่ไม่มีของ จะหายไปจากแถบทันที — ตรงตามที่ต้องการ

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final counts = itemCountByCategory;
    if (counts == null || counts.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleCategories = _buildVisibleCategories();
    if (visibleCategories.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: visibleCategories.length,
        itemBuilder: (_, idx) {
          final c = visibleCategories[idx];
          final isSelected = selected == c;

          return GestureDetector(
            onTap: () => onSelect(c),
            child: Container(
              margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.black : Colors.grey[200],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? Colors.black : Colors.grey[300]!,
                ),
              ),
              child: Center(
                child: Text(
                  c,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
