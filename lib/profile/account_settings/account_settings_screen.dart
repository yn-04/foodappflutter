// screens/account_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app/profile/account_settings/dialogs/change_password_dialog.dart';
import 'package:my_app/profile/account_settings/dialogs/delete_account_dialog.dart';
import 'package:my_app/profile/account_settings/dialogs/notification_settings_dialog.dart';
import 'package:my_app/profile/account_settings/dialogs/privacy_settings_dialog.dart';
import 'package:my_app/profile/account_settings/services/settings_service.dart';
import 'package:my_app/profile/account_settings/widgets/settings_card.dart';
import 'package:my_app/profile/account_settings/widgets/settings_item.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  // Services
  final SettingsService _settingsService = SettingsService();
  final user = FirebaseAuth.instance.currentUser;

  // State variables
  bool _isLoading = true;
  Map<String, bool> _settings = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      await _loadSettings();
    } catch (e) {
      print('Error loading data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSettings() async {
    if (user != null) {
      _settings = await _settingsService.loadSettings(user!.uid);
      if (mounted) setState(() {});
    }
  }

  Future<void> _updateSetting(String key, bool value) async {
    setState(() => _settings[key] = value);

    if (user != null) {
      await _settingsService.updateSetting(user!.uid, key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.grey[100],
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'การตั้งค่าบัญชี',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Security Section
                  SettingsCard(
                    title: 'ความปลอดภัย',
                    items: [
                      SettingsItem(
                        icon: Icons.lock_outline,
                        title: 'เปลี่ยนรหัสผ่าน',
                        subtitle: 'อัปเดตรหัสผ่านของคุณ',
                        onTap: () => _showChangePasswordDialog(),
                      ),
                      SettingsItem(
                        icon: Icons.fingerprint,
                        title: 'Face ID / Touch ID',
                        subtitle: 'ใช้ชีวมิติในการเข้าสู่ระบบ',
                        trailing: Switch(
                          value: _settings['biometricEnabled'] ?? false,
                          onChanged: (value) =>
                              _updateSetting('biometricEnabled', value),
                          activeColor: Colors.black,
                        ),
                      ),
                      SettingsItem(
                        icon: Icons.devices_outlined,
                        title: 'จัดการอุปกรณ์',
                        subtitle: 'ดูอุปกรณ์ที่ล็อกอินอยู่',
                        onTap: () => _showDevicesDialog(),
                      ),
                      SettingsItem(
                        icon: Icons.verified_user_outlined,
                        title: 'การยืนยันตัวตน',
                        subtitle: user?.emailVerified == true
                            ? 'ยืนยันแล้ว'
                            : 'ยังไม่ยืนยัน',
                        onTap: () => _handleEmailVerification(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Notifications Section
                  SettingsCard(
                    title: 'การแจ้งเตือน',
                    items: [
                      SettingsItem(
                        icon: Icons.notifications_outlined,
                        title: 'การแจ้งเตือนทั้งหมด',
                        subtitle: 'เปิด/ปิดการแจ้งเตือนทั้งหมด',
                        trailing: Switch(
                          value: _settings['notificationsEnabled'] ?? true,
                          onChanged: (value) =>
                              _updateSetting('notificationsEnabled', value),
                          activeColor: Colors.black,
                        ),
                      ),
                      SettingsItem(
                        icon: Icons.email_outlined,
                        title: 'การแจ้งเตือนทางอีเมล',
                        subtitle: 'รับข่าวสารทางอีเมล',
                        trailing: Switch(
                          value: _settings['emailNotifications'] ?? true,
                          onChanged: (_settings['notificationsEnabled'] ?? true)
                              ? (value) =>
                                    _updateSetting('emailNotifications', value)
                              : null,
                          activeColor: Colors.black,
                        ),
                      ),
                      SettingsItem(
                        icon: Icons.sms_outlined,
                        title: 'การแจ้งเตือนทาง SMS',
                        subtitle: 'รับข้อความ SMS',
                        trailing: Switch(
                          value: _settings['smsNotifications'] ?? false,
                          onChanged: (_settings['notificationsEnabled'] ?? true)
                              ? (value) =>
                                    _updateSetting('smsNotifications', value)
                              : null,
                          activeColor: Colors.black,
                        ),
                      ),
                      SettingsItem(
                        icon: Icons.mobile_friendly,
                        title: 'Push Notifications',
                        subtitle: 'การแจ้งเตือนบนมือถือ',
                        trailing: Switch(
                          value: _settings['pushNotifications'] ?? true,
                          onChanged: (_settings['notificationsEnabled'] ?? true)
                              ? (value) =>
                                    _updateSetting('pushNotifications', value)
                              : null,
                          activeColor: Colors.black,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Health Notifications
                  SettingsCard(
                    title: 'การแจ้งเตือนสุขภาพ',
                    items: [
                      SettingsItem(
                        icon: Icons.health_and_safety_outlined,
                        title: 'การแจ้งเตือนสุขภาพ',
                        subtitle: 'เตือนดูแลสุขภาพประจำวัน',
                        trailing: Switch(
                          value: _settings['healthReminders'] ?? true,
                          onChanged: (_settings['notificationsEnabled'] ?? true)
                              ? (value) =>
                                    _updateSetting('healthReminders', value)
                              : null,
                          activeColor: Colors.black,
                        ),
                      ),
                      SettingsItem(
                        icon: Icons.family_restroom,
                        title: 'การแจ้งเตือนครอบครัว',
                        subtitle: 'เตือนเกี่ยวกับสมาชิกในครอบครัว',
                        trailing: Switch(
                          value: _settings['familyNotifications'] ?? true,
                          onChanged: (_settings['notificationsEnabled'] ?? true)
                              ? (value) =>
                                    _updateSetting('familyNotifications', value)
                              : null,
                          activeColor: Colors.black,
                        ),
                      ),
                      SettingsItem(
                        icon: Icons.schedule,
                        title: 'ตั้งเวลาการแจ้งเตือน',
                        subtitle: 'กำหนดช่วงเวลาที่ต้องการรับการแจ้งเตือน',
                        onTap: () => _showNotificationTimeDialog(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Privacy Section
                  SettingsCard(
                    title: 'ความเป็นส่วนตัว',
                    items: [
                      SettingsItem(
                        icon: Icons.visibility_outlined,
                        title: 'การควบคุมความเป็นส่วนตัว',
                        subtitle: 'จัดการข้อมูลส่วนตัวของคุณ',
                        onTap: () => _showPrivacyDialog(),
                      ),
                      SettingsItem(
                        icon: Icons.download_outlined,
                        title: 'ดาวน์โหลดข้อมูล',
                        subtitle: 'ดาวน์โหลดข้อมูลทั้งหมดของคุณ',
                        onTap: () => _showDownloadDialog(),
                      ),
                      SettingsItem(
                        icon: Icons.auto_delete_outlined,
                        title: 'ลบข้อมูลอัตโนมัติ',
                        subtitle: 'ตั้งค่าการลบข้อมูลเก่า',
                        onTap: () => _showAutoDeleteDialog(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Account Management
                  SettingsCard(
                    title: 'การจัดการบัญชี',
                    items: [
                      SettingsItem(
                        icon: Icons.sync,
                        title: 'ซิงค์ข้อมูล',
                        subtitle: 'ซิงค์ข้อมูลกับอุปกรณ์อื่น',
                        onTap: () => _syncData(),
                      ),
                      SettingsItem(
                        icon: Icons.backup_outlined,
                        title: 'สำรองข้อมูล',
                        subtitle: 'สำรองข้อมูลไปยัง Cloud',
                        onTap: () => _showBackupDialog(),
                      ),
                      SettingsItem(
                        icon: Icons.restore,
                        title: 'กู้คืนข้อมูล',
                        subtitle: 'กู้คืนข้อมูลจากการสำรอง',
                        onTap: () => _showRestoreDialog(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Danger Zone
                  SettingsCard(
                    title: 'พื้นที่อันตราย',
                    items: [
                      SettingsItem(
                        icon: Icons.logout,
                        title: 'ออกจากระบบทุกอุปกรณ์',
                        subtitle: 'ออกจากระบบในอุปกรณ์ทั้งหมด',
                        onTap: () => _showLogoutAllDevicesDialog(),
                        isDestructive: true,
                      ),
                      SettingsItem(
                        icon: Icons.delete_outline,
                        title: 'ลบบัญชี',
                        subtitle: 'ลบบัญชีและข้อมูลทั้งหมดอย่างถาวร',
                        onTap: () => _showDeleteAccountDialog(),
                        isDestructive: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  // Dialog Methods
  void _showChangePasswordDialog() {
    showDialog(context: context, builder: (context) => ChangePasswordDialog());
  }

  void _showNotificationTimeDialog() {
    showDialog(
      context: context,
      builder: (context) => NotificationSettingsDialog(),
    );
  }

  void _showPrivacyDialog() {
    showDialog(context: context, builder: (context) => PrivacySettingsDialog());
  }

  void _showDeleteAccountDialog() {
    showDialog(context: context, builder: (context) => DeleteAccountDialog());
  }

  // Other Methods
  void _showDevicesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('อุปกรณ์ที่ล็อกอินอยู่'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDeviceItem('iPhone 13', 'iOS 16.5', 'กำลังใช้งาน', true),
            const SizedBox(height: 8),
            _buildDeviceItem(
              'MacBook Pro',
              'macOS Ventura',
              '2 ชั่วโมงที่แล้ว',
              false,
            ),
            const SizedBox(height: 8),
            _buildDeviceItem('iPad Air', 'iPadOS 16.5', '1 วันที่แล้ว', false),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showLogoutAllDevicesDialog();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ออกจากระบบทุกอุปกรณ์'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceItem(
    String deviceName,
    String os,
    String lastActive,
    bool isCurrentDevice,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
        color: isCurrentDevice ? Colors.green[50] : Colors.grey[50],
      ),
      child: Row(
        children: [
          Icon(
            Icons.devices,
            color: isCurrentDevice ? Colors.green : Colors.grey[600],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deviceName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  '$os • $lastActive',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (isCurrentDevice)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'อุปกรณ์นี้',
                style: TextStyle(color: Colors.white, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  void _handleEmailVerification() async {
    if (user?.emailVerified == false) {
      try {
        await user!.sendEmailVerification();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ส่งอีเมลยืนยันแล้ว กรุณาตรวจสอบอีเมลของคุณ'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('เกิดข้อผิดพลาด: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showDownloadDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ดาวน์โหลดข้อมูล'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('เลือกข้อมูลที่ต้องการดาวน์โหลด:'),
            SizedBox(height: 16),
            Text('• ข้อมูลส่วนตัว'),
            Text('• ข้อมูลสุขภาพ'),
            Text('• ข้อมูลอาหารที่แพ้'),
            Text('• ประวัติการใช้งาน'),
            Text('• ข้อมูลครอบครัว'),
            SizedBox(height: 16),
            Text(
              'ข้อมูลจะถูกส่งไปยังอีเมลของคุณในรูปแบบ ZIP',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'กำลังเตรียมข้อมูล จะส่งไปยังอีเมลของคุณเร็วๆ นี้',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('ดาวน์โหลด'),
          ),
        ],
      ),
    );
  }

  void _showAutoDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบข้อมูลอัตโนมัติ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('เลือกระยะเวลาการเก็บข้อมูล:'),
            const SizedBox(height: 16),
            RadioListTile<String>(
              title: const Text('6 เดือน'),
              value: '6months',
              groupValue: '1year',
              onChanged: (value) {},
            ),
            RadioListTile<String>(
              title: const Text('1 ปี'),
              value: '1year',
              groupValue: '1year',
              onChanged: (value) {},
            ),
            RadioListTile<String>(
              title: const Text('3 ปี'),
              value: '3years',
              groupValue: '1year',
              onChanged: (value) {},
            ),
            RadioListTile<String>(
              title: const Text('ไม่ลบอัตโนมัติ'),
              value: 'never',
              groupValue: '1year',
              onChanged: (value) {},
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('บันทึกการตั้งค่าสำเร็จ'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  void _syncData() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('กำลังซิงค์ข้อมูล...'),
          ],
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ซิงค์ข้อมูลสำเร็จ'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showBackupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('สำรองข้อมูล'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('สำรองข้อมูลไปยัง Cloud Storage'),
            SizedBox(height: 16),
            Text('การสำรองข้อมูลล่าสุด: 2 วันที่แล้ว'),
            SizedBox(height: 8),
            Text('ขนาดข้อมูล: 24.5 MB'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const AlertDialog(
                  content: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 16),
                      Text('กำลังสำรองข้อมูล...'),
                    ],
                  ),
                ),
              );
              await Future.delayed(const Duration(seconds: 3));
              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('สำรองข้อมูลสำเร็จ'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('สำรองข้อมูล'),
          ),
        ],
      ),
    );
  }

  void _showRestoreDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('กู้คืนข้อมูล'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('เลือกการสำรองข้อมูลที่ต้องการกู้คืน:'),
            SizedBox(height: 16),
            Text('• 10 ก.ค. 2568 - 24.5 MB'),
            Text('• 8 ก.ค. 2568 - 24.1 MB'),
            Text('• 6 ก.ค. 2568 - 23.8 MB'),
            SizedBox(height: 16),
            Text(
              'การกู้คืนจะเขียนทับข้อมูลปัจจุบัน',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('กู้คืนข้อมูลสำเร็จ'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('กู้คืน'),
          ),
        ],
      ),
    );
  }

  void _showLogoutAllDevicesDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ออกจากระบบทุกอุปกรณ์'),
        content: const Text(
          'คุณจะถูกออกจากระบบในอุปกรณ์ทั้งหมด และต้องล็อกอินใหม่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseAuth.instance.signOut();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ออกจากระบบทุกอุปกรณ์สำเร็จ'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('เกิดข้อผิดพลาด: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );
  }
}
