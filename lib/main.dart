import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:my_app/foodreccom/providers/enhanced_recommendation_provider.dart';
import 'package:my_app/foodreccom/utils/ingredient_translator.dart'; // ✅ เพิ่มมา
import 'package:my_app/welcomeapp/register.dart';
import 'package:my_app/welcomeapp/login.dart';
import 'package:my_app/welcomeapp/registerinfor.dart';
import 'package:my_app/welcomeapp/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  await FirebaseAuth.instance.setLanguageCode('th');

  // โหลดไฟล์ .env
  await dotenv.load(fileName: ".env");
  final apiKeys = dotenv.env['GEMINI_API_KEYS'];
  if (apiKeys == null || apiKeys.isEmpty) {
    print("❌ [ENV ERROR] GEMINI_API_KEYS not found");
  } else {
    print("✅ [ENV OK] Loaded ${apiKeys.split(',').length} keys");
    print("🔑 First key: ${apiKeys.split(',').first.substring(0, 6)}...");
  }

  // ✅ โหลด Ingredient Translator cache
  await IngredientTranslator.loadCache();

  // ตรวจสอบกล้องก่อน
  try {
    final cameras = await availableCameras();
    print('📷 Available cameras: ${cameras.length}');
  } catch (e) {
    print('❌ Error getting cameras: $e');
  }

  runApp(MyApp());
}

class AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

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
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EnhancedRecommendationProvider()),
      ],
      child: MaterialApp(
        title: 'ระบบผู้ใช้งาน (Dev)',
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
        home: AuthGate(),
        routes: {
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/registerinfor': (context) => const Registerinfor(),
          '/home': (context) => const HomeScreen(),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
