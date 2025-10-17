import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app/profile/family/family_account_screen.dart';
import 'package:my_app/profile/family/family_hub_screen.dart';
import 'package:my_app/profile/profile_tab.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:my_app/foodreccom/providers/enhanced_recommendation_provider.dart';
import 'package:my_app/foodreccom/utils/ingredient_translator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'package:my_app/firebase_options.dart';
import 'package:my_app/welcomeapp/login_screen.dart';
import 'package:my_app/welcomeapp/register_screen.dart';
import 'package:my_app/welcomeapp/profile_setup_screen.dart';
import 'package:my_app/welcomeapp/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init Firebase ด้วย options
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAuth.instance.setLanguageCode('th');

  // ✅ เปิดใช้ App Check (โหมด Dev ใช้ Debug provider ทั้ง Android/iOS)
  //    ถ้าจะไปโปรดักชัน ค่อยสลับเป็น playIntegrity/deviceCheck (ดูโน้ตด้านล่าง)
  // โหลดไฟล์ .env
  await dotenv.load(fileName: ".env");
  final apiKeys = dotenv.env['GEMINI_API_KEYS'];
  if (apiKeys == null || apiKeys.isEmpty) {
    debugPrint("❌ [ENV ERROR] GEMINI_API_KEYS not found");
  } else {
    debugPrint("✅ [ENV OK] Loaded ${apiKeys.split(',').length} keys");
    debugPrint("🔑 First key: ${apiKeys.split(',').first.substring(0, 6)}...");
  }

  // โหลด Ingredient Translator cache
  await IngredientTranslator.loadCache();

  // ตรวจสอบกล้อง
  try {
    final cameras = await availableCameras();
    debugPrint('📷 Available cameras: ${cameras.length}');
  } catch (e) {
    debugPrint('❌ Error getting cameras: $e');
  }
  // อุ่นเครื่องกล้องแบบไม่บล็อก UI
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
  const MyApp({super.key});

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
        home: const AuthGate(),
        routes: {
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/profile-setup': (_) => const ProfileSetupScreen(),
          '/home': (_) => const HomeScreen(),

          '/home/profile': (_) => const HomeScreen(initialIndex: 3),
          '/profile': (_) => const ProfileTab(),
          '/family/hub': (_) => const FamilyHubScreen(),
          '/family/account': (_) => const FamilyAccountScreen(),
        },
        onUnknownRoute: (settings) => MaterialPageRoute(
          builder: (_) => const ProfileTab(), // กันพลาด route แปลก
        ),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
