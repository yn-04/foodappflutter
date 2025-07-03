import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:my_app/welcomeapp/register.dart';

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
      theme: ThemeData(primarySwatch: Colors.blue, fontFamily: 'Kanit'),

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

// หน้าหลักที่แสดงหลังลงทะเบียนเสร็จ
class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('หน้าหลัก'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[600]!, Colors.blue[100]!],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, size: 100, color: Colors.green),
              SizedBox(height: 20),
              Text(
                'ลงทะเบียนสำเร็จ!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
              SizedBox(height: 10),
              Text(
                'ยินดีต้อนรับสู่แอปพลิเคชัน',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  // กลับไปหน้าแรก หรือไปหน้าอื่นๆ
                  Navigator.pushReplacementNamed(context, '/register');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[600],
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'เริ่มใช้งาน',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
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

  // Controllers - ใช้แค่ fullNameController
  final _fullNameController = TextEditingController();
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

      // ตั้งค่าชื่อจากหน้าก่อนหน้า
      if (_name != null && _name!.isNotEmpty) {
        _fullNameController.text = _name!;
      }
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _allergyController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('th', 'TH'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // ฟังก์ชันแยกชื่อและนามสกุล
  Map<String, String> _splitFullName(String fullName) {
    List<String> nameParts = fullName.trim().split(' ');

    if (nameParts.length == 1) {
      return {'firstName': nameParts[0], 'lastName': ''};
    } else if (nameParts.length >= 2) {
      return {
        'firstName': nameParts[0],
        'lastName': nameParts
            .sublist(1)
            .join(' '), // รวมส่วนที่เหลือเป็นนามสกุล
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
        'gender': _selectedGender,
        'birthDate': Timestamp.fromDate(_selectedDate),
        'weight': double.parse(_weightController.text),
        'height': double.parse(_heightController.text),
        'allergies': _allergyController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'profileCompleted': true,
      });

      // บันทึกข้อมูลใน collection 'registrations' ด้วย (สำหรับการติดตาม)
      await _firestore.collection('registrations').add({
        'userId': userCredential.user!.uid,
        'firstName': firstName,
        'lastName': lastName,
        'fullName': _fullNameController.text.trim(),
        'gender': _selectedGender,
        'birthDate': Timestamp.fromDate(_selectedDate),
        'weight': double.parse(_weightController.text),
        'height': double.parse(_heightController.text),
        'allergies': _allergyController.text.trim(),
        'registrationDate': Timestamp.now(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ลงทะเบียนสำเร็จ! กรุณาตรวจสอบอีเมลเพื่อยืนยันตัวตน'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );

      // นำทางไปหน้าหลักหลังลงทะเบียนเสร็จ
      Navigator.pushReplacementNamed(context, '/home');
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
          duration: Duration(seconds: 5),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _clearForm() {
    _fullNameController.clear();
    _weightController.clear();
    _heightController.clear();
    _allergyController.clear();
    setState(() {
      _selectedGender = 'ชาย';
      _selectedDate = DateTime.now();
    });
  }

  void _goBack() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ลงทะเบียน'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[600]!, Colors.blue[100]!],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.person_add,
                            size: 48,
                            color: Colors.blue[600],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'ข้อมูลลงทะเบียน',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Full Name Field (ชื่อ-นามสกุล)
                    TextFormField(
                      controller: _fullNameController,
                      decoration: InputDecoration(
                        labelText: 'ชื่อ-นามสกุล',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
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

                    // Gender
                    DropdownButtonFormField<String>(
                      value: _selectedGender,
                      decoration: InputDecoration(
                        labelText: 'เพศ',
                        prefixIcon: const Icon(Icons.wc),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
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

                    // Birth Date
                    InkWell(
                      onTap: () => _selectDate(context),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'วันเกิด',
                          prefixIcon: const Icon(Icons.calendar_today),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        child: Text(
                          DateFormat('dd/MM/yyyy').format(_selectedDate),
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
                        prefixIcon: const Icon(Icons.monitor_weight),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'กรุณากรอกน้ำหนัก';
                        }
                        if (double.tryParse(value) == null) {
                          return 'กรุณากรอกตัวเลขที่ถูกต้อง';
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
                        prefixIcon: const Icon(Icons.height),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'กรุณากรอกส่วนสูง';
                        }
                        if (double.tryParse(value) == null) {
                          return 'กรุณากรอกตัวเลขที่ถูกต้อง';
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
                        prefixIcon: const Icon(Icons.warning),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                        hintText: 'ระบุอาหารที่แพ้ เช่น กุ้ง, ถั่ว, นม',
                      ),
                    ),
                    const SizedBox(height: 24),

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
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
