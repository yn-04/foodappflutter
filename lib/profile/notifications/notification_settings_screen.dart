// lib/profile/notifications/notification_settings_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
// (ทางเลือก) ถ้ามี firebase_messaging ให้เปิดคอมเมนต์บรรทัดถัดไป
// import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _loading = true;
  bool _saving = false;

  // Toggles
  bool enablePush = true;
  bool enableInApp = true;
  bool enableEmail = false;

  // Topics / Categories
  bool topicExpiring = true; // วัตถุดิบใกล้หมดอายุ
  bool topicRecipes = true; // สูตร/เมนูใหม่
  bool topicShopping = true; // เตือนรายการซื้อของ
  bool topicFamily = false; // กิจกรรมบัญชีครอบครัว
  bool topicSystem = true; // อัปเดตระบบ/ข่าวสาร

  // Quiet Hours
  bool quietHoursEnabled = false;
  TimeOfDay quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay quietEnd = const TimeOfDay(hour: 7, minute: 0);

  // Daily Digest
  bool digestEnabled = false;
  TimeOfDay digestTime = const TimeOfDay(hour: 9, minute: 0);

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('No user');

      final doc = await _fs
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notifications')
          .get();
      final data = doc.data();

      if (data != null) {
        enablePush = (data['enablePush'] as bool?) ?? enablePush;
        enableInApp = (data['enableInApp'] as bool?) ?? enableInApp;
        enableEmail = (data['enableEmail'] as bool?) ?? enableEmail;

        final topics = (data['topics'] as Map<String, dynamic>?) ?? {};
        topicExpiring = (topics['expiring'] as bool?) ?? topicExpiring;
        topicRecipes = (topics['recipes'] as bool?) ?? topicRecipes;
        topicShopping = (topics['shopping'] as bool?) ?? topicShopping;
        topicFamily = (topics['family'] as bool?) ?? topicFamily;
        topicSystem = (topics['system'] as bool?) ?? topicSystem;

        final quiet = (data['quietHours'] as Map<String, dynamic>?) ?? {};
        quietHoursEnabled = (quiet['enabled'] as bool?) ?? quietHoursEnabled;
        final qs = (quiet['start'] as String?) ?? _fmt(quietStart);
        final qe = (quiet['end'] as String?) ?? _fmt(quietEnd);
        quietStart = _parseTime(qs) ?? quietStart;
        quietEnd = _parseTime(qe) ?? quietEnd;

        final digest = (data['dailyDigest'] as Map<String, dynamic>?) ?? {};
        digestEnabled = (digest['enabled'] as bool?) ?? digestEnabled;
        final dt = (digest['time'] as String?) ?? _fmt(digestTime);
        digestTime = _parseTime(dt) ?? digestTime;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('โหลดการตั้งค่าไม่สำเร็จ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('No user');

      final data = {
        'enablePush': enablePush,
        'enableInApp': enableInApp,
        'enableEmail': enableEmail,
        'topics': {
          'expiring': topicExpiring,
          'recipes': topicRecipes,
          'shopping': topicShopping,
          'family': topicFamily,
          'system': topicSystem,
        },
        'quietHours': {
          'enabled': quietHoursEnabled,
          'start': _fmt(quietStart),
          'end': _fmt(quietEnd),
        },
        'dailyDigest': {'enabled': digestEnabled, 'time': _fmt(digestTime)},
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _fs
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('notifications')
          .set(data, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกการตั้งค่าแล้ว'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // (ทางเลือก) สมัคร/ยกเลิก topic ของ FCM ตามสวิตช์
      // final fcm = FirebaseMessaging.instance;
      // if (topicRecipes) await fcm.subscribeToTopic('recipes'); else await fcm.unsubscribeFromTopic('recipes');
      // if (topicExpiring) await fcm.subscribeToTopic('expiring'); else await fcm.unsubscribeFromTopic('expiring');
      // if (topicShopping) await fcm.subscribeToTopic('shopping'); else await fcm.unsubscribeFromTopic('shopping');
      // if (topicFamily) await fcm.subscribeToTopic('family'); else await fcm.unsubscribeFromTopic('family');
      // if (topicSystem) await fcm.subscribeToTopic('system'); else await fcm.unsubscribeFromTopic('system');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('บันทึกไม่สำเร็จ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestPermission() async {
    // ถ้าใช้ firebase_messaging ให้เปิดใช้โค้ดด้านล่าง
    // try {
    //   final settings = await FirebaseMessaging.instance.requestPermission(
    //     alert: true, badge: true, sound: true,
    //     provisional: false,
    //   );
    //   if (mounted) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       SnackBar(content: Text('Notification permission: ${settings.authorizationStatus}')),
    //     );
    //   }
    // } catch (e) {
    //   if (mounted) {
    //     ScaffoldMessenger.of(context).showSnackBar(
    //       SnackBar(content: Text('ขอสิทธิ์การแจ้งเตือนล้มเหลว: $e'), backgroundColor: Colors.red),
    //     );
    //   }
    // }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'เพิ่ม firebase_messaging แล้วเปิดคอมเมนต์ในโค้ดเพื่อขอสิทธิ์แจ้งเตือน',
          ),
        ),
      );
    }
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  TimeOfDay? _parseTime(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _pickTime({required bool isQuietStart}) async {
    final initial = isQuietStart ? quietStart : quietEnd;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isQuietStart) {
          quietStart = picked;
        } else {
          quietEnd = picked;
        }
      });
    }
  }

  Future<void> _pickDigestTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: digestTime,
    );
    if (picked != null) {
      setState(() => digestTime = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text(
          'การแจ้งเตือน',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.grey[100],
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
            color: Colors.black,
            tooltip: 'บันทึก',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : RefreshIndicator(
              onRefresh: _load,
              color: Colors.black,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: 'ช่องทางการแจ้งเตือน',
                    children: [
                      _tileSwitch(
                        'Push Notifications',
                        'แจ้งเตือนผ่านมือถือ',
                        enablePush,
                        (v) => setState(() => enablePush = v),
                      ),
                      _divider(),
                      _tileSwitch(
                        'In-App Alerts',
                        'แบนเนอร์ภายในแอป',
                        enableInApp,
                        (v) => setState(() => enableInApp = v),
                      ),
                      _divider(),
                      _tileSwitch(
                        'อีเมล',
                        'สรุป/ข่าวสารส่งอีเมล',
                        enableEmail,
                        (v) => setState(() => enableEmail = v),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: OutlinedButton.icon(
                          onPressed: _requestPermission,
                          icon: const Icon(Icons.notifications_active_outlined),
                          label: const Text(
                            'ขอสิทธิ์การแจ้งเตือน / ตรวจสอบสถานะ',
                          ),
                        ),
                      ),
                    ],
                  ),

                  _sectionCard(
                    title: 'ประเภทการแจ้งเตือน',
                    children: [
                      _tileSwitch(
                        'วัตถุดิบใกล้หมดอายุ',
                        null,
                        topicExpiring,
                        (v) => setState(() => topicExpiring = v),
                      ),
                      _divider(),
                      _tileSwitch(
                        'สูตร/เมนูใหม่ที่เหมาะกับคุณ',
                        null,
                        topicRecipes,
                        (v) => setState(() => topicRecipes = v),
                      ),
                      _divider(),
                      _tileSwitch(
                        'เตือนรายการซื้อของ',
                        null,
                        topicShopping,
                        (v) => setState(() => topicShopping = v),
                      ),
                      _divider(),
                      _tileSwitch(
                        'กิจกรรมของบัญชีครอบครัว',
                        null,
                        topicFamily,
                        (v) => setState(() => topicFamily = v),
                      ),
                      _divider(),
                      _tileSwitch(
                        'อัปเดตระบบ/เวอร์ชัน',
                        null,
                        topicSystem,
                        (v) => setState(() => topicSystem = v),
                      ),
                    ],
                  ),

                  _sectionCard(
                    title: 'ช่วงเงียบ (Quiet Hours)',
                    children: [
                      _tileSwitch(
                        'เปิดช่วงเงียบ',
                        'ปิดเสียงแจ้งเตือนในช่วงที่กำหนด',
                        quietHoursEnabled,
                        (v) => setState(() => quietHoursEnabled = v),
                      ),
                      if (quietHoursEnabled) ...[
                        _divider(),
                        _timeRow(
                          label: 'เริ่ม',
                          value: _fmt(quietStart),
                          onTap: () => _pickTime(isQuietStart: true),
                        ),
                        _divider(),
                        _timeRow(
                          label: 'สิ้นสุด',
                          value: _fmt(quietEnd),
                          onTap: () => _pickTime(isQuietStart: false),
                        ),
                      ],
                    ],
                  ),

                  _sectionCard(
                    title: 'สรุปรายวัน (Daily Digest)',
                    children: [
                      _tileSwitch(
                        'เปิดสรุปรายวัน',
                        'รับสรุปรายการสำคัญประจำวัน',
                        digestEnabled,
                        (v) => setState(() => digestEnabled = v),
                      ),
                      if (digestEnabled) ...[
                        _divider(),
                        _timeRow(
                          label: 'เวลาส่ง',
                          value: _fmt(digestTime),
                          onTap: _pickDigestTime,
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _saving ? null : _save,
                      icon: const Icon(Icons.save),
                      label: const Text('บันทึกการตั้งค่า'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _divider() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    height: 1,
    color: Colors.grey[200],
  );

  Widget _tileSwitch(
    String title,
    String? subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: value,
        onChanged: onChanged,
        activeColor: Colors.black,
      ),
    );
  }

  Widget _timeRow({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(color: Colors.black54)),
          const SizedBox(width: 8),
          Icon(Icons.schedule, color: Colors.grey[600], size: 20),
        ],
      ),
      onTap: onTap,
    );
  }
}
