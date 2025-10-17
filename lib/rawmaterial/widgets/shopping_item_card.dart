// lib/rawmaterial/widgets/shopping_item_card.dart
import 'package:flutter/material.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/constants/units.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';

class ShoppingItemCard extends StatelessWidget {
  final ShoppingItem item;
  final VoidCallback? onTap;

  // เดิมมี onDelete อยู่แล้ว (ลบจริง)
  final Future<void> Function()? onDelete;

  // ใหม่: ใช้หมดแล้ว (บันทึก usage_logs + ตั้งจำนวนเป็น 0)
  // จะถูกเรียกพร้อมจำนวน/หน่วยที่กำลังแสดงบนการ์ด
  final Future<void> Function(int usedQty, String usedUnit)? onUseUp;

  final VoidCallback? onQuickUse;

  /// ถ้า true (default) -> แสดง dialog ยืนยันก่อน "ใช้หมดแล้ว"
  /// ใช้กับ onUseUp
  final bool confirmUseUp;

  /// เดิม: ควบคุมการยืนยันลบ (ยังคงไว้เพื่อ backward-compat)
  final bool confirmDelete;

  /// โหมดกลุ่ม (ตัวเลือก)
  final int? groupTotalQuantity;
  final String? groupUnit;
  final String? groupCategory;
  final DateTime? groupEarliestExpiry;

  const ShoppingItemCard({
    Key? key,
    required this.item,
    this.onTap,
    this.onDelete,
    this.onQuickUse,

    // 👇 เพิ่มสองบรรทัดนี้
    this.onUseUp,
    this.confirmUseUp = true,

    this.groupTotalQuantity,
    this.groupUnit,
    this.groupCategory,
    this.groupEarliestExpiry,

    // เดิม
    this.confirmDelete = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final int displayQty = groupTotalQuantity ?? item.quantity;
    final String displayUnit = Units.safe(groupUnit ?? item.unit);
    final String displayCategory = groupCategory ?? item.category;
    final DateTime? displayExpiry = groupEarliestExpiry ?? item.expiryDate;

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

    Color? statusColor;
    String? statusText;
    if (d == null) {
      statusColor = Colors.grey;
      statusText = 'ไม่ระบุวันหมดอายุ';
    } else if (d < 0) {
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
                  Text(
                    '$displayQty $displayUnit • $displayCategory',
                    style: TextStyle(color: Colors.grey[700], fontSize: 13),
                  ),
                  const SizedBox(height: 4),
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
                            color: statusColor.withValues(alpha: 0.12),
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

            // ปุ่ม “ใช้หมดแล้ว” (แทนการลบ)
            IconButton(
              icon: Icon(
                onUseUp != null
                    ? Icons.inventory_2_outlined
                    : Icons.delete_outline,
                color: Colors.grey[700],
              ),
              tooltip: onUseUp != null ? 'ใช้หมดแล้ว' : 'ลบรายการ',
              onPressed: () async {
                // ถ้ามี onUseUp ให้ทำ flow ใช้หมดแล้ว
                if (onUseUp != null) {
                  if (confirmUseUp) {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('ยืนยัน: ใช้หมดแล้ว'),
                        content: Text(
                          'ต้องการบันทึกว่า "${item.name}" ใช้หมดแล้วหรือไม่?\n',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
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
                    if (ok != true) return;
                  }
                  await onUseUp!(displayQty, displayUnit);
                  return;
                }

                // fallback: ยังไม่มี onUseUp → ใช้ลบแบบเดิม
                if (onDelete == null) return;

                if (!confirmDelete) {
                  await onDelete!();
                  return;
                }

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
