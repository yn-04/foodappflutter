import 'package:flutter/material.dart';

/// -------------------------
/// Extension สำหรับ BuildContext
/// -------------------------
extension BuildContextExtensions on BuildContext {
  void showSnack(String message, {Color color = Colors.black87}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Size get screenSize => MediaQuery.of(this).size;
  TextTheme get textTheme => Theme.of(this).textTheme;
}

/// -------------------------
/// Extension สำหรับ Widget
/// -------------------------
extension WidgetExtensions on Widget {
  Widget withPadding([EdgeInsets padding = const EdgeInsets.all(8)]) {
    return Padding(padding: padding, child: this);
  }

  Widget asCard({double radius = 12, Color? color}) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
      color: color,
      elevation: 2,
      child: this,
    );
  }

  Widget expanded() => Expanded(child: this);
}

/// -------------------------
/// Extension สำหรับ String/Text
/// -------------------------
extension StringExtensions on String {
  Text asText({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.normal,
    Color color = Colors.black87,
    TextAlign align = TextAlign.start,
  }) {
    return Text(
      this,
      textAlign: align,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      ),
    );
  }
}

extension TextStyleExtensions on TextStyle {
  TextStyle get bold => copyWith(fontWeight: FontWeight.bold);
  TextStyle get italic => copyWith(fontStyle: FontStyle.italic);
  TextStyle withColor(Color color) => copyWith(color: color);
}
