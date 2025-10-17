// lib/welcomeapp/register_screen.dart
// เช็คอีเมลซ้ำทั้งแบบเรียลไทม์ และตอนกด "ถัดไป"
// ถ้าอีเมลถูกใช้งาน → โชว์ error ใต้ช่องและ "ไม่ไปหน้า profile-setup"

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();

  // สำหรับ validate แบบเรียลไทม์เฉพาะ field
  final _passFieldKey = GlobalKey<FormFieldState<String>>();
  final _confirmFieldKey = GlobalKey<FormFieldState<String>>();

  // สำหรับแสดง error ใต้ช่องอีเมล ถ้าอีเมลถูกใช้งานแล้ว
  final _emailFocus = FocusNode();
  String? _emailError;

  // debounce สำหรับเช็คอีเมลตอนพิมพ์
  Timer? _emailDebounce;

  bool _showPass = false;
  bool _showConfirm = false;
  bool _loading = false;
  bool _accept = false;

  @override
  void dispose() {
    _displayName.dispose();
    _email.dispose();
    _pass.dispose();
    _confirm.dispose();
    _emailFocus.dispose();
    _emailDebounce?.cancel();
    super.dispose();
  }

  // ===== Validators =====
  String? _validateDisplayName(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'กรุณากรอกชื่อที่ต้องการแสดง';
    if (value.contains(RegExp(r'\s'))) {
      return 'กรุณากรอกชื่อที่ติดกันไม่เว้นวรรค';
    }
    if (value.length < 2) {
      return 'กรุณากรอกชื่ออย่างน้อย 2 ตัวอักษร';
    }
    return null;
  }

  String? _validateEmailFormat(String? v) {
    if (v == null || v.isEmpty) return 'กรุณากรอกอีเมล';
    final re = RegExp(r'^[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}$');
    return re.hasMatch(v) ? null : 'รูปแบบอีเมลไม่ถูกต้อง';
  }

  String? _validatePass(String? v) {
    if (v == null || v.isEmpty) return 'กรุณากรอกรหัสผ่าน';
    if (v.length < 8) return 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร';
    if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(v)) {
      return 'ต้องมีตัวพิมพ์เล็ก/ใหญ่ และตัวเลข';
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'กรุณายืนยันรหัสผ่าน';
    if (v != _pass.text) return 'รหัสผ่านไม่ตรงกัน';
    return null;
  }

  // ===== Email check (validate format + feedback) =====
  Future<bool> _checkEmailInUse({bool showSnackOnError = false}) async {
    final email = _email.text.trim();
    final formatError = _validateEmailFormat(email);
    if (formatError != null) {
      if (mounted) {
        setState(() => _emailError = formatError);
      }
      return false;
    }

    if (!mounted) return false;
    setState(() => _emailError = null);
    return true;
  }

  // ===== Next =====
  Future<void> _next() async {
    // validate ฟอร์ม (ชื่อ/อีเมลฟอร์แมต/รหัสผ่าน)
    if (!_formKey.currentState!.validate()) return;

    if (!_accept) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณายอมรับเงื่อนไขการใช้งาน'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _loading = true);

    // ✅ บังคับเช็คอีเมลซ้ำก่อนจะไปหน้าโปรไฟล์
    final ok = await _checkEmailInUse(showSnackOnError: true);
    if (!mounted) return;
    if (!ok) {
      setState(() => _loading = false);
      return;
    } // 👈 หยุด
    if (_emailError != null) {
      setState(() => _loading = false);
      _emailFocus.requestFocus();
      return;
    }

    // ✅ guard อีกชั้น ถ้า state มี error อยู่ก็ไม่ไป
    if (_emailError != null) {
      if (mounted) setState(() => _loading = false);
      _emailFocus.requestFocus();
      return;
    }

    // ผ่านทั้งหมด → ไปหน้า Profile Setup
    await Navigator.pushNamed(
      context,
      '/profile-setup',
      arguments: {
        'name': _displayName.text.trim(),
        'email': _email.text.trim(),
        'password': _pass.text,
      },
    );

    if (!mounted) return;
    if (mounted) setState(() => _loading = false);
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
                const SizedBox(height: 20),
                Text(
                  'สร้างบัญชีผู้ใช้',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'กรอกข้อมูลเพื่อเริ่มต้นใช้งาน',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 40),

                // ชื่อที่ต้องการแสดง
                TextFormField(
                  controller: _displayName,
                  validator: _validateDisplayName,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.name,
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'ชื่อที่ต้องการแสดง',
                    hintText: 'เช่น Nina, Nutchanon',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),

                // อีเมล (เช็คซ้ำแบบเรียลไทม์)
                TextFormField(
                  controller: _email,
                  validator: _validateEmailFormat,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.emailAddress,
                  focusNode: _emailFocus,
                  onChanged: (_) {
                    // เคลียร์ error ทันทีเมื่อพิมพ์ใหม่
                    if (_emailError != null) {
                      setState(() => _emailError = null);
                    }
                    // debounce เช็คอีเมลซ้ำหลังหยุดพิมพ์ 500ms
                    _emailDebounce?.cancel();
                    _emailDebounce = Timer(
                      const Duration(milliseconds: 500),
                      () async {
                        // ถ้ายังโฟกัสอยู่หรือเพิ่งพิมพ์ แล้วรูปแบบถูกต้อง → เช็ค
                        if (!mounted) return;
                        final formatOk =
                            _validateEmailFormat(_email.text) == null;
                        if (formatOk) {
                          await _checkEmailInUse();
                        }
                      },
                    );
                  },
                  decoration: InputDecoration(
                    labelText: 'อีเมล',
                    hintText: 'example@email.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    suffixIcon: (_emailError == null && _email.text.isNotEmpty)
                        ? const Padding(
                            padding: EdgeInsets.only(right: 12),
                            child: Icon(
                              Icons.check_circle,
                              color: Colors.green,
                              size: 20,
                            ),
                          )
                        : null,
                    errorText: _emailError, // ✅ แสดง error อีเมลซ้ำใต้ช่อง
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),

                // รหัสผ่าน
                TextFormField(
                  key: _passFieldKey,
                  controller: _pass,
                  validator: _validatePass,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  onChanged: (_) {
                    // ให้ช่องยืนยันรหัสผ่าน revalidate ทันที
                    _confirmFieldKey.currentState?.validate();
                    setState(() {});
                  },
                  textInputAction: TextInputAction.next,
                  obscureText: !_showPass,
                  decoration: InputDecoration(
                    labelText: 'รหัสผ่าน',
                    hintText:
                        'อย่างน้อย 8 ตัวอักษร + ตัวพิมพ์เล็ก/ใหญ่ + ตัวเลข',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPass ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),

                // ยืนยันรหัสผ่าน
                TextFormField(
                  key: _confirmFieldKey,
                  controller: _confirm,
                  validator: _validateConfirm,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  onChanged: (_) => _confirmFieldKey.currentState?.validate(),
                  obscureText: !_showConfirm,
                  decoration: InputDecoration(
                    labelText: 'ยืนยันรหัสผ่าน',
                    hintText: 'กรอกรหัสผ่านอีกครั้ง',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showConfirm ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _showConfirm = !_showConfirm),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),

                // Terms
                Row(
                  children: [
                    Checkbox(
                      value: _accept,
                      onChanged: (v) => setState(() => _accept = v ?? false),
                      fillColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return Colors.blue;
                        }
                        return Colors.grey[300];
                      }),
                      checkColor: Colors.white,
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _accept = !_accept),
                        child: Text.rich(
                          TextSpan(
                            text: 'ฉันยอมรับ',
                            style: TextStyle(color: Colors.grey[700]),
                            children: const [
                              TextSpan(
                                text: 'เงื่อนไขการใช้งาน',
                                style: TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                              TextSpan(text: ' และ '),
                              TextSpan(
                                text: 'นโยบายความเป็นส่วนตัว',
                                style: TextStyle(
                                  color: Colors.blue,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 120,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text(
                              'ถัดไป',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'มีบัญชีแล้ว? ',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/login'),
                      child: const Text(
                        'เข้าสู่ระบบ',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
