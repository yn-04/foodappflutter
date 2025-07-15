import 'package:flutter/material.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // ===== Form Controllers และ Keys =====
  final _formKey = GlobalKey<FormState>(); // สำหรับควบคุมและตรวจสอบฟอร์ม
  final _nameController =
      TextEditingController(); // ควบคุม TextField ชื่อ-นามสกุล
  final _emailController = TextEditingController(); // ควบคุม TextField อีเมล
  final _passwordController =
      TextEditingController(); // ควบคุม TextField รหัสผ่าน
  final _confirmPasswordController =
      TextEditingController(); // ควบคุม TextField ยืนยันรหัสผ่าน

  // ===== State Variables =====
  bool _isPasswordVisible = false; // ควบคุมการแสดง/ซ่อนรหัสผ่าน
  bool _isConfirmPasswordVisible = false; // ควบคุมการแสดง/ซ่อนยืนยันรหัสผ่าน
  bool _isLoading = false; // สถานะการโหลดเมื่อกดปุ่มลงทะเบียน
  bool _acceptTerms = false; // สถานะการยอมรับเงื่อนไขการใช้งาน

  // ===== Memory Management =====
  @override
  void dispose() {
    // ทำลาย controllers เมื่อไม่ใช้แล้วเพื่อป้องกัน memory leak
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ===== Validation Functions =====

  /// ตรวจสอบชื่อ-นามสกุล (บังคับให้กรอกทั้งชื่อและนามสกุล)
  String? _validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'กรุณากรอกชื่อ-นามสกุล';
    }

    // ตัดช่องว่างและแยกคำ
    List<String> nameParts = value.trim().split(' ');

    // กรองคำที่ไม่ใช่ช่องว่าง
    nameParts = nameParts.where((part) => part.isNotEmpty).toList();

    // ตรวจสอบว่ามีอย่างน้อย 2 คำ (ชื่อ + นามสกุล)
    if (nameParts.length < 2) {
      return 'กรุณากรอกทั้งชื่อและนามสกุล (คั่นด้วยช่องว่าง)';
    }

    // ตรวจสอบว่าแต่ละคำมีความยาวอย่างน้อย 2 ตัวอักษร
    for (String part in nameParts) {
      if (part.length < 2) {
        return 'ชื่อและนามสกุลต้องมีอย่างน้อย 2 ตัวอักษร';
      }
    }

    return null; // ผ่านการตรวจสอบ
  }

  /// ตรวจสอบรูปแบบอีเมล
  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'กรุณากรอกอีเมล';
    }

    // ใช้ Regular Expression ตรวจสอบรูปแบบอีเมล
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value)) {
      return 'รูปแบบอีเมลไม่ถูกต้อง';
    }

    return null;
  }

  /// ตรวจสอบความแข็งแกร่งของรหัสผ่าน
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'กรุณากรอกรหัสผ่าน';
    }

    // ตรวจสอบความยาวอย่างน้อย 8 ตัวอักษร
    if (value.length < 8) {
      return 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร';
    }

    // ตรวจสอบให้มีตัวพิมพ์เล็ก พิมพ์ใหญ่ และตัวเลข
    if (!RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)').hasMatch(value)) {
      return 'รหัสผ่านต้องมีตัวพิมพ์เล็ก พิมพ์ใหญ่ และตัวเลข';
    }

    return null;
  }

  /// ตรวจสอบการยืนยันรหัสผ่าน
  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'กรุณายืนยันรหัสผ่าน';
    }

    // เปรียบเทียบกับรหัสผ่านที่กรอกไว้
    if (value != _passwordController.text) {
      return 'รหัสผ่านไม่ตรงกัน';
    }

    return null;
  }

  // ===== Main Functions =====

  /// ฟังก์ชันจัดการการลงทะเบียน
  Future<void> _handleRegister() async {
    // ตรวจสอบความถูกต้องของฟอร์ม
    if (!_formKey.currentState!.validate()) {
      return; // หยุดการทำงานถ้าข้อมูลไม่ถูกต้อง
    }

    // ตรวจสอบการยอมรับเงื่อนไขการใช้งาน
    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณายอมรับเงื่อนไขการใช้งาน'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // เริ่มการโหลด
    setState(() {
      _isLoading = true;
    });

    try {
      // แสดงข้อมูลในคอนโซลเพื่อเช็คว่าได้รับข้อมูลจากฟอร์มถูกต้อง
      print(
        'กำลังตรวจสอบข้อมูล: ${_nameController.text} (${_emailController.text})',
      );

      // ตรวจสอบข้อมูลพื้นฐาน
      if (_emailController.text.trim().isEmpty ||
          _passwordController.text.isEmpty) {
        throw Exception('กรุณากรอกข้อมูลให้ครบถ้วน');
      }

      // จำลองการตรวจสอบข้อมูลกับเซิร์ฟเวอร์ (หน่วงเวลา 1 วินาที)
      await Future.delayed(const Duration(seconds: 1));

      // ตรวจสอบว่า Widget ยังอยู่ใน Widget Tree หรือไม่
      if (mounted) {
        // แสดงข้อความสำเร็จ
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ข้อมูลถูกต้อง! กำลังไปหน้าถัดไป'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // ส่งข้อมูลไปหน้าถัดไป (หน้าลงทะเบียนข้อมูลเพิ่มเติม)
        Navigator.pushNamed(
          context,
          '/registerinfor',
          arguments: {
            'name': _nameController.text.trim(),
            'email': _emailController.text.trim(),
            'password': _passwordController.text,
          },
        );
      }
    } catch (e) {
      // จัดการข้อผิดพลาด
      print('เกิดข้อผิดพลาด: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      // หยุดการโหลดเมื่อเสร็จสิ้น
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ===== UI Build Method =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50], // สีพื้นหลังของหน้า
      // ===== App Bar =====
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),

      // ===== Main Body =====
      body: SafeArea(
        child: SingleChildScrollView(
          // ให้สามารถเลื่อนหน้าได้เมื่อคีย์บอร์ดขึ้น
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey, // ผูก Form กับ GlobalKey
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),

                // ===== Header Section =====
                Text(
                  'สร้างบัญชีผู้ใช้',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'กรอกข้อมูลเพื่อเริ่มต้นใช้งาน',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // ===== Name Field (ชื่อ-นามสกุล) =====
                TextFormField(
                  controller: _nameController,
                  validator: _validateName, // ใช้ฟังก์ชันตรวจสอบที่แก้ไขแล้ว
                  keyboardType: TextInputType.name,
                  decoration: InputDecoration(
                    labelText: 'ชื่อ-นามสกุล',
                    hintText: 'เช่น สมชาย ใจดี', // เพิ่ม hint text
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),

                // ===== Email Field =====
                TextFormField(
                  controller: _emailController,
                  validator: _validateEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'อีเมล',
                    hintText: 'example@email.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),

                // ===== Password Field =====
                TextFormField(
                  controller: _passwordController,
                  validator: _validatePassword,
                  obscureText: !_isPasswordVisible, // ซ่อน/แสดงรหัสผ่าน
                  decoration: InputDecoration(
                    labelText: 'รหัสผ่าน',
                    hintText: 'อย่างน้อย 8 ตัวอักษร',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),

                // ===== Confirm Password Field =====
                TextFormField(
                  controller: _confirmPasswordController,
                  validator: _validateConfirmPassword,
                  obscureText: !_isConfirmPasswordVisible,
                  decoration: InputDecoration(
                    labelText: 'ยืนยันรหัสผ่าน',
                    hintText: 'กรอกรหัสผ่านอีกครั้ง',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isConfirmPasswordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _isConfirmPasswordVisible =
                              !_isConfirmPasswordVisible;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),

                // ===== Terms and Conditions Checkbox =====
                Row(
                  children: [
                    Checkbox(
                      value: _acceptTerms,
                      onChanged: (value) {
                        setState(() {
                          _acceptTerms = value ?? false;
                        });
                      },
                      activeColor: Colors.blue,
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _acceptTerms = !_acceptTerms;
                          });
                        },
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

                // ===== Register Button =====
                Align(
                  alignment: Alignment.centerRight, // จัดปุ่มชิดขวา
                  child: SizedBox(
                    width: 120, // กำหนดความกว้างของปุ่ม
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: _isLoading
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

                // ===== Login Link =====
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'มีบัญชีแล้ว? ',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    GestureDetector(
                      onTap: () {
                        // นำทางไปหน้าเข้าสู่ระบบ
                        Navigator.pushNamed(context, '/login');
                      },
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
