// lib/profile/family/widgets/member_card.dart
import 'package:flutter/material.dart';

/// บทบาทของสมาชิก
enum MemberRole { admin, member }

/// ประเภทการกระทำจากเมนูของการ์ด
/// (คง enum เดิมไว้เพื่อความเข้ากันได้ แต่ UI ใช้เฉพาะ remove)
enum MemberCardAction { remove, makeAdmin, revokeAdmin }

/// การ์ดแสดงสมาชิกในครอบครัว (สไตล์สีขาว เรียบ, เน้นการ์ดของ "คุณ")
class MemberCard extends StatelessWidget {
  const MemberCard({
    super.key,
    required this.uid, // ใช้ภายใน callback เท่านั้น ไม่แสดงบน UI
    required this.name,
    required this.role, // 'admin' | 'member'
    required this.isSelf, // การ์ดนี้เป็นของผู้ชมเองหรือไม่
    required this.isAdmin, // ผู้ชมเป็นแอดมินของครอบครัวหรือไม่ (เพื่อเปิดเมนู)
    required this.onAction, // callback จากเมนู
    this.photoUrl,
    this.email,
    this.joinedAt, // วันที่เข้าร่วม (optional)
  });

  final String uid;
  final String name;
  final String role;
  final bool isSelf;
  final bool isAdmin;
  final Future<void> Function({
    required String action,
    required String targetUid,
    required String role,
  })
  onAction;

  final String? photoUrl;
  final String? email;
  final DateTime? joinedAt;

  @override
  Widget build(BuildContext context) {
    final normalizedRole = (role.isEmpty ? 'member' : role).toLowerCase();
    final isAdminRole = normalizedRole == 'admin';

    // การ์ดสีขาวทั้งหมด; การ์ดของ "คุณ" เงาอ่อนขึ้นเล็กน้อย
    final double elevation = isSelf ? 2.0 : 0.5;

    // ชื่อ
    final displayName = (name.isNotEmpty ? name : 'Unnamed');

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      elevation: elevation,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: ListTile(
        leading: _buildAvatar(),
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8.0),
            _RolePill(isAdminRole: isAdminRole),
            if (isSelf) ...[const SizedBox(width: 6.0), const _SelfPill()],
          ],
        ),
        subtitle: _buildSubtitle(context),
        trailing: _buildMenu(context, normalizedRole),
      ),
    );
  }

  Widget _buildAvatar() {
    // ถ้ามีรูปค่อยเปลี่ยนมาใช้ NetworkImage ได้
    final initials = _resolveInitial(email, name);
    return CircleAvatar(radius: 20.0, child: Text(initials));
  }

  Widget _buildSubtitle(BuildContext context) {
    final parts = <String>[];

    // อีเมล
    if (email != null && email!.isNotEmpty) {
      parts.add(email!);
    }

    // วันที่เข้าร่วม
    final joined = _formatDate(joinedAt);
    if (joined != null) {
      parts.add('เข้าร่วม: $joined');
    }

    // ❌ ไม่แสดง uid

    return Text(
      parts.isEmpty ? '-' : parts.join(' • '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  /// เมนู: เหลือเฉพาะ "ลบออกจากครอบครัว"
  Widget? _buildMenu(BuildContext context, String normalizedRole) {
    // เงื่อนไข: ต้องเป็นแอดมินถึงจะเห็นเมนู และห้ามจัดการตัวเอง
    if (!isAdmin || isSelf) return null;

    return PopupMenuButton<MemberCardAction>(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      onSelected: (action) async {
        switch (action) {
          case MemberCardAction.remove:
            await onAction(
              action: 'remove',
              targetUid: uid,
              role: normalizedRole,
            );
            break;
          case MemberCardAction.makeAdmin:
          case MemberCardAction.revokeAdmin:
            // ไม่ใช้แล้ว
            break;
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<MemberCardAction>>[
        PopupMenuItem<MemberCardAction>(
          value: MemberCardAction.remove,
          child: Text(
            'ลบออกจากครอบครัว',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }

  String _resolveInitial(String? email, String name) {
    String? source;
    if (email != null && email.contains('@')) {
      source = email.trim();
    } else if (name.trim().isNotEmpty) {
      source = name.trim();
    }
    if (source == null || source.isEmpty) return '?';
    return source[0].toUpperCase();
  }

  String? _formatDate(DateTime? dt) {
    if (dt == null) return null;
    final d = dt.toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd'; // yyyy-MM-dd
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({required this.isAdminRole});
  final bool isAdminRole;

  @override
  Widget build(BuildContext context) {
    final label = isAdminRole ? 'ผู้ดูแล' : 'สมาชิก';
    final color = isAdminRole
        ? Theme.of(context).colorScheme.primary
        : Colors.grey.shade700;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999.0),
        border: Border.all(color: color.withOpacity(0.5), width: 1.0),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          letterSpacing: 0.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SelfPill extends StatelessWidget {
  const _SelfPill();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999.0),
        border: Border.all(color: color.withOpacity(0.5), width: 1.0),
      ),
      child: Text(
        'คุณ',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
