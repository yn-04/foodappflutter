// lib/welcomeapp/profile_setup_screen.dart
// โปรไฟล์ตั้งต้นหลังสมัครด้วยโทนสีใหม่และภาพหัวกระดาน

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'welcome_theme.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? _email;
  String? _password;
  String? _name;
  String? _phoneNumber;

  final _displayNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _allergyController = TextEditingController();

  String _selectedGender = 'ชาย';
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  final List<String> _genderOptions = ['ชาย', 'หญิง', 'ไม่ระบุ'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _email = args['email'];
      _password = args['password'];
      _name = args['name'];
      _phoneNumber = args['phoneNumber'];

      if ((_name ?? '').isNotEmpty) {
        _displayNameController.text = _name!;
      }
      if ((_phoneNumber ?? '').isNotEmpty) {
        _phoneController.text = _phoneNumber!;
      }
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _phoneController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _allergyController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final now = DateTime.now();
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(1900),
        lastDate: now,
        helpText: 'เลือกวันเกิด',
        cancelText: 'ยกเลิก',
        confirmText: 'เลือก',
        fieldHintText: 'วว/ดด/ปปปป',
        fieldLabelText: 'วันเกิด',
        builder: (BuildContext context, Widget? child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: WelcomeTheme.primary,
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: WelcomeTheme.textPrimary,
              ),
            ),
            child: child!,
          );
        },
      );

      if (!mounted) return;
      if (picked != null && picked != _selectedDate) {
        setState(() => _selectedDate = picked);
      }
    } catch (_) {
      if (!mounted) return;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('ไม่สามารถเปิดปฏิทินได้ กรุณาลองใหม่'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    if (_email == null || _password == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่พบข้อมูลอีเมลและรหัสผ่าน กรุณาเริ่มใหม่'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final displayName = _displayNameController.text.trim();

      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: _email!,
        password: _password!,
      );
      if (!mounted) return;

      await userCredential.user!.updateDisplayName(displayName);
      if (!mounted) return;

      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'email': _email,
        'displayName': displayName,
        'phoneNumber': _phoneController.text.trim(),
        'gender': _selectedGender,
        'birthDate': Timestamp.fromDate(_selectedDate),
        'weight': double.parse(_weightController.text),
        'height': double.parse(_heightController.text),
        'allergies': _allergyController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'profileCompleted': true,
      });
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ลงทะเบียนสำเร็จ!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String errorMessage = 'เกิดข้อผิดพลาดในการลงทะเบียน';
      if (e.code == 'weak-password') {
        errorMessage = 'รหัสผ่านไม่รัดกุมเพียงพอ';
      } else if (e.code == 'email-already-in-use') {
        errorMessage = 'อีเมลนี้มีผู้ใช้งานแล้ว';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'รูปแบบอีเมลไม่ถูกต้อง';
      } else if (e.code == 'network-request-failed') {
        errorMessage = 'มีปัญหาเกี่ยวกับการเชื่อมต่อเครือข่าย';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goBack() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    InputDecoration decoration({
      required String label,
      String? hint,
      IconData? prefixIcon,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
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
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'ข้อมูลลงทะเบียน',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const WelcomeHeader(
                title: 'ครบขั้นตอนภายในไม่กี่นาที',
                subtitle:
                    'บอกข้อมูลสุขภาพเล็กน้อยเพื่อรับคำแนะนำที่เหมาะกับคุณ',
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
                          'ข้อมูลส่วนตัว',
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: WelcomeTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _displayNameController,
                          decoration: decoration(
                            label: 'ชื่อที่ต้องการแสดง',
                            hint: 'เช่น นีน่า, คุณตะวัน',
                            prefixIcon: Icons.person,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'กรุณากรอกชื่อที่ต้องการแสดง';
                            }
                            if (value.trim().length < 2) {
                              return 'กรุณากรอกชื่ออย่างน้อย 2 ตัวอักษร';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedGender,
                          decoration: decoration(
                            label: 'เพศ',
                            prefixIcon: Icons.wc,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          icon: const Icon(Icons.keyboard_arrow_down),
                          items: _genderOptions
                              .map(
                                (v) =>
                                    DropdownMenuItem(value: v, child: Text(v)),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedGender = v ?? 'ไม่ระบุ'),
                        ),
                        const SizedBox(height: 18),
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _selectDate(context),
                          child: InputDecorator(
                            decoration: decoration(
                              label: 'วันเกิด',
                              prefixIcon: Icons.calendar_today,
                            ),
                            child: Text(
                              _formatDate(_selectedDate),
                              style: textTheme.bodyMedium?.copyWith(
                                color: WelcomeTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: decoration(
                            label: 'เบอร์โทรศัพท์ (ถ้ามี)',
                            hint: '08x-xxx-xxxx',
                            prefixIcon: Icons.phone_android_outlined,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _weightController,
                          keyboardType: TextInputType.number,
                          decoration: decoration(
                            label: 'น้ำหนัก (กก.)',
                            prefixIcon: Icons.monitor_weight,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'กรุณากรอกน้ำหนัก';
                            }
                            final weight = double.tryParse(value);
                            if (weight == null || weight <= 0 || weight > 300) {
                              return 'กรุณากรอกน้ำหนักที่ถูกต้อง (1-300 กก.)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _heightController,
                          keyboardType: TextInputType.number,
                          decoration: decoration(
                            label: 'ส่วนสูง (ซม.)',
                            prefixIcon: Icons.height,
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'กรุณากรอกส่วนสูง';
                            }
                            final height = double.tryParse(value);
                            if (height == null || height <= 0 || height > 250) {
                              return 'กรุณากรอกส่วนสูงที่ถูกต้อง (1-250 ซม.)';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _allergyController,
                          maxLines: 3,
                          decoration: decoration(
                            label: 'อาหารที่แพ้ (ถ้ามี)',
                            hint:
                                'ระบุอาหารที่แพ้ เช่น กุ้ง, ถั่ว, นม หรือใส่ "ไม่มี"',
                            prefixIcon: Icons.warning_amber_rounded,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _isLoading ? null : _goBack,
                                style: WelcomeTheme.secondaryButtonStyle,
                                child: const Text('ย้อนกลับ'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isLoading
                                    ? null
                                    : _submitRegistration,
                                style: WelcomeTheme.primaryButtonStyle,
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'ลงทะเบียน',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
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
            ],
          ),
        ),
      ),
    );
  }
}
