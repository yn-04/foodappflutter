import 'package:flutter/material.dart';

class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.title,
    required this.count,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final int count;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // กันล้นตอนระบบปรับตัวอักษรใหญ่
    final textScale = MediaQuery.textScaleFactorOf(context).clamp(1.0, 1.2);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaleFactor: textScale),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 130,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withAlpha((255 * 0.14).round()),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outline.withAlpha(102)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: cs.primary.withAlpha((255 * 0.12).round()),
                child: Icon(icon, color: cs.primary, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count รายการ',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withAlpha(153),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
