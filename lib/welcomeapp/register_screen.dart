// lib/welcomeapp/register_screen.dart
// สมัครสมาชิกด้วยโทนสีใหม่พร้อม header ภาพโลโก้

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'welcome_theme.dart';

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

  final _passFieldKey = GlobalKey<FormFieldState<String>>();
  final _confirmFieldKey = GlobalKey<FormFieldState<String>>();

  final _emailFocus = FocusNode();
  String? _emailError;

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

  Future<bool> _checkEmailInUse({bool showSnackOnError = false}) async {
    final email = _email.text.trim();
    final formatError = _validateEmailFormat(email);
    if (formatError != null) {
      if (mounted) setState(() => _emailError = formatError);
      return false;
    }

    if (!mounted) return false;
    setState(() => _emailError = null);
    return true;
  }

  Future<void> _next() async {
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

    final ok = await _checkEmailInUse(showSnackOnError: true);
    if (!mounted) return;
    if (!ok) {
      setState(() => _loading = false);
      return;
    }
    if (_emailError != null) {
      setState(() => _loading = false);
      _emailFocus.requestFocus();
      return;
    }

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
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    InputDecoration decoration({
      required String label,
      String? hint,
      IconData? prefixIcon,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: WelcomeTheme.fieldFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: WelcomeTheme.primary, width: 1.4),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: WelcomeTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const WelcomeHeader(
                title: 'สร้างบัญชี SmartKitchenAI',
                subtitle: 'จัดการครัวและวางแผนมื้ออาหารได้อย่างมั่นใจ',
                caption:
                    'เพียงไม่กี่ขั้นตอน เราจะช่วยติดตามวัตถุดิบและเมนูที่เหมาะกับคุณ',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Form(
                  key: _formKey,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color.fromARGB(13, 0, 0, 0),
                          blurRadius: 30,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'ข้อมูลสำหรับสมัคร',
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: WelcomeTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _displayName,
                          validator: _validateDisplayName,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.name,
                          inputFormatters: [
                            FilteringTextInputFormatter.deny(RegExp(r'\s')),
                          ],
                          decoration: decoration(
                            label: 'ชื่อที่ต้องการแสดง',
                            hint: 'เช่น Nina, Nutchanon',
                            prefixIcon: Icons.person_outline,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _email,
                          validator: _validateEmailFormat,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.emailAddress,
                          focusNode: _emailFocus,
                          onChanged: (_) {
                            if (_emailError != null) {
                              setState(() => _emailError = null);
                            }
                            _emailDebounce?.cancel();
                            _emailDebounce = Timer(
                              const Duration(milliseconds: 500),
                              () async {
                                if (!mounted) return;
                                final formatOk =
                                    _validateEmailFormat(_email.text) == null;
                                if (formatOk) {
                                  await _checkEmailInUse();
                                }
                              },
                            );
                          },
                          decoration: decoration(
                            label: 'อีเมล',
                            hint: 'example@email.com',
                            prefixIcon: Icons.email_outlined,
                            suffixIcon:
                                (_emailError == null && _email.text.isNotEmpty)
                                ? const Padding(
                                    padding: EdgeInsets.only(right: 12),
                                    child: Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: 20,
                                    ),
                                  )
                                : null,
                          ).copyWith(errorText: _emailError),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          key: _passFieldKey,
                          controller: _pass,
                          validator: _validatePass,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          onChanged: (_) {
                            _confirmFieldKey.currentState?.validate();
                            setState(() {});
                          },
                          textInputAction: TextInputAction.next,
                          obscureText: !_showPass,
                          decoration: decoration(
                            label: 'รหัสผ่าน',
                            prefixIcon: Icons.lock_outline,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPass
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: WelcomeTheme.textSecondary,
                              ),
                              onPressed: () =>
                                  setState(() => _showPass = !_showPass),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          key: _confirmFieldKey,
                          controller: _confirm,
                          validator: _validateConfirm,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          obscureText: !_showConfirm,
                          textInputAction: TextInputAction.done,
                          decoration: decoration(
                            label: 'ยืนยันรหัสผ่าน',
                            prefixIcon: Icons.lock_outline,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showConfirm
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: WelcomeTheme.textSecondary,
                              ),
                              onPressed: () =>
                                  setState(() => _showConfirm = !_showConfirm),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _accept,
                              onChanged: (v) =>
                                  setState(() => _accept = v ?? false),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              activeColor: WelcomeTheme.primary,
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _accept = !_accept),
                                child: Text.rich(
                                  TextSpan(
                                    text: 'ฉันยอมรับ ',
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: WelcomeTheme.textSecondary,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: 'เงื่อนไขการใช้งาน',
                                        style: TextStyle(
                                          color: WelcomeTheme.primary,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                      const TextSpan(text: ' และ '),
                                      TextSpan(
                                        text: 'นโยบายความเป็นส่วนตัว',
                                        style: TextStyle(
                                          color: WelcomeTheme.primary,
                                          fontWeight: FontWeight.w600,
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
                        const SizedBox(height: 28),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            width: 140,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _next,
                              style: WelcomeTheme.primaryButtonStyle,
                              child: _loading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
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
                              style: textTheme.bodyMedium?.copyWith(
                                color: WelcomeTheme.textSecondary,
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pushNamed(context, '/login'),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                foregroundColor: WelcomeTheme.primary,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text('เข้าสู่ระบบ'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
