import 'package:flutter/material.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';

class InventorySummarySection extends StatelessWidget {
  const InventorySummarySection({
    super.key,
    required this.totalItems,
    required this.counts, // Map<หมวด, จำนวน>
    required this.topCategory, // หมวดที่มากที่สุด (อาจเป็น null เมื่อว่าง)
    this.title = 'สรุปคลังวัตถุดิบ',
    this.hint = 'จำนวนรายการในแต่ละหมวด',
    this.viewAllText = 'ดูรายละเอียด',
    this.maxBars = 8, // แสดงท็อป N หมวด (ป้องกันยืดยาวเกิน)
  });

  final int totalItems;
  final Map<String, int> counts;
  final String? topCategory;

  final String title;
  final String hint;
  final String viewAllText;
  final int maxBars;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // สร้างรายการหมวดเรียงมาก→น้อย
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final shown = entries.take(maxBars).toList();
    final maxVal = (shown.isEmpty) ? 0 : shown.first.value;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((255 * 0.05).round()),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // หัวเรื่อง + ปุ่มดูทั้งหมด
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              TextButton(
                onPressed: () {
                  _showAllCategories(context, entries);
                },
                child: Text(viewAllText, style: TextStyle(color: cs.primary)),
              ),
            ],
          ),

          // hint
          Text(
            hint,
            style: TextStyle(fontSize: 13, color: cs.onSurface.withAlpha(153)),
          ),
          const SizedBox(height: 12),

          // กราฟแท่งแนวนอน (top N)
          if (shown.isEmpty)
            _emptyPlaceholder(context)
          else
            Column(
              children: [
                for (final e in shown) ...[
                  _BarRow(label: e.key, value: e.value, maxValue: maxVal),
                  const SizedBox(height: 10),
                ],
              ],
            ),

          const SizedBox(height: 8),

          // สรุปหมวดมากที่สุด
          _TopCategorySummary(
            topCategory: topCategory,
            count: (topCategory == null) ? 0 : (counts[topCategory] ?? 0),
            total: totalItems,
          ),
        ],
      ),
    );
  }

  Widget _emptyPlaceholder(BuildContext context) {
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
          Icon(Icons.bar_chart, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            'ยังไม่มีข้อมูลหมวดหมู่',
            style: TextStyle(
              color: cs.onSurface.withAlpha(166),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showAllCategories(
    BuildContext context,
    List<MapEntry<String, int>> entries,
  ) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final sorted = [...entries];
        return SafeArea(
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
                    const Icon(Icons.bar_chart),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'หมวดหมู่ทั้งหมด',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '${sorted.length} หมวด',
                      style: TextStyle(color: cs.onSurface.withAlpha(153)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sorted.length,
                    separatorBuilder: (context, _) =>
                        Divider(color: cs.outlineVariant.withAlpha(80)),
                    itemBuilder: (context, i) {
                      final e = sorted[i];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: cs.primary.withAlpha(
                            (255 * 0.10).round(),
                          ),
                          child: Icon(
                            Categories.iconFor(e.key),
                            color: cs.primary,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: Text(
                          '${e.value} รายการ',
                          style: TextStyle(color: cs.onSurface.withAlpha(180)),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// แถวกราฟแท่งแนวนอน
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.maxValue,
  });

  final String label;
  final int value;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        // ไอคอน + ป้ายหมวด
        SizedBox(
          width: 120, // กว้างพอสำหรับป้าย (กันล้น)
          child: Row(
            children: [
              Icon(Categories.iconFor(label), color: cs.primary, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),

        // แถบกราฟยืดตามพื้นที่
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final totalW = constraints.maxWidth;
              final ratio = (maxValue == 0) ? 0.0 : (value / maxValue);
              final barW = (totalW * ratio).clamp(4.0, totalW);

              return Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withAlpha(
                        (255 * 0.14).round(),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 14,
                    width: barW,
                    decoration: BoxDecoration(
                      color: cs.primary.withAlpha((255 * 0.65).round()),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(width: 10),

        // จำนวนรายการ
        SizedBox(
          width: 56,
          child: Text(
            '$value รายการ',
            textAlign: TextAlign.right,
            style: TextStyle(
              color: cs.onSurface.withAlpha(190),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// สรุปหมวดมากที่สุด
class _TopCategorySummary extends StatelessWidget {
  const _TopCategorySummary({
    required this.topCategory,
    required this.count,
    required this.total,
  });

  final String? topCategory;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (topCategory == null || total == 0) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'ยังไม่มีข้อมูลหมวดที่มากที่สุด',
          style: TextStyle(color: cs.onSurface.withAlpha(160)),
        ),
      );
    }

    final percent = (count / total * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.emoji_events_outlined, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'หมวดที่มีมากที่สุด: $topCategory ($count รายการ • ~$percent%)',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
