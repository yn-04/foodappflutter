// screens/family/widgets/quick_actions_row.dart
import 'package:flutter/material.dart';

class QuickActionsRow extends StatelessWidget {
  final VoidCallback onInvite;
  final VoidCallback onHealthCheck;

  const QuickActionsRow({
    super.key,
    required this.onInvite,
    required this.onHealthCheck,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: QuickActionCard(
            title: 'เชิญสมาชิก',
            subtitle: 'แชร์ลิงก์หรือ QR Code',
            icon: Icons.person_add,
            color: Colors.blue,
            onTap: onInvite,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: QuickActionCard(
            title: 'ตรวจสุขภาพ',
            subtitle: 'ดูสถานะสมาชิก',
            icon: Icons.health_and_safety,
            color: Colors.green,
            onTap: onHealthCheck,
          ),
        ),
      ],
    );
  }
}

class QuickActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const QuickActionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
