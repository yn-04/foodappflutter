// screens/family/dialogs/add_member_options_dialog.dart
import 'package:flutter/material.dart';

class AddMemberOptionsDialog {
  static void show({
    required BuildContext context,
    required VoidCallback onAddManually,
    required VoidCallback onScanQR,
    required VoidCallback onShareLink,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            const Text(
              'เพิ่มสมาชิกใหม่',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'เลือกวิธีการเพิ่มสมาชิกในครอบครัว',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Options
            _AddOptionTile(
              icon: Icons.person_add,
              title: 'เพิ่มด้วยข้อมูลส่วนตัว',
              subtitle: 'กรอกข้อมูลสมาชิกใหม่ด้วยตนเอง',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                onAddManually();
              },
            ),
            const SizedBox(height: 12),
            _AddOptionTile(
              icon: Icons.qr_code_scanner,
              title: 'สแกน QR Code',
              subtitle: 'ให้สมาชิกสแกน QR Code เพื่อเข้าร่วม',
              color: Colors.green,
              onTap: () {
                Navigator.pop(context);
                onScanQR();
              },
            ),
            const SizedBox(height: 12),
            _AddOptionTile(
              icon: Icons.share,
              title: 'แชร์ลิงก์เชิญ',
              subtitle: 'ส่งลิงก์เชิญให้สมาชิกเข้าร่วม',
              color: Colors.orange,
              onTap: () {
                Navigator.pop(context);
                onShareLink();
              },
            ),

            const SizedBox(height: 24),

            // Cancel button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'ยกเลิก',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            ),

            // Safe area padding
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}

class _AddOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AddOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
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
          border: Border.all(color: color.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(12),
          color: color.withOpacity(0.05),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
