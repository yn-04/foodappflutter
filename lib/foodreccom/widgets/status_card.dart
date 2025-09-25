//lib/foodreccom/widgets/status_card.dart
import 'package:flutter/material.dart';

class StatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color color;
  final Widget? action;

  const StatusCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.color,
    this.action,
  });

  // state: loading
  const StatusCard.loading({
    super.key,
    required String title,
    String? subtitle,
    required Color color,
  }) : icon = Icons.hourglass_empty,
       title = title,
       subtitle = subtitle,
       color = color,
       action = null;

  // state: error
  factory StatusCard.error({
    required String message,
    required VoidCallback onRetry,
  }) {
    return StatusCard(
      icon: Icons.error_outline,
      title: 'เกิดข้อผิดพลาด',
      subtitle: message,
      color: Colors.red,
      action: ElevatedButton(
        onPressed: onRetry,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red[600],
          foregroundColor: Colors.white,
        ),
        child: const Text('ลองใหม่'),
      ),
    );
  }

  // state: empty
  factory StatusCard.empty({
    required bool hasIngredients,
    required VoidCallback onRetry,
    required VoidCallback onAdd,
  }) {
    return StatusCard(
      icon: hasIngredients ? Icons.restaurant_menu : Icons.inventory_2,
      title: hasIngredients ? 'ยังไม่มีเมนูแนะนำ' : 'ไม่มีวัตถุดิบในระบบ',
      subtitle: hasIngredients
          ? 'AI ไม่สามารถแนะนำเมนูได้ในขณะนี้'
          : 'กรุณาเพิ่มวัตถุดิบก่อนเพื่อรับคำแนะนำ',
      color: Colors.grey,
      action: ElevatedButton(
        onPressed: hasIngredients ? onRetry : onAdd,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.yellow[600],
          foregroundColor: Colors.black,
        ),
        child: Text(hasIngredients ? 'ขอคำแนะนำใหม่' : 'เพิ่มวัตถุดิบ'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 40),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(icon, size: 80, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color.withOpacity(0.9),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: color.withOpacity(0.7), fontSize: 14),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
