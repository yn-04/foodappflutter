// main.dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:my_app/welcomeapp/register.dart';
import 'package:my_app/welcomeapp/login.dart';
import 'package:my_app/welcomeapp/registerinfor.dart';
import 'package:my_app/welcomeapp/home.dart'; // ตรวจสอบ path ให้ถูกต้อง

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // ตรวจสอบกล้องก่อน
  try {
    final cameras = await availableCameras();
    print('Available cameras: ${cameras.length}');
  } catch (e) {
    print('Error getting cameras: $e');
  }
  runApp(MyApp());
}

class AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // กำลังตรวจสอบสถานะการล็อกอิน
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ถ้ามีผู้ใช้ล็อกอินอยู่แล้ว → ไป Home
        if (snapshot.hasData) {
          return const HomeScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ระบบผู้ใช้งาน',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Kanit',
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: AuthGate(), // ใช้ home แทน initialRoute
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/registerinfor': (context) => const Registerinfor(),
        '/home': (context) => const HomeScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
