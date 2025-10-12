// lib/profile/family/widgets/ui_helpers.dart
import 'package:flutter/material.dart';

/// ------------------------------
/// Spacing & Gaps
/// ------------------------------
const kRadius12 = 12.0;
const kRadius16 = 16.0;

const kCardPadding = EdgeInsets.all(16);
const kPagePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 20);

SizedBox vGap(double h) => SizedBox(height: h);
SizedBox hGap(double w) => SizedBox(width: w);

const gap4 = SizedBox(height: 4);
const gap6 = SizedBox(height: 6);
const gap8 = SizedBox(height: 8);
const gap12 = SizedBox(height: 12);
const gap16 = SizedBox(height: 16);
const gap20 = SizedBox(height: 20);
const gap24 = SizedBox(height: 24);

/// ------------------------------
/// Shadows & Decor
/// ------------------------------
final kSoftShadow = [
  BoxShadow(
    color: Colors.black.withOpacity(0.06),
    blurRadius: 16,
    offset: const Offset(0, 6),
  ),
];

BoxDecoration cardDecor({
  Color? color,
  double radius = kRadius16,
  bool withBorder = true,
}) {
  return BoxDecoration(
    color: color ?? Colors.white,
    borderRadius: BorderRadius.circular(radius),
    border: withBorder ? Border.all(color: Colors.black12) : null,
  );
}

/// ------------------------------
/// Responsive helpers
/// ------------------------------
bool isSmallScreen(BuildContext c) => MediaQuery.of(c).size.width < 360;
bool isTablet(BuildContext c) => MediaQuery.of(c).size.width >= 720;
double maxCardWidth(
  BuildContext c, {
  double mobile = 480,
  double tablet = 720,
}) {
  final w = MediaQuery.of(c).size.width;
  return w < 700 ? mobile : tablet;
}

/// ------------------------------
/// Text helpers
/// ------------------------------
TextStyle titleStyle(BuildContext c) {
  final base = Theme.of(c).textTheme.titleMedium;
  return (base ?? const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))
      .copyWith(fontWeight: FontWeight.w800);
}

TextStyle subtitleStyle(BuildContext c) {
  final base = Theme.of(c).textTheme.bodyMedium;
  return (base ?? const TextStyle(fontSize: 14)).copyWith(
    color: Colors.grey[700],
  );
}

/// ตัดข้อความยาว ป้องกัน overflow เวลานำไปแสดงในการ์ดแคบ ๆ
String ellipsize(String? text, {int max = 40}) {
  if (text == null) return '';
  if (text.length <= max) return text;
  return '${text.substring(0, max)}…';
}

/// ------------------------------
/// Snackbars & Dialogs
/// ------------------------------
void showSnack(
  BuildContext c,
  String message, {
  Color bg = Colors.black,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(c).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(
              label: actionLabel,
              textColor: Colors.white,
              onPressed: onAction,
            )
          : null,
    ),
  );
}

void showSuccess(BuildContext c, String m) => showSnack(c, m, bg: Colors.green);

void showError(BuildContext c, String m) => showSnack(c, m, bg: Colors.red);

Future<bool> confirm(
  BuildContext c, {
  required String title,
  String? message,
  String okText = 'ยืนยัน',
  String cancelText = 'ยกเลิก',
  Color okColor = Colors.black,
}) async {
  final res = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: (message == null) ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: Text(cancelText),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: okColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(c, true),
          child: Text(okText),
        ),
      ],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius16),
      ),
    ),
  );
  return res ?? false;
}

/// ------------------------------
/// Simple Section Header
/// ------------------------------
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// ------------------------------
/// Loading Overlay
/// ------------------------------
class LoadingOverlay extends StatelessWidget {
  final bool show;
  final Widget child;
  final String? message;

  const LoadingOverlay({
    super.key,
    required this.show,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: cardDecor(color: Colors.white),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      hGap(12),
                      Expanded(
                        child: Text(
                          message ?? 'กำลังดำเนินการ...',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// ------------------------------
/// Card Wrapper (กัน overflow + max width)
/// ------------------------------
class MaxWidthCard extends StatelessWidget {
  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry padding;

  const MaxWidthCard({
    super.key,
    required this.child,
    this.maxWidth = 680,
    this.padding = kCardPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? MediaQuery.of(context).size.width,
        ),
        child: Container(
          padding: padding,
          decoration: cardDecor(),
          child: child,
        ),
      ),
    );
  }
}
