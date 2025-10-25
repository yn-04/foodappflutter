// lib/dashboard/widgets/category_card.dart
import 'package:flutter/material.dart';

/// Reusable pill-shaped card for displaying category counts on the dashboard.
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.title,
    required this.count,
    required this.icon,
    this.onTap,
    this.caption,
    this.color,
  });

  final String title;
  final int count;
  final IconData icon;
  final VoidCallback? onTap;
  final String? caption;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = color ?? cs.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        width: 140,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withAlpha((255 * 0.16).round()),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outline.withAlpha((255 * 0.18).round())),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: accent.withAlpha((255 * 0.15).round()),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              caption ?? '$count รายการ',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
