// lib/rawmaterial/widgets/category_bar.dart
import 'package:flutter/material.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';

class CategoryBar extends StatelessWidget {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;
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

    final positiveKeys = <String>[];
    counts.forEach((k, v) {
      if (v > 0) positiveKeys.add(Categories.normalize(k));
    });
    if (positiveKeys.isEmpty) return const <String>[];

    final total = positiveKeys.fold<int>(0, (p, k) => p + _getCount(counts, k));
    final result = <String>[];
    if (total > 0 && categories.contains(Categories.allLabel)) {
      result.add(Categories.allLabel);
    }

    final order = <String, int>{
      for (var i = 0; i < categories.length; i++)
        Categories.normalize(categories[i]): i,
    };

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
    unknown.sort((a, b) => a.compareTo(b));

    result.addAll(known);
    result.addAll(unknown);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final counts = itemCountByCategory;
    if (counts == null || counts.isEmpty) return const SizedBox.shrink();

    final visibleCategories = _buildVisibleCategories();
    if (visibleCategories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: visibleCategories.length,
        itemBuilder: (_, idx) {
          final c = visibleCategories[idx];
          final isSelected = selected == c;
          final color = Categories.colorFor(c);
          final fillColor = color.withAlpha(
            (255 * (isSelected ? 0.24 : 0.08)).round(),
          );
          final borderColor = color.withAlpha(
            (255 * (isSelected ? 0.8 : 0.25)).round(),
          );

          return GestureDetector(
            onTap: () => onSelect(c),
            child: Container(
              margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: 1.4),
              ),
              child: Row(
                children: [
                  Icon(Categories.iconFor(c), size: 18, color: color),
                  const SizedBox(width: 6),
                  Text(
                    c,
                    style: const TextStyle(
                      color: Colors.black, // ✅ ตัวหนังสือสีดำ
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
