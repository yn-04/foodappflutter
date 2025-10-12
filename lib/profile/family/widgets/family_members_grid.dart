// lib/profile/family/widgets/family_members_grid.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'member_card.dart';

class FamilyMembersGrid extends StatelessWidget {
  const FamilyMembersGrid({
    super.key,
    required this.familyId,
    required this.onAction, // callback จากเมนูการ์ด
  });

  final String familyId;

  /// ต้องมีลายเซ็นให้ตรงกับที่ FamilyAccountScreen เรียกใช้
  final Future<void> Function({
    required String action,
    required String targetUid,
    required String role,
  })
  onAction;

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: fs
          .collection('family_members')
          .where('familyId', isEqualTo: familyId)
          .orderBy('addedAt', descending: false)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Text('โหลดรายชื่อสมาชิกไม่สำเร็จ: ${snap.error}'),
          );
        }

        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('ยังไม่มีสมาชิกในครอบครัว'),
          );
        }

        final myUid = auth.currentUser?.uid;
        final amAdmin = _amIAdmin(myUid, docs);

        // ใช้ ListView (ถ้าต้องการเป็น Grid สามารถเปลี่ยนได้)
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 16.0),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4.0),
          itemBuilder: (context, i) {
            final m = docs[i].data();

            // ระบุ uid ของสมาชิกแต่ละคน
            final targetUid =
                (m['userId'] as String?) ?? (m['uid'] as String?) ?? docs[i].id;

            // บทบาท (admin/member)
            final role = (m['role'] as String? ?? 'member').toLowerCase();

            // ชื่อที่เคยเก็บไว้ในสมาชิก (fallback)
            final storedName = (m['displayName'] as String?)?.trim();

            // วันที่เข้าร่วม (addedAt: Timestamp?)
            DateTime? joinedAt;
            final addedAt = m['addedAt'];
            if (addedAt is Timestamp) {
              joinedAt = addedAt.toDate();
            }

            // การ์ดของตัวเองไหม
            final bool isSelfLocal = (myUid != null && myUid == targetUid);

            // สตรีมชื่อ/อีเมลแบบเรียลไทม์จาก users/{uid}
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: fs.collection('users').doc(targetUid).snapshots(),
              builder: (context, userSnap) {
                final userDoc = userSnap.data;
                String? liveName;
                String? userEmail;

                if (userDoc != null && userDoc.exists) {
                  final userMap = userDoc.data();
                  liveName = (userMap?['displayName'] as String?)?.trim();
                  userEmail = userMap?['email'] as String?;
                }

                final name = (liveName != null && liveName.isNotEmpty)
                    ? liveName
                    : (storedName != null && storedName.isNotEmpty
                          ? storedName
                          : 'Unnamed');

                return MemberCard(
                  uid: targetUid,
                  name: name,
                  role: role,
                  isSelf: isSelfLocal,
                  isAdmin: amAdmin, // สิทธิ์ของ "ผู้ชม" ทั้งหน้า
                  email: userEmail, // แสดงอีเมล (ถ้ามี)
                  joinedAt: joinedAt, // แสดงวันที่เข้าร่วม (ถ้ามี)
                  onAction: onAction, // callback ไปหน้าหลัก
                );
              },
            );
          },
        );
      },
    );
  }

  /// เช็คว่าผู้ใช้ปัจจุบันเป็นแอดมินของครอบครัวนี้หรือไม่
  bool _amIAdmin(
    String? myUid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (myUid == null) return false;
    for (final d in docs) {
      final m = d.data();
      final u = (m['userId'] as String?) ?? (m['uid'] as String?) ?? d.id;
      if (u == myUid) {
        final role = (m['role'] as String? ?? 'member').toLowerCase();
        return role == 'admin';
      }
    }
    return false;
  }
}
