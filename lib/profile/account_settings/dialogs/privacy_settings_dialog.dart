// dialogs/privacy_settings_dialog.dart
import 'package:flutter/material.dart';

class PrivacySettingsDialog extends StatefulWidget {
  const PrivacySettingsDialog({Key? key}) : super(key: key);

  @override
  State<PrivacySettingsDialog> createState() => _PrivacySettingsDialogState();
}

class _PrivacySettingsDialogState extends State<PrivacySettingsDialog> {
  // Privacy settings
  bool _shareHealthData = true;
  bool _anonymousAnalytics = false;
  bool _personalizedMarketing = false;
  bool _dataProcessingConsent = true;
  bool _thirdPartySharing = false;

  void _saveSettings() {
    // TODO: Save privacy settings to database
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('บันทึกการตั้งค่าความเป็นส่วนตัวสำเร็จ'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showDataUsageInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('การใช้ข้อมูลของเรา'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'เราใช้ข้อมูลของคุณเพื่อ:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• ปรับปรุงและพัฒนาบริการ'),
              Text('• ให้คำแนะนำด้านสุขภาพที่เหมาะสม'),
              Text('• วิเคราะห์แนวโน้มการใช้งาน'),
              SizedBox(height: 16),
              Text(
                'ข้อมูลที่เราเก็บรวบรวม:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• ข้อมูลสุขภาพและการออกกำลังกาย'),
              Text('• ข้อมูลการใช้งานแอป'),
              Text('• ข้อมูลอุปกรณ์และระบบปฏิบัติการ'),
              Text('• ข้อมูลการเข้าถึงและการนำทาง'),
              SizedBox(height: 16),
              Text(
                'เราจะไม่แชร์ข้อมูลส่วนตัวของคุณกับบุคคลที่สามโดยไม่ได้รับความยินยอม',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('เข้าใจแล้ว'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'การควบคุมความเป็นส่วนตัว',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header text
            const Text(
              'ควบคุมการใช้และแชร์ข้อมูลของคุณ:',
              style: TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 16),

            // Health data sharing
            _buildPrivacyOption(
              icon: Icons.health_and_safety,
              iconColor: Colors.green,
              title: 'แชร์ข้อมูลสุขภาพ',
              subtitle: 'อนุญาตให้แชร์ข้อมูลสุขภาพกับสมาชิกครอบครัวที่คุณระบุ',
              value: _shareHealthData,
              onChanged: (value) => setState(() => _shareHealthData = value),
            ),

            const SizedBox(height: 12),

            // Anonymous analytics
            _buildPrivacyOption(
              icon: Icons.analytics,
              iconColor: Colors.blue,
              title: 'การวิเคราะห์แบบไม่ระบุตัวตน',
              subtitle: 'ช่วยปรับปรุงแอปโดยส่งข้อมูลการใช้งานที่ไม่ระบุตัวตน',
              value: _anonymousAnalytics,
              onChanged: (value) => setState(() => _anonymousAnalytics = value),
            ),

            const SizedBox(height: 12),

            // Personalized marketing
            _buildPrivacyOption(
              icon: Icons.campaign,
              iconColor: Colors.orange,
              title: 'การตลาดส่วนบุคคล',
              subtitle: 'รับข้อเสนอและเนื้อหาที่ปรับให้เหมาะกับคุณ',
              value: _personalizedMarketing,
              onChanged: (value) =>
                  setState(() => _personalizedMarketing = value),
            ),

            const SizedBox(height: 12),

            // Data processing consent
            _buildPrivacyOption(
              icon: Icons.security,
              iconColor: Colors.indigo,
              title: 'ความยินยอมในการประมวลผลข้อมูล',
              subtitle: 'อนุญาตให้ประมวลผลข้อมูลเพื่อการให้บริการที่ดีขึ้น',
              value: _dataProcessingConsent,
              onChanged: (value) =>
                  setState(() => _dataProcessingConsent = value),
              isRequired: true,
            ),

            const SizedBox(height: 12),

            // Third party sharing
            _buildPrivacyOption(
              icon: Icons.share,
              iconColor: Colors.red,
              title: 'แชร์ข้อมูลกับบุคคลที่สาม',
              subtitle:
                  'อนุญาตให้แชร์ข้อมูลกับพันธมิตรเพื่อการวิจัยทางการแพทย์',
              value: _thirdPartySharing,
              onChanged: (value) => setState(() => _thirdPartySharing = value),
            ),

            const SizedBox(height: 20),

            // Info button
            Center(
              child: OutlinedButton.icon(
                onPressed: _showDataUsageInfo,
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('ดูข้อมูลเพิ่มเติม'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue,
                  side: const BorderSide(color: Colors.blue),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Privacy notice
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield, color: Colors.green, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'ความปลอดภัยของข้อมูล',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'ข้อมูลของคุณได้รับการเข้ารหัสและจัดเก็บอย่างปลอดภัย คุณสามารถเปลี่ยนแปลงการตั้งค่าเหล่านี้ได้ตลอดเวลา',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
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
          onPressed: _saveSettings,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          child: const Text('บันทึกการตั้งค่า'),
        ),
      ],
    );
  }

  Widget _buildPrivacyOption({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isRequired = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (isRequired)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'จำเป็น',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: isRequired ? null : onChanged,
            activeColor: Colors.black,
          ),
        ],
      ),
    );
  }
}
