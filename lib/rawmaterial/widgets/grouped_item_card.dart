// lib/rawmaterial/widgets/grouped_item_card.dart
import 'package:flutter/material.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/constants/units.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';

class GroupedItemCard extends StatelessWidget {
  final String name;
  final List<ShoppingItem> items;
  final VoidCallback? onTap;

  /// ลบทั้งกลุ่ม (fallback ถ้าไม่ได้ส่ง onUseUpGroup มา)
  final Future<void> Function()? onDeleteGroup;

  /// ใช้หมดทั้งกลุ่ม (แนะนำให้ parent ไป log usage และตั้ง qty=0 รายการย่อย)
  final Future<void> Function(List<ShoppingItem> items)? onUseUpGroup;

  /// แสดง dialog ยืนยันก่อน "ใช้หมดทั้งกลุ่ม"
  final bool confirmUseUpGroup;

  const GroupedItemCard({
    super.key,
    required this.name,
    required this.items,
    this.onTap,
    this.onDeleteGroup,
    this.onUseUpGroup,
    this.confirmUseUpGroup = true,
  });

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
    return (color: Colors.green, text: 'หมดอายุในอีก $days วัน');
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

    const radius = 15.0;
    const frontHeight = 118.0;

    // ถ้ามี onUseUpGroup ให้แสดงโหมด "ใช้หมด"

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // แผ่นหลัง
        Transform.translate(
          offset: const Offset(0, 10),
          child: IgnorePointer(
            child: Container(
              margin: const EdgeInsets.fromLTRB(24, 6, 24, 15),
              height: frontHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
          ),
        ),

        // การ์ดหน้า
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Material(
            color: Colors.white,
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: onTap,
              child: Container(
                height: frontHeight,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // ไอคอนหมวด
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Colors.grey[100],
                      child: Icon(
                        Categories.iconFor(category),
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // เนื้อหา
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasSingleUnit
                                ? '$totalQty $displayUnit • $category • ${items.length} รายการ'
                                : '$category • ${items.length} รายการ (หลายหน่วย)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (status.color != null && status.text != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: status.color!.withValues(alpha: 0.12),
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
                            ),
                        ],
                      ),
                    ),

                    // ปุ่มขวา: ใช้หมดทั้งกลุ่ม (ถ้ามี onUseUpGroup) มิฉะนั้น fallback เป็นลบกลุ่ม
                    if (onUseUpGroup != null)
                      IconButton(
                        tooltip: 'ใช้หมดทั้งกลุ่ม',
                        icon: Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.grey[700],
                        ),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('ยืนยัน: ใช้หมดทั้งกลุ่ม'),
                              content: Text(
                                'ต้องการบันทึกว่าใช้ "$name" ทั้งกลุ่มจนหมดหรือไม่?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('ยกเลิก'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(
                                    'ยืนยัน',
                                    style: TextStyle(color: Colors.grey[700]),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await onUseUpGroup!(items);
                          }
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
