// lib/rawmaterial/pages/item_detail_card.dart
import 'package:flutter/material.dart';

import 'package:my_app/rawmaterial/models/shopping_item.dart';
import 'package:my_app/rawmaterial/widgets/shopping_item_card.dart'
    as base_card;

/// การ์ดแสดงรายละเอียดวัตถุดิบแบบย่อ
/// ใช้สไตล์เดียวกับ `widgets/shopping_item_card.dart`
class ItemDetailCard extends StatelessWidget {
  final ShoppingItem item;

  // การกระทำต่าง ๆ (ส่งต่อไปยังการ์ดหลัก)
  final VoidCallback? onTap;
  final Future<void> Function()? onDelete;
  final VoidCallback? onQuickUse;

  // โหมดกลุ่ม (ออปชัน)
  final int? groupTotalQuantity;
  final String? groupUnit;
  final String? groupCategory;
  final DateTime? groupEarliestExpiry;

  const ItemDetailCard({
    super.key,
    required this.item,
    this.onTap,
    this.onDelete,
    this.onQuickUse,
    this.groupTotalQuantity,
    this.groupUnit,
    this.groupCategory,
    this.groupEarliestExpiry,
  });

  @override
  Widget build(BuildContext context) {
    return base_card.ShoppingItemCard(
      item: item,
      onTap: onTap,
      onDelete: onDelete,
      onQuickUse: onQuickUse,
      groupTotalQuantity: groupTotalQuantity,
      groupUnit: groupUnit,
      groupCategory: groupCategory,
      groupEarliestExpiry: groupEarliestExpiry,
    );
  }
}
