// screens/family/dialogs/family_options_dialog.dart
import 'package:flutter/material.dart';

class FamilyOptionsDialog {
  static void show({
    required BuildContext context,
    required VoidCallback onRefresh,
    required VoidCallback onExport,
    required VoidCallback onDisband,
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
              'ตัวเลือกครอบครัว',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'จัดการและตั้งค่าครอบครัวของคุณ',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Options
            _FamilyOptionTile(
              icon: Icons.refresh,
              title: 'อัปเดตข้อมูลครอบครัว',
              subtitle: 'รีเฟรชข้อมูลและสถิติล่าสุด',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                onRefresh();
              },
            ),
            const SizedBox(height: 12),
            _FamilyOptionTile(
              icon: Icons.analytics,
              title: 'ดูสถิติครอบครัว',
              subtitle: 'วิเคราะห์ข้อมูลสุขภาพแบบละเอียด',
              color: Colors.green,
              onTap: () {
                Navigator.pop(context);
                _showFamilyAnalytics(context);
              },
            ),
            const SizedBox(height: 12),
            _FamilyOptionTile(
              icon: Icons.download,
              title: 'ส่งออกข้อมูลครอบครัว',
              subtitle: 'ดาวน์โหลดรายงานครอบครัวทั้งหมด',
              color: Colors.purple,
              onTap: () {
                Navigator.pop(context);
                onExport();
              },
            ),
            const SizedBox(height: 12),
            _FamilyOptionTile(
              icon: Icons.settings,
              title: 'การตั้งค่าขั้นสูง',
              subtitle: 'ตั้งค่าครอบครัวแบบละเอียด',
              color: Colors.orange,
              onTap: () {
                Navigator.pop(context);
                _showAdvancedSettings(context);
              },
            ),
            const SizedBox(height: 20),

            // Divider
            Container(
              height: 1,
              color: Colors.grey[300],
              margin: const EdgeInsets.symmetric(vertical: 8),
            ),

            // Destructive option
            _FamilyOptionTile(
              icon: Icons.delete_forever,
              title: 'ยุบครอบครัว',
              subtitle: 'ลบครอบครัวและข้อมูลทั้งหมด',
              color: Colors.red,
              isDestructive: true,
              onTap: () {
                Navigator.pop(context);
                onDisband();
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
                  'ปิด',
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

  static void _showFamilyAnalytics(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.analytics, color: Colors.green[600]),
            const SizedBox(width: 8),
            const Text('สถิติครอบครัว'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildAnalyticsCard(
                'การออกกำลังกายในสัปดาห์นี้',
                '75%',
                'สมาชิก 3 จาก 4 คนออกกำลังกายสม่ำเสมอ',
                Colors.green,
                Icons.fitness_center,
              ),
              const SizedBox(height: 12),
              _buildAnalyticsCard(
                'ค่า BMI เฉลี่ย',
                '22.8',
                'อยู่ในเกณฑ์ปกติ (18.5-24.9)',
                Colors.blue,
                Icons.monitor_weight,
              ),
              const SizedBox(height: 12),
              _buildAnalyticsCard(
                'การตรวจสุขภาพ',
                '50%',
                'สมาชิก 2 คนตรวจสุขภาพแล้วในปีนี้',
                Colors.orange,
                Icons.health_and_safety,
              ),
              const SizedBox(height: 12),
              _buildAnalyticsCard(
                'คะแนนสุขภาพครอบครัว',
                '8.2/10',
                'สุขภาพดีมาก แนะนำให้ดูแลต่อไป',
                Colors.purple,
                Icons.star,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to detailed analytics
            },
            child: const Text('ดูรายละเอียด'),
          ),
        ],
      ),
    );
  }

  static Widget _buildAnalyticsCard(
    String title,
    String value,
    String description,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static void _showAdvancedSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.settings, color: Colors.orange[600]),
            const SizedBox(width: 8),
            const Text('การตั้งค่าขั้นสูง'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAdvancedSettingTile(
                'การซิงค์ข้อมูล',
                'ซิงค์อัตโนมัติทุก 30 นาที',
                Icons.sync,
                Colors.blue,
                true,
              ),
              _buildAdvancedSettingTile(
                'การสำรองข้อมูลอัตโนมัติ',
                'สำรองข้อมูลทุกสัปดาห์',
                Icons.backup,
                Colors.green,
                true,
              ),
              _buildAdvancedSettingTile(
                'โหมดประหยัดแบตเตอรี่',
                'ลดการใช้พลังงาน',
                Icons.battery_saver,
                Colors.orange,
                false,
              ),
              _buildAdvancedSettingTile(
                'การวิเคราะห์ด้วย AI',
                'ใช้ AI ให้คำแนะนำสุขภาพ',
                Icons.psychology,
                Colors.purple,
                true,
              ),
              _buildAdvancedSettingTile(
                'โหมดความเป็นส่วนตัวสูง',
                'เข้ารหัสข้อมูลพิเศษ',
                Icons.enhanced_encryption,
                Colors.red,
                false,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.yellow[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.yellow[300]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      color: Colors.yellow[700],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'การเปลี่ยนการตั้งค่าเหล่านี้อาจส่งผลต่อประสิทธิภาพของแอป',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.yellow[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Save advanced settings
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[600],
            ),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  static Widget _buildAdvancedSettingTile(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    bool value,
  ) {
    return StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: (newValue) {
                setState(() {
                  value = newValue;
                });
              },
              activeColor: color,
            ),
          ],
        ),
      ),
    );
  }
}

class _FamilyOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool isDestructive;

  const _FamilyOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.isDestructive = false,
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
          color: isDestructive
              ? Colors.red.withOpacity(0.05)
              : color.withOpacity(0.05),
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
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDestructive ? Colors.red[700] : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDestructive ? Colors.red[500] : Colors.grey[600],
                    ),
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
