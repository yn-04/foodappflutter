// lib/profile/family/widgets/quick_actions_row.dart
import 'package:flutter/material.dart';

/// แถวปุ่มลัดบนหน้าบัญชีครอบครัว
/// - ถ้ายังไม่มีครอบครัว -> แสดง "สร้างครอบครัว" และ "เข้าร่วมครอบครัว"
/// - ถ้ามีครอบครัว (member) -> แสดง "เชิญสมาชิก" และ "ออกจากครอบครัว"
/// - ถ้ามีครอบครัว (admin) -> เหมือน member + (option) "ยุบครอบครัว" ถ้าส่ง callback มา
class QuickActionsRow extends StatelessWidget {
  final bool hasFamily;
  final bool isAdmin;

  final VoidCallback onInvite; // เชิญสมาชิก (สร้างโค้ด/QR)
  final VoidCallback onJoinFamily; // ไปหน้า Join (สแกน/กรอกโค้ด)
  final VoidCallback onLeaveFamily; // ออกจากครอบครัว
  final VoidCallback onCreateFamily; // สร้างครอบครัว

  /// (optional) โชว์ปุ่ม "ยุบครอบครัว" เฉพาะ admin หากส่ง callback มา
  final VoidCallback? onDisbandFamily;

  const QuickActionsRow({
    super.key,
    required this.hasFamily,
    required this.isAdmin,
    required this.onInvite,
    required this.onJoinFamily,
    required this.onLeaveFamily,
    required this.onCreateFamily,
    this.onDisbandFamily,
  });

  @override
  Widget build(BuildContext context) {
    final items = <_ActionSpec>[];

    if (!hasFamily) {
      items.addAll([
        _ActionSpec(
          label: 'สร้างครอบครัว',
          icon: Icons.family_restroom,
          onTap: onCreateFamily,
          type: _BtnType.primary,
        ),
        _ActionSpec(
          label: 'เข้าร่วมครอบครัว',
          icon: Icons.qr_code_scanner,
          onTap: onJoinFamily,
          type: _BtnType.neutral,
        ),
      ]);
    } else {
      items.add(
        _ActionSpec(
          label: 'เชิญสมาชิก',
          icon: Icons.person_add_alt_1,
          onTap: onInvite,
          type: _BtnType.primary,
        ),
      );

      if (isAdmin) {
        if (onDisbandFamily != null) {
          items.add(
            _ActionSpec(
              label: 'ยุบครอบครัว',
              icon: Icons.delete_forever,
              onTap: onDisbandFamily!,
              type: _BtnType.destructive,
            ),
          );
        }
      } else {
        items.add(
          _ActionSpec(
            label: 'ออกจากครอบครัว',
            icon: Icons.logout,
            onTap: onLeaveFamily,
            type: _BtnType.destructiveOutline,
          ),
        );
      }
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: items
          .map(
            (e) => _ActionButton(
              label: e.label,
              icon: e.icon,
              onTap: e.onTap,
              type: e.type,
            ),
          )
          .toList(),
    );
  }
}

enum _BtnType { primary, neutral, destructive, destructiveOutline }

class _ActionSpec {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final _BtnType type;
  _ActionSpec({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.type,
  });
}

/// ปุ่มแอคชันขนาดกลาง รองรับหลายสไตล์ + กัน overflow
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final _BtnType type;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // กำหนดสีปุ่มตามชนิด
    Color bg;
    Color fg;
    OutlinedBorder shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    ButtonStyle style;

    switch (type) {
      case _BtnType.primary:
        bg = Colors.black;
        fg = Colors.white;
        style = ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: shape,
        );
        return _buttonWrapper(
          ElevatedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Flexible(
              child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
            style: style,
          ),
        );

      case _BtnType.neutral:
        style = OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: shape,
        );
        return _buttonWrapper(
          OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Flexible(
              child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
            style: style,
          ),
        );

      case _BtnType.destructive:
        bg = Colors.red.shade600;
        fg = Colors.white;
        style = ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: shape,
        );
        return _buttonWrapper(
          ElevatedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Flexible(
              child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
            style: style,
          ),
        );

      case _BtnType.destructiveOutline:
        final borderColor = isDark ? Colors.red.shade300 : Colors.red.shade600;
        style = OutlinedButton.styleFrom(
          side: BorderSide(color: borderColor),
          foregroundColor: borderColor,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: shape,
        );
        return _buttonWrapper(
          OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Flexible(
              child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
            style: style,
          ),
        );
    }
  }

  /// ห่อปุ่มด้วย ConstrainedBox + SizedBox เพื่อกันปุ่มยืดเกิน/overflow ใน Wrap
  Widget _buttonWrapper(Widget child) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
      child: SizedBox(height: 44, child: child),
    );
  }
}
