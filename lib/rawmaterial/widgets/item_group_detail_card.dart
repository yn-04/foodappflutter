// lib/rawmaterial/widgets/item_group_detail_card.dart — แสดงรายละเอียดกลุ่ม (ชื่อซ้ำ) แบบ Pop-up
// โชว์รายการด้วยการ์ด ShoppingItemCard และให้แก้ไข/ลบได้
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:my_app/rawmaterial/constants/units.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';
import 'package:my_app/rawmaterial/pages/item_detail_page.dart';
import 'package:my_app/rawmaterial/widgets/shopping_item_card.dart';
import 'package:my_app/rawmaterial/widgets/quick_use_sheet.dart'; // ✅ เพิ่มบรรทัดนี้
import 'package:my_app/rawmaterial/utils/unit_converter.dart';

class ItemGroupDetailSheet extends StatefulWidget {
  final String groupName;
  final List<ShoppingItem> items;

  const ItemGroupDetailSheet({
    super.key,
    required this.groupName,
    required this.items,
  });

  @override
  State<ItemGroupDetailSheet> createState() => _ItemGroupDetailSheetState();
}

class _ItemGroupDetailSheetState extends State<ItemGroupDetailSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return SafeArea(
          top: false, // ไม่ดันลงด้านบน เพราะเป็นชีตเลื่อนขึ้นมา
          child: Material(
            // ✅ ใช้ Material ให้ทึบ (ไม่โปร่ง)
            color: Colors.white,
            elevation: 8,
            shadowColor: Colors.black.withOpacity(0.15),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias, // ✅ ตัดขอบ ink/ripple ให้โค้งตามมุม
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 10),

                // ... ที่เหลือเหมือนเดิม ...
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.groupName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        '${widget.items.length} รายการ',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Divider(height: 1, color: Colors.grey[300]),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                    itemCount: widget.items.length,
                    itemBuilder: (_, idx) {
                      final i = widget.items[idx];
                      return ShoppingItemCard(
                        item: i,
                        onTap: () async {
                          final changed = await showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => ItemDetailPage(item: i),
                          );
                          if (changed == true && mounted) {
                            Navigator.pop(context, true);
                          }
                        },
                        onDelete: () => _deleteItem(context, i),
                        onQuickUse: () => _showQuickUseSheet(i),
                        // ในชีตนี้ปิดปุ่ม Quick use อยู่แล้ว
                        confirmDelete: false, // 👈 ปิดการยืนยันบนการ์ด
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _duplicateFromFirst(BuildContext context) async {
    if (widget.items.isEmpty) return;
    await _duplicateItem(context, widget.items.first);
  }

  Future<void> _duplicateItem(BuildContext context, ShoppingItem i) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .add({
            'name': i.name,
            'category': i.category,
            'quantity': i.quantity,
            'unit': Units.safe(i.unit),
            'expiry_date': i.expiryDate != null
                ? Timestamp.fromDate(i.expiryDate!)
                : null,
            'imageUrl': i.imageUrl,
            'created_at': FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
            'user_id': user.uid,
          });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ทำซ้ำไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteItem(BuildContext context, ShoppingItem i) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: false, // 👈 เปิดบน navigator ของชีต
      builder: (_) => AlertDialog(
        title: const Text('ลบวัตถุดิบ'),
        content: Text('ต้องการลบ "${i.name}" ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .doc(i.id)
          .delete();

      if (!mounted) return;
      // ปิดชีตพร้อมส่ง true กลับให้หน้าพ่อรีเฟรช
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ลบไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showQuickUseSheet(ShoppingItem item) {
    showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) {
        return QuickUseSheet(
          itemName: item.name,
          unit: item.unit,
          currentQty: item.quantity,
          onSave: (useQty, unit, note) async {
            if (useQty <= 0) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('จำนวนที่ใช้ต้องอยู่ระหว่าง 1 ถึงจำนวนคงเหลือ'),
                ),
              );
              return;
            }

            final conversion = UnitConverter.applyUsage(
              currentQty: item.quantity,
              currentUnit: item.unit,
              useQty: useQty,
              useUnit: unit,
            );
            if (!conversion.isValid) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('จำนวนที่ใช้ต้องอยู่ระหว่าง 1 ถึงจำนวนคงเหลือ'),
                ),
              );
              return;
            }

            try {
              final user = FirebaseAuth.instance.currentUser;
              if (user == null) return;

              final docRef = FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('raw_materials')
                  .doc(item.id);

              await docRef.collection('usage_logs').add({
                'quantity': useQty,
                'unit': unit,
                'note': note,
                'used_at': FieldValue.serverTimestamp(),
              });

              await docRef.update({
                'quantity': conversion.remainingQuantity,
                'unit': conversion.remainingUnit,
                'updated_at': FieldValue.serverTimestamp(),
              });

              if (!mounted) return;

              Future.microtask(() {
                if (!mounted) return;
                Navigator.pop(context, true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'บันทึกการใช้แล้ว - เหลือ ${conversion.remainingQuantity} ${conversion.remainingUnit}',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              });
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
            }
          },
        );
      },
    );
  }
}
