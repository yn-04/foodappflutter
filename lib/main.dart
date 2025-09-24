import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:my_app/firebase_options.dart';
import 'package:my_app/foodreccom/providers/recommendation_provider.dart';
import 'package:my_app/welcomeapp/login_screen.dart';
import 'package:my_app/welcomeapp/register_screen.dart';
import 'package:my_app/welcomeapp/profile_setup_screen.dart';
import 'package:my_app/welcomeapp/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Init Firebase with explicit options to avoid platform-specific hangs
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // (ไม่บังคับ) อุ่นเครื่องกล้องแบบไม่บล็อก UI เพื่อลดจอดำ
  // ไม่ต้องรอให้เสร็จ เพื่อไม่ให้บูตช้า
  // ignore: unawaited_futures
  Future(() async {
    try {
      await availableCameras();
    } catch (_) {}
  });

  runApp(const MyApp());
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // ล็อกอินค้าง → ไป Home
        if (snap.hasData) return const HomeScreen();
        // ยังไม่ล็อกอิน → ไป Login
        return const LoginScreen();
      },
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RecommendationProvider(),
      child: MaterialApp(
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
        home: const AuthGate(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/profile-setup': (_) => const ProfileSetupScreen(),
          '/home': (_) => const HomeScreen(),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
