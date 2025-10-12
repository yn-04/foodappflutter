// screens/account_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app/profile/account_settings/dialogs/change_password_dialog.dart';
import 'package:my_app/profile/account_settings/dialogs/delete_account_dialog.dart';
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
                  // Danger Zone
                  SettingsCard(
                    title: 'พื้นที่อันตราย',
                    items: [
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

  void _showDeleteAccountDialog() {
    showDialog(context: context, builder: (context) => DeleteAccountDialog());
  }

  // Other Methods

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
}
