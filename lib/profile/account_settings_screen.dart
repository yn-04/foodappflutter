// lib/profile/account_settings/account_settings_screen.dart
// Minimal white/black + yellow, ไม่มีม่วง
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ---------- Theme ----------
const kYellow = Color.fromRGBO(251, 192, 45, 1);
const kText = Colors.black87;

// ---------- Screen ----------
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});
  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _auth = FirebaseAuth.instance;
  final _userService = UserService();

  // ===== helpers =====
  String _fmt(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year.toString();
    return '$dd/$mm/$yy';
  }

  void _snackOk(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(m),
          ],
        ),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _snackErr(String m) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(m)),
          ],
        ),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  InputDecoration _input([String? hint]) => InputDecoration(
    hintText: hint,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: Colors.black87),
    ),
  );

  // ===== update inline =====
  Future<void> _updateName(MyUser u) async {
    final ctl = TextEditingController(text: u.displayName);
    final ok = await showDialog<String>(
      context: context,
      builder: (_) => _MiniDialog(
        title: 'แก้ไขชื่อที่ต้องการแสดง',
        child: TextField(
          controller: ctl,
          autofocus: true,
          decoration: _input('เช่น กานต์'),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(context).pop(ctl.text.trim()),
        ),
        onConfirm: () => ctl.text.trim(),
      ),
    );
    if (ok == null) return;
    final name = ok.trim();
    if (name.isEmpty || name.length < 2) {
      _snackErr('โปรดกรอกอย่างน้อย 2 ตัวอักษร');
      return;
    }
    await _userService.updateUserFields(u.id, {
      'displayName': name,
      'profileCompleted': true,
    });
    // sync displayName ไปที่ FirebaseAuth
    await _auth.currentUser?.updateDisplayName(name);
    _snackOk('บันทึกแล้ว');
  }

  Future<void> _updateGender(MyUser u) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (_) => _PickerDialog(
        title: 'เลือกเพศ',
        options: const ['ชาย', 'หญิง', 'อื่นๆ'],
        initial: (u.gender.isNotEmpty ? u.gender : 'ชาย'),
      ),
    );
    if (selected == null) return;
    await _userService.updateUserFields(u.id, {
      'gender': selected,
      'profileCompleted': true,
    });
    _snackOk('บันทึกแล้ว');
  }

  Future<void> _updateBirthDate(MyUser u) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: u.birthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'เลือกวันเกิด',
      cancelText: 'ยกเลิก',
      confirmText: 'เลือก',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.black87,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    await _userService.updateUserFields(u.id, {
      // เซฟเป็น Timestamp เพื่อความเสถียร
      'birthDate': Timestamp.fromDate(picked),
      'profileCompleted': true,
    });
    _snackOk('บันทึกแล้ว');
  }

  Future<void> _changePassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChangePasswordDialog(),
    );
    if (ok == true) _snackOk('เปลี่ยนรหัสผ่านสำเร็จ');
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (ok == true && mounted) {
      _snackOk('ลบบัญชีสำเร็จ');
      Navigator.of(context).maybePop();
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final u = _auth.currentUser;
    if (u == null) {
      return const Scaffold(body: Center(child: Text('ยังไม่ได้เข้าสู่ระบบ')));
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'การตั้งค่าบัญชี',
          style: TextStyle(color: kText, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: kText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<MyUser?>(
        stream: _userService.streamUser(u.uid),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(Colors.grey),
              ),
            );
          }
          if (snap.hasError) {
            return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
          }
          final my =
              snap.data ??
              MyUser(
                id: u.uid,
                email: u.email ?? '',
                displayName: u.displayName ?? '',
                gender: 'ชาย',
                birthDate: null,
                createdAt: u.metadata.creationTime ?? DateTime.now(),
                profileCompleted: false,
              );

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ===== 1) ข้อมูลส่วนตัว (แก้ได้) =====
              _Section(
                title: "ข้อมูลส่วนตัว",
                children: [
                  _Item(
                    icon: Icons.person_outline,
                    title: "ชื่อที่ต้องการแสดง",
                    subtitle: my.displayName.isNotEmpty
                        ? my.displayName
                        : 'ไม่ระบุ',
                    onTap: () => _updateName(my),
                  ),
                  _Item(
                    icon: Icons.wc,
                    title: "เพศ",
                    subtitle: (my.gender.isNotEmpty ? my.gender : 'ไม่ระบุ'),
                    onTap: () => _updateGender(my),
                  ),
                  _Item(
                    icon: Icons.cake_outlined,
                    title: "วันเกิด",
                    subtitle: my.birthDate != null
                        ? _fmt(my.birthDate!)
                        : 'ไม่ระบุ',
                    onTap: () => _updateBirthDate(my),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ===== 2) ข้อมูลบัญชี (ดูอย่างเดียว) =====
              _Section(
                title: "ข้อมูลบัญชี",
                children: [
                  _Item(
                    icon: Icons.email_outlined,
                    title: "อีเมล",
                    subtitle: my.email.isNotEmpty ? my.email : '-',
                    enabled: false, // ดูอย่างเดียว
                  ),
                  _Item(
                    icon: Icons.today_outlined,
                    title: "วันที่เข้าร่วม",
                    subtitle: _fmt(
                      my.createdAt ??
                          (u.metadata.creationTime ?? DateTime.now()),
                    ),
                    enabled: false,
                  ),
                  _Item(
                    icon: Icons.login,
                    title: "วิธีการล็อกอิน",
                    subtitle: _loginMethodLabel(u),
                    enabled: false,
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ===== 3) ความปลอดภัย =====
              _Section(
                title: "ความปลอดภัย",
                children: [
                  _Item(
                    icon: Icons.lock_outline,
                    title: "เปลี่ยนรหัสผ่าน",
                    subtitle: "อัปเดตรหัสผ่าน",
                    onTap: _changePassword,
                  ),
                  _Item(
                    icon: Icons.delete_forever_rounded,
                    title: "ลบบัญชีผู้ใช้",
                    subtitle: "ลบถาวรและไม่สามารถกู้คืนได้",
                    iconColor: Colors.red[700],
                    onTap: _deleteAccount,
                  ),
                  _Item(
                    icon: Icons.exit_to_app_rounded,
                    title: "ออกจากระบบ",
                    subtitle: "ออกจากระบบบนอุปกรณ์นี้",
                    onTap: () async {
                      await _auth.signOut();
                      if (!mounted) return;
                      Navigator.of(
                        context,
                      ).pushNamedAndRemoveUntil('/login', (route) => false);
                    },
                  ),
                ],
              ),

              const SizedBox(height: 60),
            ],
          );
        },
      ),
    );
  }

  String _loginMethodLabel(User u) {
    final providers = u.providerData.map((p) => p.providerId).toList();
    if (providers.contains('password')) return 'อีเมล/รหัสผ่าน';
    if (providers.contains('google.com')) return 'Google';
    if (providers.contains('facebook.com')) return 'Facebook';
    if (providers.contains('apple.com')) return 'Apple';
    return providers.isEmpty ? '-' : providers.join(', ');
  }
}

// ---------- Subwidgets ----------
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.grey[300]!),
    ),
    child: Column(
      children: [
        ListTile(
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: kText,
              fontSize: 14,
            ),
          ),
        ),
        const Divider(height: 1),
        ..._withDividers(children),
      ],
    ),
  );

  List<Widget> _withDividers(List<Widget> items) {
    final out = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      out.add(items[i]);
      if (i != items.length - 1) {
        out.add(Divider(height: 1, color: Colors.grey[200]));
      }
    }
    return out;
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Color? iconColor;
  final bool enabled;

  const _Item({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.iconColor,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: iconColor ?? kText),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w600, color: kText),
    ),
    subtitle: Text(subtitle),
    trailing: enabled
        ? const Icon(Icons.chevron_right, color: Colors.grey)
        : null,
    onTap: enabled ? onTap : null,
    enabled: enabled,
  );
}

// ---------- Dialogs ----------
class _MiniDialog extends StatelessWidget {
  const _MiniDialog({
    required this.title,
    required this.child,
    required this.onConfirm,
  });
  final String title;
  final Widget child;
  final String? Function()? onConfirm;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: kText,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.black87),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.06),
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: Colors.black87),
                  child: const Text('ยกเลิก'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final v = onConfirm!();
                    if (v != null) Navigator.of(context).pop(v);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: kYellow,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('บันทึก'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerDialog extends StatefulWidget {
  const _PickerDialog({
    required this.title,
    required this.options,
    this.initial,
  });
  final String title;
  final List<String> options;
  final String? initial;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  late String _selected;
  @override
  void initState() {
    super.initState();
    _selected = widget.initial ?? widget.options.first;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: kText,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.black87),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.06),
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final opt in widget.options)
              RadioListTile<String>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(opt, style: const TextStyle(color: kText)),
                value: opt,
                groupValue: _selected,
                activeColor: Colors.black,
                onChanged: (v) => setState(() => _selected = v!),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: Colors.black87),
                  child: const Text('ยกเลิก'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_selected),
                  style: FilledButton.styleFrom(
                    backgroundColor: kYellow,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('บันทึก'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Change password / Delete account ----------
class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();
  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AccountService.changePassword(
        currentPassword: _current.text.trim(),
        newPassword: _new.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เปลี่ยนรหัสผ่านไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'เปลี่ยนรหัสผ่าน',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: kText,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close, color: Colors.black87),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.06),
                      shape: const CircleBorder(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _pwdField(_current, 'รหัสผ่านปัจจุบัน'),
              const SizedBox(height: 10),
              _pwdField(
                _new,
                'รหัสผ่านใหม่',
                validator: (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'กรุณากรอกรหัสผ่านใหม่';
                  if (s.length < 6) return 'อย่างน้อย 6 ตัวอักษร';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              _pwdField(
                _confirm,
                'ยืนยันรหัสผ่านใหม่',
                validator: (v) {
                  return (v ?? '').trim() != _new.text.trim()
                      ? 'รหัสผ่านไม่ตรงกัน'
                      : null;
                },
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Checkbox(
                    value: _show,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _show = v ?? false),
                    activeColor: Colors.black,
                    checkColor: Colors.white,
                  ),
                  const Text('แสดงรหัสผ่าน', style: TextStyle(color: kText)),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black87,
                    ),
                    child: const Text('ยกเลิก'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: kYellow,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.black,
                              ),
                            ),
                          )
                        : const Text(
                            'บันทึก',
                            style: TextStyle(color: Colors.black),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pwdField(
    TextEditingController c,
    String label, {
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: c,
      obscureText: !_show,
      validator:
          validator ?? (v) => (v == null || v.isEmpty) ? 'กรุณากรอก' : null,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        labelStyle: const TextStyle(color: Colors.black87),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.black87),
        ),
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await AccountService.deleteAccount(password: _password.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ลบบัญชีไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ลบบัญชีผู้ใช้',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: kText,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'การลบบัญชีเป็นการลบถาวรและไม่สามารถกู้คืนได้ โปรดยืนยันรหัสผ่านของคุณ',
                style: TextStyle(color: kText),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: !_show,
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'กรุณากรอกรหัสผ่าน' : null,
                decoration: InputDecoration(
                  labelText: 'รหัสผ่าน',
                  filled: true,
                  fillColor: Colors.white,
                  labelStyle: const TextStyle(color: Colors.black87),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.black87),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _show,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _show = v ?? false),
                    activeColor: Colors.black,
                    checkColor: Colors.white,
                  ),
                  const Text('แสดงรหัสผ่าน', style: TextStyle(color: kText)),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black87,
                    ),
                    child: const Text('ยกเลิก'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('ลบบัญชี'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Services & Model ----------
class UserService {
  final _fs = FirebaseFirestore.instance;

  // realtime stream
  Stream<MyUser?> streamUser(String uid) {
    return _fs.collection('users').doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = uid;
      return MyUser.fromMap(data);
    });
  }

  Future<MyUser?> getUserById(String uid) async {
    final doc = await _fs.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    data['id'] = uid;
    return MyUser.fromMap(data);
  }

  Future<bool> updateUser(String uid, MyUser updated) async {
    try {
      await _fs
          .collection('users')
          .doc(uid)
          .set(updated.toMap(), SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> updateUserFields(String uid, Map<String, dynamic> patch) async {
    await _fs.collection('users').doc(uid).set(patch, SetOptions(merge: true));
  }
}

class MyUser {
  final String id;
  final String email;
  final String displayName;
  final String gender;
  final DateTime? birthDate;
  final DateTime? createdAt;
  final bool profileCompleted;

  const MyUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.gender,
    required this.birthDate,
    required this.createdAt,
    required this.profileCompleted,
  });

  int? get age {
    if (birthDate == null) return null;
    final now = DateTime.now();
    var a = now.year - birthDate!.year;
    final md = DateTime(now.year, birthDate!.month, birthDate!.day);
    if (now.isBefore(md)) a -= 1;
    return a;
  }

  MyUser copyWith({
    String? id,
    String? email,
    String? displayName,
    String? gender,
    DateTime? birthDate,
    DateTime? createdAt,
    bool? profileCompleted,
  }) {
    return MyUser(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
      createdAt: createdAt ?? this.createdAt,
      profileCompleted: profileCompleted ?? this.profileCompleted,
    );
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
    return null;
  }

  factory MyUser.fromMap(Map<String, dynamic> map) {
    return MyUser(
      id: (map['id'] ?? '').toString(),
      email: (map['email'] ?? '').toString(),
      displayName: (map['displayName'] ?? '').toString(),
      gender: (map['gender'] ?? 'ชาย').toString(),
      birthDate: _parseDate(map['birthDate']),
      createdAt: _parseDate(map['createdAt']),
      profileCompleted: (map['profileCompleted'] ?? false) == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'gender': gender,
      // บันทึกเป็น ISO string ถ้าอยากจะเก็บเป็นข้อความ
      // ถ้าต้องการบันทึกเป็น Timestamp ให้ใช้ Timestamp.fromDate ตอนเซฟ (เหมือนที่ updateUserFields ทำ)
      'birthDate': birthDate?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'profileCompleted': profileCompleted,
    };
  }
}

class AccountService {
  static final _auth = FirebaseAuth.instance;

  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('ยังไม่ได้เข้าสู่ระบบ');
    }
    final cred = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(cred);
    await user.updatePassword(newPassword);
  }

  static Future<void> deleteAccount({required String password}) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw Exception('ยังไม่ได้เข้าสู่ระบบ');
    }
    final cred = EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
    await user.reauthenticateWithCredential(cred);
    await user.delete();
  }
}
