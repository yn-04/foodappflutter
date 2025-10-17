// ignore_for_file: use_build_context_synchronously
//lib/welcomeapp/login_screen.dart2
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPass = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final email = _email.text.trim();
      final password = _password.text;
      // 2) ล็อกอินจริง
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) return; // กัน context หลุด
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } on FirebaseAuthException catch (e) {
      debugPrint('[AUTH] signIn error code=${e.code}, message=${e.message}');
      var msg = 'เข้าสู่ระบบไม่สำเร็จ';
      switch (e.code) {
        case 'user-not-found':
          msg = 'ไม่พบบัญชีผู้ใช้นี้';
          break;
        case 'wrong-password':
          msg = 'รหัสผ่านไม่ถูกต้อง';
          break;
        case 'invalid-email':
          msg = 'อีเมลไม่ถูกต้อง';
          break;
        case 'user-disabled':
          msg = 'บัญชีนี้ถูกปิดการใช้งาน';
          break;
        case 'too-many-requests':
          msg = 'พยายามมากเกินไป โปรดลองใหม่ภายหลัง';
          break;
        case 'network-request-failed':
          msg = 'เชื่อมต่อเครือข่ายล้มเหลว';
          break;
        case 'invalid-credential':
          msg = 'ข้อมูลรับรองไม่ถูกต้อง';
          break;
        case 'operation-not-allowed':
          msg = 'ยังไม่เปิดใช้งาน Email/Password ใน Console';
          break;
        case 'no-password-provider': // ✅ แยกเคสนี้ให้ชัด
          msg = e.message ?? 'อีเมลนี้ยังไม่ได้ตั้งรหัสผ่าน';
          break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      debugPrint('[AUTH] signIn other error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เข้าสู่ระบบไม่สำเร็จ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showResetSentSheet(String email) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ResetSentSheet(email: email),
    );
  }

  Future<void> _showPasswordResetDialog() async {
    // เตรียม messenger ไว้ใช้หลัง await โดยไม่พึ่ง context ตรง ๆ
    final messenger = ScaffoldMessenger.maybeOf(context);

    // กันเฟรมปัจจุบันให้จบก่อน
    await Future.microtask(() {});

    String tempEmail = _email.text.trim();
    final formKey = GlobalKey<FormState>();

    // — Dialog มินิมอล —
    final submitted = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'ลืมรหัสผ่าน',
            style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          content: Form(
            key: formKey,
            child: TextFormField(
              initialValue: tempEmail,
              onChanged: (v) => tempEmail = v.trim(),
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: 'อีเมล',
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  // ไม่มีม่วง
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Colors.black87,
                    width: 1.2,
                  ),
                ),
              ),
              validator: (v) {
                final s = (v ?? '').trim();
                if (s.isEmpty) return 'กรุณากรอกอีเมล';
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(s)) {
                  return 'รูปแบบอีเมลไม่ถูกต้อง';
                }
                return null;
              },
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () {
                FocusScope.of(dialogContext).unfocus();
                Navigator.of(dialogContext).pop();
              },
              style: TextButton.styleFrom(foregroundColor: Colors.black87),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  FocusScope.of(dialogContext).unfocus();
                  Navigator.of(dialogContext).pop(tempEmail);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black, // ปุ่มดำ มินิมอล
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
              child: const Text('ส่งลิงก์รีเซ็ต'),
            ),
          ],
        );
      },
    );

    if (submitted == null) return;

    // ให้ dialog ปิดและ IME ซ่อนให้เรียบร้อย
    await Future.microtask(() {});

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: submitted);
      if (!mounted) return;
      _showResetSentSheet(submitted); // << เรียกแผ่นล่างที่นี่
    } on FirebaseAuthException catch (e) {
      var msg = 'ไม่สามารถส่งลิงก์รีเซ็ตรหัสผ่านได้';
      if (e.code == 'user-not-found') msg = 'ไม่พบบัญชีผู้ใช้นี้';
      if (e.code == 'invalid-email') msg = 'อีเมลไม่ถูกต้อง';

      WidgetsBinding.instance.addPostFrameCallback((_) {
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          SnackBar(
            backgroundColor: Colors.red[700],
            content: Text(msg, style: const TextStyle(color: Colors.white)),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 30),
                Text(
                  'ยินดีต้อนรับ!',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'กรุณาเข้าสู่ระบบเพื่อเริ่มต้นใช้งาน',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 40),

                TextFormField(
                  controller: _email,
                  decoration: InputDecoration(
                    labelText: 'อีเมล',
                    prefixIcon: const Icon(Icons.email_outlined),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'กรุณากรอกอีเมล' : null,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _password,
                  obscureText: !_showPass,
                  decoration: InputDecoration(
                    labelText: 'รหัสผ่าน',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPass ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'กรุณากรอกรหัสผ่าน' : null,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _showPasswordResetDialog,
                    style: TextButton.styleFrom(foregroundColor: Colors.blue),
                    child: const Text('ลืมรหัสผ่าน?'),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          )
                        : const Text(
                            'เข้าสู่ระบบ',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'ยังไม่มีบัญชี? ',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/register'),
                      child: const Text(
                        'ลงทะเบียน',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ResetSentSheet extends StatefulWidget {
  final String email;
  const ResetSentSheet({super.key, required this.email});

  @override
  State<ResetSentSheet> createState() => _ResetSentSheetState();
}

class _ResetSentSheetState extends State<ResetSentSheet> {
  int secondsLeft = 60;
  bool sending = false;
  bool justSent = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  void _startCooldown() {
    _t?.cancel();
    setState(() => secondsLeft = 60);
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        secondsLeft--;
        if (secondsLeft <= 0) t.cancel();
      });
    });
  }

  Future<void> _resend() async {
    if (sending || secondsLeft > 0) return;
    setState(() {
      sending = true;
      justSent = false;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: widget.email);
      setState(() => justSent = true);
      _startCooldown();
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.mark_email_read_outlined, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'ส่งลิงก์รีเซ็ตรหัสผ่านแล้ว',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.email,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
          ),
          const SizedBox(height: 16),
          const _TipRow(
            icon: Icons.inbox_outlined,
            text: 'ลองเช็กใน Spam/Promotions',
          ),
          const SizedBox(height: 8),
          const _TipRow(
            icon: Icons.check_circle_outline,
            text: 'กด “ไม่ใช่สแปม” เพื่อให้ครั้งต่อไปเข้า Inbox',
          ),
          const SizedBox(height: 8),
          const _TipRow(
            icon: Icons.refresh_outlined,
            text: 'ถ้ายังไม่เจอ ลองส่งอีกครั้งด้านล่าง',
          ),
          if (justSent) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[100]!),
              ),
              child: Row(
                children: const [
                  Icon(Icons.check_rounded, size: 20, color: Colors.green),
                  SizedBox(width: 8),
                  Expanded(child: Text('ส่งอีกครั้งแล้ว')),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: (sending || secondsLeft > 0) ? null : _resend,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black, // โทนมินิมอล ไม่ม่วง
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      secondsLeft > 0
                          ? 'ส่งอีกครั้งได้ใน ${secondsLeft}s'
                          : 'ส่งอีกครั้ง',
                    ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[700]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
          ),
        ),
      ],
    );
  }
}
