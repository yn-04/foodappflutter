// lib/rawmaterial/widgets/shopping_item_card.dart การ์ดแสดงรายการวัตถุดิบ (เดี่ยว/กลุ่ม)
import 'package:flutter/material.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/constants/units.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';

class ShoppingItemCard extends StatelessWidget {
  final ShoppingItem item;
  final VoidCallback? onTap;
  final Future<void> Function()? onDelete; // รองรับ async
  final VoidCallback? onQuickUse;

  /// ====== โหมดกลุ่ม (ออปชัน) ======
  /// จำนวนรวมทั้งหมดในกลุ่ม (ถ้า null จะใช้ item.quantity)
  final int? groupTotalQuantity;

  /// หน่วยของกลุ่ม (ถ้า null จะใช้ item.unit)
  final String? groupUnit;

  /// หมวดหมู่ของกลุ่ม (ถ้า null จะใช้ item.category)
  final String? groupCategory;

  /// วันหมดอายุที่ "ใกล้ที่สุด" ในกลุ่ม (ถ้า null จะใช้ item.expiryDate)
  final DateTime? groupEarliestExpiry;

  const ShoppingItemCard({
    Key? key,
    required this.item,
    this.onTap,
    this.onDelete,
    this.onQuickUse,
    this.groupTotalQuantity,
    this.groupUnit,
    this.groupCategory,
    this.groupEarliestExpiry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // ====== เลือกค่าที่จะแสดง (โหมดกลุ่ม > เดี่ยว) ======
    final int displayQty = groupTotalQuantity ?? item.quantity;
    final String displayUnit = Units.safe(groupUnit ?? item.unit);
    final String displayCategory = groupCategory ?? item.category;
    final DateTime? displayExpiry = groupEarliestExpiry ?? item.expiryDate;

    // คำนวณต่างวันแบบ day-precision (ตัดเวลาออก)
    int? d;
    if (displayExpiry != null) {
      final today = DateTime.now();
      final onlyToday = DateTime(today.year, today.month, today.day);
      final onlyExpiry = DateTime(
        displayExpiry.year,
        displayExpiry.month,
        displayExpiry.day,
      );
      d = onlyExpiry.difference(onlyToday).inDays;
    }

    // ---- สถานะวันหมดอายุ (สี/ข้อความ) ----
    Color? statusColor;
    String? statusText;

    if (d == null) {
      statusColor = Colors.grey;
      statusText = 'ไม่ระบุวันหมดอายุ';
    } else if (d < 0) {
      // หมดอายุแล้ว -> ไม่แสดงสถานะ/วันที่
      statusColor = null;
      statusText = null;
    } else if (d == 0) {
      statusColor = Colors.red;
      statusText = 'หมดอายุวันนี้';
    } else if (d == 1) {
      statusColor = Colors.red;
      statusText = 'หมดอายุในอีก 1 วัน';
    } else if (d == 2 || d == 3) {
      statusColor = Colors.orange;
      statusText = 'หมดอายุในอีก $d วัน';
    } else {
      statusColor = Colors.green;
      statusText = 'หมดอายุในอีก $d วัน';
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.grey[200],
              child: Icon(
                Categories.iconFor(displayCategory),
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- ชื่อวัตถุดิบ: ตัดบรรทัด + ใส่ ... ----
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // บรรทัดสรุปจำนวนรวม + หน่วย + หมวดหมู่ (รองรับกลุ่ม/เดี่ยว)
                  Text(
                    '$displayQty $displayUnit • $displayCategory',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                  const SizedBox(height: 4),

                  // ---- แสดงสถานะ/วันที่ตามเงื่อนไข ----
                  if (statusText != null && statusColor != null)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            // ignore: deprecated_member_use
                            color: statusColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // ปุ่มลบ (มียืนยันก่อนลบ)
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.grey[700]),
              tooltip: 'ลบรายการ',
              onPressed: onDelete == null
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('ลบรายการ'),
                          content: Text('ต้องการลบ "${item.name}" ใช่หรือไม่?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('ยกเลิก'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(
                                'ลบ',
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await onDelete!();
                      }
                    },
            ),
            const SizedBox(width: 8),

            // ปุ่ม "ใช้เลย"
            SizedBox(
              height: 30,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  backgroundColor: const Color.fromARGB(255, 255, 255, 255),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey[700]!),
                  ),
                ),
                // ใช้ไอคอนธีมทำอาหาร สีเทา
                icon: Icon(
                  Icons.restaurant_menu,
                  size: 16,
                  color: Colors.grey[700],
                ),
                label: const Text(
                  'ใช้',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                onPressed: onQuickUse,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
