import 'package:flutter/material.dart';

/// Shared colors and components for Welcome app screens.
class WelcomeTheme {
  static const Color background = Color(0xFFFFF5EB);
  static const Color primary = Color(0xFFFB8500);
  static const Color accent = Color(0xFFFFB703);
  static const Color textPrimary = Color(0xFF1F2933);
  static const Color textSecondary = Color(0xFF4B5563);
  static const Color fieldFill = Color(0xFFFFFAF4);
  static const LinearGradient headerGradient = LinearGradient(
    colors: [accent, primary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primary,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    padding: const EdgeInsets.symmetric(vertical: 16),
    elevation: 0,
  );

  static ButtonStyle secondaryButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: primary,
    side: const BorderSide(color: primary, width: 1.4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    padding: const EdgeInsets.symmetric(vertical: 16),
  );
}

class WelcomeHeader extends StatelessWidget {
  const WelcomeHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.caption,
  });

  final String title;
  final String subtitle;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
      decoration: const BoxDecoration(
        gradient: WelcomeTheme.headerGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/login_logo.png',
            height: 120,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color.fromARGB(224, 255, 255, 255),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color.fromARGB(194, 255, 255, 255),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
