import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:my_app/welcomeapp/login.dart';
import 'package:my_app/welcomeapp/register.dart';
import 'package:my_app/welcomeapp/registerinfor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kubb',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Prompt', // ถ้าใช้ฟอนต์ไทย
      ),

      // กำหนดหน้าเริ่มต้น
      initialRoute: '/register',

      // กำหนด routes ทั้งหมด (แค่ 3 หน้า)
      routes: {
        '/login': (context) => LoginScreen(),
        '/register': (context) => RegisterScreen(),
        '/registerinfor': (context) => Registerinfor(),
      },

      // หน้าที่แสดงเมื่อไม่พบ route
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text('Page Not Found')),
            body: Center(child: Text('ไม่พบหน้าที่ต้องการ')),
          ),
        );
      },
    );
  }
}
