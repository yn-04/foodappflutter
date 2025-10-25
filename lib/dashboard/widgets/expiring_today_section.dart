// lib/dashboard/widgets/expiring_today_section.dart
import 'package:flutter/material.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';

/// แสดงวัตถุดิบที่หมดอายุวันนี้ (แนวนอน เลื่อนซ้าย–ขวา)
/// - มองเห็น "3 ใบพร้อมกัน" โดยคำนวณความกว้างต่อใบจากพื้นที่จริง
/// - เอาป้าย "หมดอายุวันนี้/เหลืออีก X วัน" ออกตามที่ขอ
/// - ปุ่ม "ดู Insight" อยู่ล่างสุด และข้อความ Insight เป็นพื้นขาวล้วน
class ExpiringTodaySection extends StatefulWidget {
  const ExpiringTodaySection({
    super.key,
    required this.items,
    this.insightFooter,
  });

  final List<ShoppingItem> items;
  final Widget? insightFooter;

  @override
  State<ExpiringTodaySection> createState() => _ExpiringTodaySectionState();
}

class _ExpiringTodaySectionState extends State<ExpiringTodaySection> {
  bool _insightExpanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // เรียงตามวันหมดอายุ (วันก่อน -> วันหลัง)
    final sorted = List<ShoppingItem>.from(widget.items)
      ..sort((a, b) => _compareExpiry(a.expiryDate, b.expiryDate));
    final hasData = sorted.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.error.withAlpha((255 * 0.18).round())),
        boxShadow: [
          BoxShadow(
            color: cs.error.withAlpha((255 * 0.08).round()),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(count: sorted.length),
          const SizedBox(height: 12),

          if (!hasData)
            const _EmptyState()
          else
            // ======= แนวนอน เลื่อนซ้าย–ขวา เห็น 3 ใบพร้อมกัน =======
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                // ให้เห็น 3 ใบพร้อมกัน -> 3*cardWidth + 2*spacing = maxWidth
                final cardWidth = (constraints.maxWidth - 2 * spacing) / 3;

                return SizedBox(
                  height: 150, // ปรับได้ 140–170 ตามฟอนต์/ดีไวซ์
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    physics: const BouncingScrollPhysics(),
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const SizedBox(width: spacing),
                    itemBuilder: (context, index) {
                      final item = sorted[index];
                      return SizedBox(
                        width: cardWidth,
                        child: _ExpiringHorizontalCard(
                          item: item,
                          highlight: index == 0, // ใบแรกไฮไลท์เบา ๆ
                        ),
                      );
                    },
                  ),
                );
              },
            ),

          // ====== ปุ่ม "ดู Insight" ล่างสุดของการ์ด ======
          if (widget.insightFooter != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _insightExpanded = !_insightExpanded),
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  _insightExpanded
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
                label: Text(
                  _insightExpanded ? 'ซ่อน Insight' : 'ดู Insight',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            // ====== ข้อความ Insight "พื้นโปร่ง ไม่มีสี/กรอบ" ======
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) {
                return ClipRect(
                  child: FadeTransition(
                    opacity: anim,
                    child: SizeTransition(
                      sizeFactor: anim,
                      axisAlignment: -1.0, // กางจากด้านบน
                      child: child,
                    ),
                  ),
                );
              },
              child: _insightExpanded
                  ? Padding(
                      key: const ValueKey('expiring_today_insight.open'),
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                      // ใช้ Theme ครอบกัน divider/พื้นในลูกให้โปร่งด้วย
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          cardColor: Colors.transparent,
                          canvasColor: Colors.transparent,
                          dividerColor: Colors.transparent,
                        ),
                        child: widget.insightFooter!,
                      ),
                    )
                  : const SizedBox(
                      key: ValueKey('expiring_today_insight.closed'),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  static int _compareExpiry(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    final dateA = DateTime(a.year, a.month, a.day);
    final dateB = DateTime(b.year, b.month, b.day);
    return dateA.compareTo(dateB);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final subtitle = count == 0
        ? 'วันนี้ยังไม่มีวัตถุดิบที่จะหมดอายุ'
        : 'จัดการให้ทันก่อนเสียของนะ';

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.error.withAlpha((255 * 0.14).round()),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(Icons.warning_amber_rounded, color: cs.error, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'วัตถุดิบที่หมดอายุวันนี้',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: cs.error.withAlpha((255 * 0.12).round()),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            '$count รายการ',
            style: TextStyle(color: cs.error, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha((255 * 0.16).round()),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outline.withAlpha((255 * 0.18).round())),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outlined, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'วันนี้ยังไม่มีวัตถุดิบที่หมดอายุ จัดสต็อกสบายใจได้เลย',
              style: TextStyle(
                color: cs.onSurface.withAlpha((255 * 0.8).round()),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// การ์ดแนวนอน (ไม่มีป้ายวันหมดอายุ)
class _ExpiringHorizontalCard extends StatelessWidget {
  const _ExpiringHorizontalCard({required this.item, this.highlight = false});

  final ShoppingItem item;
  final bool highlight;

  @override
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final category = Categories.normalize(item.category.trim());
    final categoryColor = Categories.colorFor(category);
    final highlightColor = cs.error;

    final accent = highlight ? highlightColor : categoryColor;
    final background = highlight
        ? highlightColor.withAlpha((255 * 0.10).round())
        : cs.surfaceContainerHighest.withAlpha((255 * 0.15).round());
    final borderColor = highlight
        ? highlightColor.withAlpha((255 * 0.25).round())
        : cs.outline.withAlpha((255 * 0.16).round());

    final quantityText = _quantityText(item);
    final categoryLabel = category.isEmpty ? 'ไม่ระบุหมวด' : category;

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ไอคอน + ชื่อ (ชื่อ 2 บรรทัด + ellipsis)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 2, // << สองบรรทัด
                  overflow: TextOverflow.ellipsis, // << ellipsis
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    fontSize: 14.5,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          // ปริมาณ (แยกบรรทัด)
          Text(
            quantityText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 6),

          // ชิปหมวดหมู่ (แยกบรรทัดของตัวเอง)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withAlpha((255 * 0.22).round()),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: cs.outline.withAlpha((255 * 0.16).round()),
              ),
            ),
            child: Text(
              categoryLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface.withAlpha((255 * 0.80).round()),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          const Spacer(),
          // (เอาป้ายวันหมดอายุออกตามที่ตกลง)
        ],
      ),
    );
  }

  static String _quantityText(ShoppingItem item) {
    final unit = item.unit.trim();
    if (item.quantity <= 0 && unit.isEmpty) {
      return 'ไม่ระบุปริมาณ';
    }
    if (item.quantity <= 0) {
      return unit;
    }
    if (unit.isEmpty) {
      return '${item.quantity} หน่วย';
    }
    return '${item.quantity} $unit';
  }
}
