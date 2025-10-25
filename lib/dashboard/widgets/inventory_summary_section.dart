//lib/dashboard/widgets/inventory_summary_section.dart
import 'package:flutter/material.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InventorySummarySection extends StatelessWidget {
  const InventorySummarySection({
    super.key,
    required this.totalItems,
    required this.counts, // Map<หมวด, จำนวน>
    required this.latestAdded, // Map<หมวด, เวลาที่เพิ่มล่าสุด>
    required this.topCategory, // หมวดที่มากที่สุด (อาจเป็น null เมื่อว่าง)
    this.title = 'หมวดหมู่และวัตถุดิบทั้งหมด',
    this.hint = 'จำนวนรายการวัตถุดิบในแต่ละหมวดหมู่',
    this.viewAllText = 'ดูรายละเอียด',
    this.inlineInsight,
  });

  final int totalItems;
  final Map<String, int> counts;
  final Map<String, DateTime?> latestAdded;
  final String? topCategory;

  final String title;
  final String hint;
  final String viewAllText;
  final Widget? inlineInsight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // สร้างรายการหมวดเรียงตามเวลาที่เพิ่มล่าสุด
    final entries = counts.entries.toList()..sort(_compareEntries);

    final hasData = entries.isNotEmpty;

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

          // แสดงหมวดทั้งหมดในสต็อกแบบเลื่อนเหมือนเมนูแนะนำ
          if (!hasData)
            _emptyPlaceholder(context)
          else
            SizedBox(
              height: 160,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final e = entries[index];
                  final categoryColor = Categories.colorFor(e.key);
                  return _CategoryChip(
                    category: e.key,
                    count: e.value,
                    color: categoryColor,
                    onTap: () => _showCategoryDetail(context, e.key),
                  );
                },
              ),
            ),
          if (inlineInsight != null) ...[
            const SizedBox(height: 12),
            inlineInsight!,
          ],
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
        final sorted = [...entries]..sort(_compareEntries);
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
                      final accent = Categories.colorFor(e.key);
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: accent.withAlpha(
                            (255 * 0.10).round(),
                          ),
                          child: Icon(
                            Categories.iconFor(e.key),
                            color: accent,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          e.key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: Text(
                          '${e.value} รายการ',
                          style: TextStyle(color: cs.onSurface.withAlpha(180)),
                        ),
                        onTap: () => _showCategoryDetail(context, e.key),
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

  int _compareEntries(MapEntry<String, int> a, MapEntry<String, int> b) {
    final da = latestAdded[a.key];
    final db = latestAdded[b.key];
    if (da != null && db != null) {
      final cmp = db.compareTo(da);
      if (cmp != 0) return cmp;
    } else if (da != null) {
      return -1;
    } else if (db != null) {
      return 1;
    }
    final countCmp = b.value.compareTo(a.value);
    if (countCmp != 0) return countCmp;
    return a.key.compareTo(b.key);
  }

  void _showCategoryDetail(BuildContext context, String category) {
    final cs = Theme.of(context).colorScheme;
    final accent = Categories.colorFor(category);
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.75;
        return SafeArea(
          child: SizedBox(
            height: maxHeight,
            child: Padding(
              padding: const EdgeInsets.only(
                top: 12,
                left: 16,
                right: 16,
                bottom: 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outline.withAlpha(120),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Categories.iconFor(category), color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'วัตถุดิบในหมวด: $category',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<List<_IngredientQty>>(
                      future: _fetchIngredientsInCategory(category),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'เกิดข้อผิดพลาด: ${snapshot.error}',
                              style: TextStyle(color: cs.error),
                            ),
                          );
                        }
                        final items = snapshot.data ?? [];
                        if (items.isEmpty) {
                          return Center(
                            child: Text(
                              'ไม่มีวัตถุดิบในหมวดนี้',
                              style: TextStyle(
                                color: cs.onSurface.withAlpha(160),
                              ),
                            ),
                          );
                        }

                        // เรียงตามวันหมดอายุ (น้อยไปมาก), null ไว้ท้าย
                        final sorted = [...items]
                          ..sort((a, b) {
                            final ad = a.expiryDate;
                            final bd = b.expiryDate;
                            if (ad == null && bd == null) return 0;
                            if (ad == null) return 1;
                            if (bd == null) return -1;
                            return ad.compareTo(bd);
                          });

                        return ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: sorted.length,
                          separatorBuilder: (_, __) =>
                              Divider(color: cs.outlineVariant.withAlpha(60)),
                          itemBuilder: (context, i) {
                            final ing = sorted[i];
                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              title: Text(
                                ing.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                              subtitle: ing.expiryDate == null
                                  ? null
                                  : Text(
                                      _expirySubtitle(ing.expiryDate!),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurface.withAlpha(150),
                                      ),
                                    ),
                              trailing: Text(
                                _formatQty(ing.quantity, ing.unit),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<List<_IngredientQty>> _fetchIngredientsInCategory(
    String category,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('raw_materials')
        .where('category', isEqualTo: category)
        .get();
    // รวมรายการชื่อเดียวกันเข้าด้วยกัน (รองรับ g/kg, ml/l)
    final agg = <String, _Agg>{};
    for (final d in snap.docs) {
      final data = d.data();
      final rawName = (data['name'] ?? '').toString();
      final name = rawName.trim();
      if (name.isEmpty) continue;
      final unit = (data['unit'] ?? '').toString().trim();
      final q = data['quantity'];
      final qtyInt = (q is int)
          ? q
          : (q is double)
          ? q.round()
          : int.tryParse(q?.toString() ?? '') ?? 0;
      if (qtyInt <= 0) continue; // กรองจำนวน = 0 ออก
      // กรองวัตถุดิบที่หมดอายุออกจากรายละเอียดหมวด
      final edRaw = data['expiry_date'];
      final ed = _toDateTime(edRaw);
      final isExpired = ed == null ? false : _dateOnly(ed).isBefore(_today());
      if (isExpired) continue;

      final keyName = name.toLowerCase();
      final group = _unitGroup(unit);
      final key = group == _UnitGroup.other
          ? '$keyName|unit:$unit'
          : '$keyName|$group';
      final canonicalAdd = _toCanonical(qtyInt, unit);
      final current = agg[key];
      if (current == null) {
        agg[key] = _Agg(
          label: name,
          group: group,
          canonicalQty: canonicalAdd,
          groupUnit: group == _UnitGroup.other ? unit : null,
          minExpiry: ed,
        );
      } else {
        current.canonicalQty += canonicalAdd;
        if (ed != null) {
          if (current.minExpiry == null || ed.isBefore(current.minExpiry!)) {
            current.minExpiry = ed;
          }
        }
      }
    }

    final list = <_IngredientQty>[];
    for (final entry in agg.values) {
      switch (entry.group) {
        case _UnitGroup.mass:
          final grams = entry.canonicalQty;
          if (grams % 1000 == 0) {
            list.add(
              _IngredientQty(
                name: entry.label,
                quantity: (grams / 1000).toDouble(),
                unit: 'กิโลกรัม',
                expiryDate: entry.minExpiry,
              ),
            );
          } else {
            list.add(
              _IngredientQty(
                name: entry.label,
                quantity: grams.toDouble(),
                unit: 'กรัม',
                expiryDate: entry.minExpiry,
              ),
            );
          }
          break;
        case _UnitGroup.volume:
          final ml = entry.canonicalQty;
          if (ml % 1000 == 0) {
            list.add(
              _IngredientQty(
                name: entry.label,
                quantity: (ml / 1000).toDouble(),
                unit: 'ลิตร',
                expiryDate: entry.minExpiry,
              ),
            );
          } else {
            list.add(
              _IngredientQty(
                name: entry.label,
                quantity: ml.toDouble(),
                unit: 'มิลลิลิตร',
                expiryDate: entry.minExpiry,
              ),
            );
          }
          break;
        default:
          // หน่วยอื่น ๆ รวมเฉพาะหน่วยเดียวกัน (ตาม key แล้ว)
          list.add(
            _IngredientQty(
              name: entry.label,
              quantity: entry.canonicalQty.toDouble(),
              unit: entry.groupUnit ?? '',
              expiryDate: entry.minExpiry,
            ),
          );
      }
    }

    // เรียงโดยวันหมดอายุ (น้อยไปมาก), null ท้าย
    list.sort((a, b) {
      final ad = a.expiryDate;
      final bd = b.expiryDate;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });
    return list;
  }
}

class _IngredientQty {
  final String name;
  final double quantity;
  final String unit;
  final DateTime? expiryDate;
  _IngredientQty({
    required this.name,
    required this.quantity,
    required this.unit,
    this.expiryDate,
  });
}

String _formatQty(double qty, String unit) {
  if (qty == qty.roundToDouble()) {
    return '${qty.toStringAsFixed(0)} ${unit.trim()}'.trim();
  }
  return '${qty.toStringAsFixed(1)} ${unit.trim()}'.trim();
}

String _formatDate(DateTime d) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yy = d.year.toString();
  return '$dd/$mm/$yy';
}

String _expirySubtitle(DateTime d) {
  final dateText = _formatDate(d);
  final dl = _dateOnly(d).difference(_today()).inDays;
  if (dl <= 0) {
    // กรณีวันนี้ (หรือเผื่อข้อมูลเวลาเพี้ยนไปเล็กน้อย)
    return '$dateText • หมดอายุวันนี้';
  }
  return '$dateText • ใกล้หมดอายุอีก $dl วัน';
}

// --- local date helpers (match ShoppingItem parsing/logic) ---
DateTime? _toDateTime(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) {
    try {
      return DateTime.parse(v);
    } catch (_) {
      return null;
    }
  }
  if (v is int) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(v);
    } catch (_) {
      return null;
    }
  }
  return null;
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

// ===== Aggregation helpers =====
enum _UnitGroup { mass, volume, other }

class _Agg {
  final String label;
  final _UnitGroup group;
  int
  canonicalQty; // grams for mass, milliliters for volume, raw count for others
  final String? groupUnit; // for other group, keep the specific unit
  DateTime? minExpiry;
  _Agg({
    required this.label,
    required this.group,
    required this.canonicalQty,
    this.groupUnit,
    this.minExpiry,
  });
}

_UnitGroup _unitGroup(String unit) {
  final u = unit.trim().toLowerCase();
  switch (u) {
    case 'กรัม':
    case 'กิโลกรัม':
      return _UnitGroup.mass;
    case 'มิลลิลิตร':
    case 'ลิตร':
    case 'ช้อนชา':
    case 'ช้อนโต๊ะ':
    case 'ถ้วย':
    case 'ซีซี':
    case 'cc':
    case 'tsp':
    case 'tbsp':
    case 'cup':
      return _UnitGroup.volume;
    default:
      return _UnitGroup.other;
  }
}

int _toCanonical(int qty, String unit) {
  final u = unit.trim().toLowerCase();
  switch (u) {
    // mass (canonical = grams)
    case 'กรัม':
      return qty;
    case 'กิโลกรัม':
      return qty * 1000;

    // volume (canonical = milliliters)
    case 'มิลลิลิตร':
    case 'ซีซี':
    case 'cc':
      return qty; // ml
    case 'ลิตร':
      return qty * 1000;
    case 'ช้อนชา': // ~ 5 ml
    case 'tsp':
      return qty * 5;
    case 'ช้อนโต๊ะ': // ~ 15 ml
    case 'tbsp':
      return qty * 15;
    case 'ถ้วย': // ~ 240 ml (metric cup)
    case 'cup':
      return qty * 240;

    default:
      // others keep as-is (treated per specific unit)
      return qty;
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

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.emoji_events_outlined, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'หมวดที่มีมากที่สุด: $topCategory ($count รายการ)',
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final String category;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withAlpha((255 * 0.14).round()),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outline.withAlpha(90)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: color.withAlpha((255 * 0.16).round()),
              child: Icon(Categories.iconFor(category), color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              category,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$count รายการ',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withAlpha(160),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
