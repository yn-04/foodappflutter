// screens/family/widgets/family_settings_card.dart
import 'package:flutter/material.dart';

class FamilySettingsCard extends StatelessWidget {
  final VoidCallback onQRCode;
  final VoidCallback onPermissions;
  final VoidCallback onNotifications;
  final VoidCallback onBackup;

  const FamilySettingsCard({
    super.key,
    required this.onQRCode,
    required this.onPermissions,
    required this.onNotifications,
    required this.onBackup,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.settings,
                    color: Colors.blue[600],
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'การตั้งค่าครอบครัว',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          SettingsTile(
            icon: Icons.qr_code,
            title: 'เชิญสมาชิกผ่าน QR Code',
            subtitle: 'สร้าง QR Code เพื่อเชิญสมาชิกใหม่',
            color: Colors.green,
            onTap: onQRCode,
          ),
          _buildDivider(),
          SettingsTile(
            icon: Icons.security,
            title: 'สิทธิ์การเข้าถึงข้อมูล',
            subtitle: 'จัดการสิทธิ์การดูข้อมูลสุขภาพ',
            color: Colors.orange,
            onTap: onPermissions,
          ),
          _buildDivider(),
          SettingsTile(
            icon: Icons.notifications,
            title: 'การแจ้งเตือนครอบครัว',
            subtitle: 'ตั้งค่าการแจ้งเตือนสำหรับครอบครัว',
            color: Colors.purple,
            onTap: onNotifications,
          ),
          _buildDivider(),
          SettingsTile(
            icon: Icons.backup,
            title: 'สำรองข้อมูลครอบครัว',
            subtitle: 'สำรองและซิงค์ข้อมูลครอบครัว',
            color: Colors.teal,
            onTap: onBackup,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      height: 1,
      color: Colors.grey[200],
    );
  }
}

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const SettingsTile({
    super.key,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
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
