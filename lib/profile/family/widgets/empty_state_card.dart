// lib/profile/family/widgets/empty_state_card.dart
import 'package:flutter/material.dart';

/// การ์ดแสดงสถานะว่าง (Empty State)
/// - รองรับไอคอน/รูปภาพ/ข้อความ/ปุ่มกด
/// - ออกแบบให้ไม่ overflow และยืดหยุ่นกับพื้นที่
class EmptyStateCard extends StatelessWidget {
  final IconData? icon;
  final double iconSize;
  final Color? iconColor;

  /// หากอยากใช้รูปภาพแทนไอคอน ให้ใส่ [illustration] (เช่น Image.asset / Image.network)
  /// ถ้ากำหนดทั้ง icon และ illustration จะแสดง illustration เป็นหลัก
  final Widget? illustration;

  final String title;
  final String? message;

  /// ปุ่มหลัก (เช่น “สร้างครอบครัว”)
  final String? primaryText;
  final VoidCallback? onPrimary;

  /// ปุ่มรอง (เช่น “เข้าร่วมด้วยโค้ด/สแกน”)
  final String? secondaryText;
  final VoidCallback? onSecondary;

  /// ปรับ padding การ์ด
  final EdgeInsetsGeometry padding;

  /// กำหนดความกว้างสูงสุด (เช่น บน tablet/desktop)
  final double? maxWidth;

  /// สีพื้นหลัง (ค่าเริ่มต้นใช้ Theme.cardColor)
  final Color? background;

  const EmptyStateCard({
    super.key,
    this.icon = Icons.family_restroom,
    this.iconSize = 56,
    this.iconColor,
    this.illustration,
    required this.title,
    this.message,
    this.primaryText,
    this.onPrimary,
    this.secondaryText,
    this.onSecondary,
    this.padding = const EdgeInsets.all(20),
    this.maxWidth = 480,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = background ?? Theme.of(context).cardColor;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Illustration หรือ Icon
              if (illustration != null) ...[
                SizedBox(
                  height: iconSize + 16,
                  child: FittedBox(fit: BoxFit.contain, child: illustration!),
                ),
                const SizedBox(height: 16),
              ] else if (icon != null) ...[
                CircleAvatar(
                  radius: (iconSize / 2) + 12,
                  backgroundColor: (iconColor ?? Colors.indigo).withValues(alpha: 
                    0.08,
                  ),
                  child: Icon(
                    icon,
                    size: iconSize,
                    color: iconColor ?? Colors.indigo,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Title
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),

              // Message
              if (message != null && message!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[700],
                  ),
                ),
              ],

              // Actions
              if ((primaryText != null && onPrimary != null) ||
                  (secondaryText != null && onSecondary != null)) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    if (primaryText != null && onPrimary != null)
                      _PrimaryButton(text: primaryText!, onPressed: onPrimary!),
                    if (secondaryText != null && onSecondary != null)
                      _SecondaryButton(
                        text: secondaryText!,
                        onPressed: onSecondary!,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------- buttons -----------------

class _PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  const _PrimaryButton({required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  const _SecondaryButton({required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black,
        side: const BorderSide(color: Colors.black12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: onPressed,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}
