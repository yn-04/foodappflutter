import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
<<<<<<< HEAD
import 'package:my_app/register/home.dart';
import 'package:my_app/register/register.dart';
=======
import 'package:my_app/welcomeapp/home.dart';
import 'package:my_app/welcomeapp/register.dart';
>>>>>>> 042b438647d2fd2dde10ec244616df775c0d9cde

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ลงทะเบียน',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Kanit',
        useMaterial3: true,
      ),

      // กำหนดหน้าเริ่มต้น
      initialRoute: '/register',

      // เพิ่ม routes ทั้งหมด
      routes: {
        '/register': (context) => RegisterScreen(),
        '/registerinfor': (context) => Registerinfor(),
        '/home': (context) => HomeScreen(), // หน้าหลักหลังลงทะเบียนเสร็จ
      },
    );
  }
}

class Registerinfor extends StatefulWidget {
  const Registerinfor({Key? key}) : super(key: key);

  @override
  _RegistrationPageState createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<Registerinfor> {
  final _formKey = GlobalKey<FormState>();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ข้อมูลจากหน้าก่อนหน้า
  String? _email;
  String? _password;
  String? _name;
  String? _phoneNumber;

  // Controllers
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _allergyController = TextEditingController();

  // Variables
  String _selectedGender = 'ชาย';
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  final List<String> _genderOptions = ['ชาย', 'หญิง', 'ไม่ระบุ'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // รับข้อมูลจากหน้าก่อนหน้า
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _email = args['email'];
      _password = args['password'];
      _name = args['name'];
      _phoneNumber = args['phoneNumber'];

      // ตั้งค่าชื่อและเบอร์โทรจากหน้าก่อนหน้า
      if (_name != null && _name!.isNotEmpty) {
        _fullNameController.text = _name!;
      }
      if (_phoneNumber != null && _phoneNumber!.isNotEmpty) {
        _phoneController.text = _phoneNumber!;
      }
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _allergyController.dispose();
    super.dispose();
  }

  // ฟังก์ชันสำหรับแสดงปฏิทินแบบ ค.ศ.
  Future<void> _selectDate(BuildContext context) async {
    try {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(1900),
        lastDate: DateTime.now(),
        helpText: 'เลือกวันเกิด',
        cancelText: 'ยกเลิก',
        confirmText: 'เลือก',
        fieldHintText: 'วว/ดด/ปปปป',
        fieldLabelText: 'วันเกิด',
        builder: (BuildContext context, Widget? child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: Colors.blue[600]!,
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null && picked != _selectedDate) {
        setState(() {
          _selectedDate = picked;
        });
      }
    } catch (e) {
      print('Error selecting date: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่สามารถเปิดปฏิทินได้ กรุณาลองใหม่'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ฟังก์ชันสำหรับ format วันที่เป็น ค.ศ.
  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
  }

  // ฟังก์ชันแยกชื่อและนามสกุล
  Map<String, String> _splitFullName(String fullName) {
    List<String> nameParts = fullName.trim().split(' ');

    if (nameParts.length == 1) {
      return {'firstName': nameParts[0], 'lastName': ''};
    } else if (nameParts.length >= 2) {
      return {
        'firstName': nameParts[0],
        'lastName': nameParts.sublist(1).join(' '),
      };
    } else {
      return {'firstName': fullName, 'lastName': ''};
    }
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_email == null || _password == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่พบข้อมูลอีเมลและรหัสผ่าน กรุณาเริ่มใหม่'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // แยกชื่อและนามสกุล
      Map<String, String> nameData = _splitFullName(_fullNameController.text);
      String firstName = nameData['firstName']!;
      String lastName = nameData['lastName']!;

      // สร้างบัญชีผู้ใช้ใน Firebase Authentication
      UserCredential userCredential = await _auth
          .createUserWithEmailAndPassword(email: _email!, password: _password!);

      print('สร้างบัญชีผู้ใช้สำเร็จ UID: ${userCredential.user!.uid}');

      // อัปเดตชื่อในโปรไฟล์ Firebase Authentication
      await userCredential.user!.updateDisplayName(
        _fullNameController.text.trim(),
      );

      // ส่งอีเมลยืนยันตัวตน
      await userCredential.user!.sendEmailVerification();

      // บันทึกข้อมูลเพิ่มเติมใน Firestore
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'email': _email,
        'firstName': firstName,
        'lastName': lastName,
        'fullName': _fullNameController.text.trim(),
        'phoneNumber': _phoneController.text.trim(),
        'gender': _selectedGender,
        'birthDate': Timestamp.fromDate(_selectedDate),
        'weight': double.parse(_weightController.text),
        'height': double.parse(_heightController.text),
        'allergies': _allergyController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'profileCompleted': true,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ลงทะเบียนสำเร็จ! กรุณาตรวจสอบอีเมลเพื่อยืนยันตัวตน'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // นำทางไปหน้าหลักหลังลงทะเบียนเสร็จ
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } on FirebaseAuthException catch (e) {
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
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _goBack() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'ข้อมูลลงทะเบียน',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // Full Name Field (ชื่อ-นามสกุล)
              TextFormField(
                controller: _fullNameController,
                decoration: InputDecoration(
                  labelText: 'ชื่อ-นามสกุล',
                  prefixIcon: const Icon(Icons.person, color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[600]!),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  hintText: 'เช่น ภาสกร จิรวัฒน์',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอกชื่อ-นามสกุล';
                  }
                  if (value.trim().split(' ').length < 2) {
                    return 'กรุณากรอกทั้งชื่อและนามสกุล';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Phone Number Field (ไม่บังคับ)
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'เบอร์โทรศัพท์ (ไม่บังคับ)',
                  prefixIcon: const Icon(Icons.phone, color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[600]!),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  hintText: 'เช่น 081-234-5678',
                ),
                validator: (value) {
                  // ไม่บังคับกรอก แต่ถ้ากรอกต้องถูกต้อง
                  if (value != null && value.isNotEmpty) {
                    String cleaned = value.replaceAll(RegExp(r'[^\d]'), '');
                    if (cleaned.length != 10 || !cleaned.startsWith('0')) {
                      return 'กรุณากรอกเบอร์โทรที่ถูกต้อง (10 หลัก)';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Gender
              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: InputDecoration(
                  labelText: 'เพศ',
                  prefixIcon: const Icon(Icons.wc, color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[600]!),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                items: _genderOptions.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedGender = newValue!;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Birth Date - แสดงเป็น ค.ศ.
              InkWell(
                onTap: () => _selectDate(context),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'วันเกิด',
                    prefixIcon: const Icon(
                      Icons.calendar_today,
                      color: Colors.grey,
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
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.blue[600]!),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    suffixIcon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.grey,
                    ),
                  ),
                  child: Text(
                    _formatDate(_selectedDate), // แสดงเป็น ค.ศ.
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Weight
              TextFormField(
                controller: _weightController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'น้ำหนัก (กก.)',
                  prefixIcon: const Icon(
                    Icons.monitor_weight,
                    color: Colors.grey,
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
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[600]!),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
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
              const SizedBox(height: 16),

              // Height
              TextFormField(
                controller: _heightController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'ส่วนสูง (ซม.)',
                  prefixIcon: const Icon(Icons.height, color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[600]!),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
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
              const SizedBox(height: 16),

              // Allergies
              TextFormField(
                controller: _allergyController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'อาหารที่แพ้ (ถ้ามี)',
                  prefixIcon: const Icon(Icons.warning, color: Colors.grey),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.blue[600]!),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  hintText:
                      'ระบุอาหารที่แพ้ เช่น กุ้ง, ถั่ว, นม หรือใส่ "ไม่มี" หากไม่แพ้อะไร',
                ),
              ),
              const SizedBox(height: 32),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _goBack,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        side: BorderSide(color: Colors.grey[400]!),
                      ),
                      child: const Text(
                        'ย้อนกลับ',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitRegistration,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
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
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
