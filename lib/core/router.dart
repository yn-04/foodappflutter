import 'package:flutter/material.dart';
import 'package:my_app/welcomeapp/home.dart';
import 'package:my_app/welcomeapp/login_screen.dart';
import 'package:my_app/welcomeapp/profile_setup_screen.dart';
import 'package:my_app/welcomeapp/register_screen.dart';

class Routes {
  static const login = '/login';
  static const register = '/register';
  static const profileSetup = '/profile-setup';
  static const home = '/home';
}

class AppRouter {
  static const initialRoute = Routes.register; // หรือ Routes.login ตาม flow

  static Route<dynamic> onGenerateRoute(RouteSettings s) {
    switch (s.name) {
      case Routes.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case Routes.register:
        return MaterialPageRoute(builder: (_) => const RegisterScreen());
      case Routes.profileSetup:
        return MaterialPageRoute(builder: (_) => const ProfileSetupScreen());
      case Routes.home:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      default:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
    }
  }
}
