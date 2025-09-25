// lib/dashboard/widgets/expiring_today_section.dart
import 'package:flutter/material.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/widgets/shopping_item_card.dart';
import 'category_card.dart';

/// ===== Top-level helpers / models =====

class _CategoryBucket {
  _CategoryBucket({required this.icon});
  final IconData icon;
  final List<ShoppingItem> items = [];
}

/// จัดกลุ่มตามหมวด โดยอาศัย Categories.normalize + iconFor
Map<String, _CategoryBucket> _groupExpiringByCategory(List<ShoppingItem> src) {
  final map = <String, _CategoryBucket>{};
  for (final it in src) {
    // ทำความสะอาดชื่อหมวด + map ให้เป็นหมวดมาตรฐาน
    final normalized = Categories.normalize(it.category);
    final key = (normalized.isEmpty) ? 'ไม่ระบุ' : normalized;
    final icon = Categories.iconFor(key);

    map.putIfAbsent(key, () => _CategoryBucket(icon: icon));
    map[key]!.items.add(it);
  }
  // เรียงกลุ่มตามจำนวนมาก→น้อย
  final entries = map.entries.toList()
    ..sort((a, b) => b.value.items.length.compareTo(a.value.items.length));
  return Map.fromEntries(entries);
}

void _showCategorySheet(
  BuildContext context,
  String category,
  List<ShoppingItem> items,
) {
  final cs = Theme.of(context).colorScheme;

  // เรียงรายการ: เหลือวันน้อยก่อน
  final sorted = [...items]
    ..sort((a, b) {
      final da = a.daysLeft ?? 9999;
      final db = b.daysLeft ?? 9999;
      return da.compareTo(db);
    });

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final double maxHeight =
          MediaQuery.of(ctx).size.height * 0.7; // สูงสุด 70%
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Padding(
            padding: const EdgeInsets.only(
              top: 12,
              left: 16,
              right: 16,
              bottom: 10,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outline.withAlpha(120),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Categories.iconFor(category), color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'รายการหมดอายุวันนี้: $category',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '${sorted.length} รายการ',
                      style: TextStyle(color: cs.onSurface.withAlpha(153)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: sorted.length,
                    itemBuilder: (_, i) {
                      final it = sorted[i];
                      return ShoppingItemCard(item: it);
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// ===== Widget =====

/// การ์ด “หมดอายุวันนี้” แสดงเป็นหมวดหมู่ + จำนวน และกดเพื่อดูรายการในหมวด (popup)
class ExpiringTodaySection extends StatelessWidget {
  const ExpiringTodaySection({
    super.key,
    required this.items, // รายการที่ daysLeft == 0
    this.title = 'หมดอายุวันนี้',
    this.countSuffix = ' รายการ',
    this.emptyText = 'วันนี้ยังไม่มีวัตถุดิบที่จะหมดอายุ',
  });

  final List<ShoppingItem> items;
  final String title;
  final String countSuffix;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grouped = _groupExpiringByCategory(items);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((255 * 0.05).round()),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // หัวการ์ด
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${items.length}$countSuffix',
                    style: TextStyle(
                      fontSize: 14,
                      color: cs.onSurface.withAlpha(153),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha((255 * 0.12).round()),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.notifications_active_outlined,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // เนื้อหา
          if (items.isEmpty)
            _emptyPlaceholder(context, emptyText)
          else
            SizedBox(
              height: 128, // กันล้นแนวตั้งของการ์ด
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: grouped.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) {
                  final entry = grouped.entries.elementAt(i);
                  final catKey = entry.key;
                  final bucket = entry.value;

                  return CategoryCard(
                    title: catKey, // ใช้ชื่อหมวดจาก Categories.normalize แล้ว
                    count: bucket.items.length,
                    icon: bucket.icon,
                    onTap: () => _showCategorySheet(ctx, catKey, bucket.items),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyPlaceholder(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha((255 * 0.18).round()),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: cs.onSurface.withAlpha(166),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
