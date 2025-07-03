import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:my_app/welcomeapp/register.dart';
import 'package:my_app/welcomeapp/login.dart';
import 'package:my_app/welcomeapp/registerinfor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ถ้ามีผู้ใช้ล็อกอินอยู่แล้ว → ไป Home
        if (snapshot.connectionState == ConnectionState.active) {
          final user = snapshot.data;
          if (user != null) {
            return HomeScreen();
          } else {
            return const LoginScreen();
          }
        }

        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ระบบผู้ใช้งาน',
      theme: ThemeData(primarySwatch: Colors.blue, fontFamily: 'Kanit'),
      initialRoute: '/login',
      routes: {
        '/': (context) => AuthGate(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/registerinfor': (context) => const Registerinfor(),
        '/home': (context) => HomeScreen(),
      },
    );
  }
}
