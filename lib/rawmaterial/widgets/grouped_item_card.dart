// lib/rawmaterial/widgets/grouped_item_card.dart
import 'package:flutter/material.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/constants/units.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';

class GroupedItemCard extends StatelessWidget {
  final String name;
  final List<ShoppingItem> items;
  final VoidCallback? onTap;

  /// เรียกเมื่อยืนยันลบทั้งกลุ่ม
  final Future<void> Function()? onDeleteGroup;

  const GroupedItemCard({
    Key? key,
    required this.name,
    required this.items,
    this.onTap,
    this.onDeleteGroup,
  }) : super(key: key);

  int? _daysLeft(DateTime? expiry) {
    if (expiry == null) return null;
    final now = DateTime.now();
    final onlyNow = DateTime(now.year, now.month, now.day);
    final onlyExp = DateTime(expiry.year, expiry.month, expiry.day);
    return onlyExp.difference(onlyNow).inDays;
  }

  ({Color? color, String? text}) _status(int? days) {
    if (days == null) return (color: Colors.grey, text: 'ไม่ระบุวันหมดอายุ');
    if (days < 0) return (color: null, text: null);
    if (days == 0) return (color: Colors.red, text: 'หมดอายุวันนี้');
    if (days == 1) return (color: Colors.red, text: 'หมดอายุในอีก 1 วัน');
    if (days == 2 || days == 3) {
      return (color: Colors.orange, text: 'หมดอายุในอีก $days วัน');
    }
    return (color: Colors.green, text: 'หมดในอีก $days วัน');
  }

  @override
  Widget build(BuildContext context) {
    final category = items.first.category;

    // รวมจำนวน + หน่วย
    final unitSet = items.map((e) => Units.safe(e.unit)).toSet();
    final hasSingleUnit = unitSet.length == 1;
    final displayUnit = hasSingleUnit ? unitSet.first : null;
    final totalQty = items.fold<int>(0, (s, e) => s + e.quantity);

    // วันหมดอายุที่ใกล้ที่สุด
    final DateTime? nearest = items
        .map((e) => e.expiryDate)
        .where((d) => d != null)
        .cast<DateTime>()
        .fold<DateTime?>(
          null,
          (min, d) => (min == null || d.isBefore(min)) ? d : min,
        );

    final days = _daysLeft(nearest);
    final status = _status(days);

    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey[100],
            child: Icon(Categories.iconFor(category), color: Colors.grey[700]),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ชื่อกลุ่ม
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),

                // จำนวนรวม + รายการ
                Text(
                  hasSingleUnit
                      ? '$totalQty $displayUnit • $category • ${items.length} รายการ'
                      : '$category • ${items.length} รายการ (หลายหน่วย)',
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
                const SizedBox(height: 6),

                // สถานะวันหมดอายุ (ไม่แสดงวันที่ตัวเลข)
                if (status.color != null && status.text != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: status.color!.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status.text!,
                      style: TextStyle(
                        color: status.color,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ปุ่มลบกลุ่ม — ขยายฮิตโซน + แจ้งเตือนถ้า callback ไม่ถูกผูก
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              tooltip: 'ลบทั้งกลุ่ม',
              icon: Icon(Icons.delete_outline, color: Colors.grey[600]),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () async {
                if (onDeleteGroup == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'กลุ่มนี้ยังไม่ได้ผูกการลบ (onDeleteGroup)',
                      ),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }

                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('ยืนยันการลบ'),
                    content: ConstrainedBox(
                      constraints: BoxConstraints(
                        // กันล้นจอในกรณีรายการเยอะ
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                        maxWidth: MediaQuery.of(context).size.width * 0.9,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('คุณต้องการลบกลุ่ม "$name" ใช่หรือไม่?\n'),
                            const Text('รายการที่จะถูกลบ:'),
                            const SizedBox(height: 8),
                            ...items.map(
                              (e) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  '• ${e.name} (${e.quantity} ${Units.safe(e.unit)})',
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('ยกเลิก'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text(
                          'ลบ',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );

                if (ok == true) {
                  await onDeleteGroup!();
                }
              },
            ),
          ),
        ],
      ),
    );

    // เอฟเฟกต์การ์ดซ้อน
    return InkWell(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none, // ✅ กันโดนตัดฮิตโซนบริเวณขอบ
        children: [
          Positioned.fill(
            top: 10,
            left: 8,
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 6),
                  ],
                ),
              ),
            ),
          ),
          card,
        ],
      ),
    );
  }
}
