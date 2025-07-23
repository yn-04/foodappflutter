// lib/widgets/shopping_item_card.dart
import 'package:flutter/material.dart';
import '../models/shopping_item.dart';

class ShoppingItemCard extends StatelessWidget {
  final ShoppingItem item;
  final Function(int) onQuantityChanged;
  final VoidCallback onDelete;
  final String searchQuery;

  const ShoppingItemCard({
    Key? key,
    required this.item,
    required this.onQuantityChanged,
    required this.onDelete,
    this.searchQuery = '',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // คำนวณสถานะการหมดอายุ
    Color statusColor = Colors.green;
    String statusText = 'ยังไม่หมดอายุ';

    if (item.expiryDate != null) {
      final now = DateTime.now();
      final daysUntilExpiry = item.expiryDate!.difference(now).inDays;

      if (daysUntilExpiry < 0) {
        statusColor = Colors.red;
        statusText = 'หมดอายุแล้ว';
      } else if (daysUntilExpiry <= 3) {
        statusColor = Colors.orange;
        statusText = 'ใกล้หมดอายุ';
      }
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 50,
            height: 50,
            color: Colors.grey[200],
            child: item.imageUrl.isNotEmpty
                ? Image.network(
                    item.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.image_not_supported,
                        color: Colors.grey,
                      );
                    },
                  )
                : Icon(_getCategoryIcon(item.category), color: Colors.grey),
          ),
        ),
        title: _buildHighlightedText(item.name, searchQuery),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _buildHighlightedText(
                    item.category,
                    searchQuery,
                    TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              item.expiryDate != null
                  ? 'หมดอายุ: ${_formatDate(item.expiryDate!)}'
                  : 'ไม่มีวันหมดอายุ',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        // แก้ไข trailing เพื่อป้องกัน RenderFlex overflow
        trailing: SizedBox(
          width: 112, // กำหนดความกว้างสูงสุด
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ปุ่มลบ - ลดขนาด
              Container(
                width: 28, // ลดจาก 32 เป็น 28
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.remove_circle_outline,
                    color: Colors.red,
                    size: 18, // ลดขนาดไอคอน
                  ),
                  onPressed: () {
                    if (item.quantity > 1) {
                      onQuantityChanged(item.quantity - 1);
                    } else {
                      _showDeleteConfirmDialog(context);
                    }
                  },
                ),
              ),

              // แสดงจำนวน - ลดขนาด
              Container(
                width: 28, // ลดจาก 40 เป็น 28
                child: Center(
                  child: Text(
                    '${item.quantity}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14, // ลดขนาดฟอนต์
                    ),
                  ),
                ),
              ),

              // ปุ่มเพิ่ม - ลดขนาด
              Container(
                width: 28, // ลดจาก 32 เป็น 28
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.add_circle_outline,
                    color: Colors.green,
                    size: 18, // ลดขนาดไอคอน
                  ),
                  onPressed: () {
                    onQuantityChanged(item.quantity + 1);
                  },
                ),
              ),

              // ไอคอนถังขยะ - ลดขนาด
              Container(
                width: 28, // ลดจาก 32 เป็น 28
                height: 28,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.delete_outline,
                    color: Colors.grey[600],
                    size: 18, // ลดขนาดไอคอน
                  ),
                  onPressed: () {
                    _showDeleteDialog(context);
                  },
                ),
              ),
            ],
          ),
        ),
        onLongPress: () {
          _showDeleteDialog(context);
        },
      ),
    );
  }

  // สร้างข้อความที่ไฮไลต์คำค้นหา
  Widget _buildHighlightedText(String text, String query, [TextStyle? style]) {
    if (query.isEmpty) {
      return Text(
        text,
        style: style ?? TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);

    if (index == -1) {
      return Text(
        text,
        style: style ?? TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      );
    }

    final beforeMatch = text.substring(0, index);
    final match = text.substring(index, index + query.length);
    final afterMatch = text.substring(index + query.length);

    return RichText(
      text: TextSpan(
        style:
            style ??
            TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.black,
            ),
        children: [
          TextSpan(text: beforeMatch),
          TextSpan(
            text: match,
            style: TextStyle(
              backgroundColor: Colors.yellow[300],
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: afterMatch),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'เนื้อสัตว์':
        return Icons.set_meal;
      case 'ผัก':
        return Icons.eco;
      case 'ผลไม้':
        return Icons.apple;
      case 'เครื่องเทศ':
        return Icons.grain;
      case 'แป้ง':
        return Icons.bakery_dining;
      case 'น้ำมัน':
        return Icons.opacity;
      case 'เครื่องดื่ม':
        return Icons.local_drink;
      case 'ของแห้ง':
        return Icons.inventory_2;
      case 'ของแช่แข็ง':
        return Icons.ac_unit;
      default:
        return Icons.fastfood;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${(date.year + 543).toString().substring(2)}';
  }

  void _showDeleteConfirmDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ลบรายการ'),
        content: Text(
          'จำนวน ${item.name} จะเป็น 0 ต้องการลบรายการนี้ออกใช่หรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () {
              onQuantityChanged(0); // ส่ง 0 เพื่อลบรายการ
              Navigator.pop(context);
            },
            child: Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ลบรายการ'),
        content: Text('คุณต้องการลบ ${item.name} ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () {
              onDelete();
              Navigator.pop(context);
            },
            child: Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
