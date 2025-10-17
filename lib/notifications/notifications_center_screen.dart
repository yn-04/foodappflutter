//lib/notifications/notifications_center_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificationsCenterScreen extends StatefulWidget {
  const NotificationsCenterScreen({super.key});

  @override
  State<NotificationsCenterScreen> createState() =>
      _NotificationsCenterScreenState();
}

class _NotificationsCenterScreenState extends State<NotificationsCenterScreen> {
  String? _familyId;
  bool _isLoadingFamily = true;
  String? _familyLoadError;
  bool _isSyncingNotifications = false;

  @override
  void initState() {
    super.initState();
    _loadFamilyId();
  }

  Future<void> _loadFamilyId() async {
    if (mounted) {
      setState(() {
        _isLoadingFamily = true;
        _familyLoadError = null;
      });
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _familyId = null;
        _isLoadingFamily = false;
        _familyLoadError = 'กรุณาเข้าสู่ระบบอีกครั้ง';
      });
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = snap.data();
      final rawFamilyId =
          (data?['familyId'] ?? data?['family_id'])
              as String?; // รองรับข้อมูลเก่า

      if (!mounted) return;
      final resolvedFamilyId = (rawFamilyId != null && rawFamilyId.isNotEmpty)
          ? rawFamilyId
          : null;

      setState(() {
        _familyId = resolvedFamilyId;
        _isLoadingFamily = false;
        _familyLoadError = null;
      });

      await _syncExpiryNotifications(familyId: resolvedFamilyId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _familyId = null;
        _isLoadingFamily = false;
        _familyLoadError = e.toString();
      });
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _familyNotifStream(String fid) {
    return FirebaseFirestore.instance
        .collection('notifications')
        .doc(fid)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _personalNotifStream(String uid) {
    return FirebaseFirestore.instance
        .collection('user_notifications')
        .doc(uid)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  String _resolveLevel(Map<String, dynamic> data) {
    final rawLevel = data['level'];
    if (rawLevel is String && rawLevel.isNotEmpty) {
      return rawLevel;
    }
    final daysLeft = (data['daysLeft'] as num?)?.toInt();
    switch (daysLeft) {
      case 0:
        return 'today';
      case 1:
        return 'in_1';
      case 2:
        return 'in_2';
      case 3:
        return 'in_3';
      default:
        return 'info';
    }
  }

  Future<void> _syncExpiryNotifications({String? familyId}) async {
    if (_isSyncingNotifications) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // ใช้ค่าที่สะอาดเสมอ
    final fid = (familyId ?? '').trim();
    final hasFamily = fid.isNotEmpty;

    _isSyncingNotifications = true;
    try {
      final firestore = FirebaseFirestore.instance;

      // 1) โหลดรายการแจ้งเตือนเดิม (ของเป้าหมายที่เราจะเขียน)
      CollectionReference<Map<String, dynamic>> targetNotifColl = hasFamily
          ? firestore.collection('notifications').doc(fid).collection('items')
          : firestore
                .collection('user_notifications')
                .doc(uid)
                .collection('items');

      QuerySnapshot<Map<String, dynamic>> existingSnap;
      try {
        existingSnap = await targetNotifColl
            .where('type', isEqualTo: 'expiry')
            .get();
      } catch (e) {
        // ถ้าอ่านกลุ่มแจ้งเตือนเป้าหมายไม่ได้ ให้เดาว่าเป็นสิทธิ์ แล้วลอง fallback ทันที
        if (hasFamily) {
          targetNotifColl = firestore
              .collection('user_notifications')
              .doc(uid)
              .collection('items');
          existingSnap = await targetNotifColl
              .where('type', isEqualTo: 'expiry')
              .get();
        } else {
          rethrow;
        }
      }

      final existingMap = {for (final doc in existingSnap.docs) doc.id: doc};

      // 2) โหลดรายการวัตถุดิบต้นทาง
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> rawDocs = [];
      try {
        if (hasFamily) {
          // ต้องผ่าน rules: users/{u}/raw_materials/{id} allow read if familyId == myFamilyId()
          final familySnap = await firestore
              .collectionGroup('raw_materials')
              .where('familyId', isEqualTo: fid)
              .get();
          rawDocs.addAll(familySnap.docs);
        } else {
          final personalSnap = await firestore
              .collection('users')
              .doc(uid)
              .collection('raw_materials')
              .get();
          rawDocs.addAll(personalSnap.docs);
        }
      } catch (e) {
        // แจ้งเตือนเฉพาะจุดนี้เพื่อระบุว่าอ่านวัตถุดิบไม่ผ่าน
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'อ่านวัตถุดิบไม่สำเร็จ (สิทธิ์ไม่ผ่านหรือเครือข่าย): $e',
              ),
            ),
          );
        }
        return;
      }

      // 3) คำนวณแจ้งเตือนที่ควรมี
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final formatter = DateFormat('dd/MM/yyyy');

      WriteBatch batch = firestore.batch();
      var operations = 0;
      final keepIds = <String>{};

      Future<void> commitIfNeeded() async {
        if (operations >= 400) {
          await batch.commit();
          batch = firestore.batch();
          operations = 0;
        }
      }

      String levelFromDaysLeft(int d) {
        switch (d) {
          case 0:
            return 'today';
          case 1:
            return 'in_1';
          case 2:
            return 'in_2';
          case 3:
            return 'in_3';
          default:
            return 'info';
        }
      }

      for (final doc in rawDocs) {
        final data = doc.data();
        final expiryValue = data['expiry_date'];
        DateTime? expiry;
        if (expiryValue is Timestamp) {
          expiry = expiryValue.toDate();
        } else if (expiryValue is String) {
          try {
            expiry = DateTime.parse(expiryValue);
          } catch (_) {}
        } else if (expiryValue is DateTime) {
          expiry = expiryValue;
        }
        if (expiry == null) continue;

        final expiryOnly = DateTime(expiry.year, expiry.month, expiry.day);
        final daysLeft = expiryOnly.difference(todayOnly).inDays;
        if (daysLeft < 0 || daysLeft > 3) continue;

        final qty = _toInt(data['quantity']);
        if (qty <= 0) continue;

        final itemName = (data['name'] ?? data['name_key'] ?? 'วัตถุดิบ')
            .toString();
        final ownerId = (data['ownerId'] ?? data['owner_id'] ?? '').toString();
        final refPath = doc.reference.path;
        final docId = '${refPath.replaceAll('/', '_')}_d$daysLeft';

        keepIds.add(docId);
        final existingData = existingMap[docId]?.data();

        final title = daysLeft == 0
            ? 'หมดอายุวันนี้'
            : 'ใกล้หมดอายุในอีก $daysLeft วัน';
        final formattedDate = formatter.format(expiryOnly);
        final body = daysLeft == 0
            ? '$itemName จะหมดอายุวันนี้ ($formattedDate)'
            : '$itemName จะหมดอายุในอีก $daysLeft วัน (หมดอายุ $formattedDate)';

        final notifRef = targetNotifColl.doc(docId);
        final payload = <String, dynamic>{
          'id': docId,
          'type': 'expiry',
          'refPath': refPath,
          'itemId': doc.id,
          'itemName': itemName,
          'ownerId': ownerId,
          'daysLeft': daysLeft,
          'level': levelFromDaysLeft(daysLeft),
          'expiresOn': Timestamp.fromDate(expiryOnly),
          'title': title,
          'body': body,
          'updatedAt': FieldValue.serverTimestamp(),
          'read': existingData != null
              ? (existingData['read'] ?? false)
              : false,
        };

        if (hasFamily) {
          // ❗ จำเป็นสำหรับ rules: requestFamilyId() == familyId
          payload['familyId'] = fid;
        } else {
          payload['userId'] = uid;
          payload['toUid'] = uid;
        }

        if (existingData != null && existingData['createdAt'] != null) {
          payload['createdAt'] = existingData['createdAt'];
        } else {
          payload['createdAt'] = FieldValue.serverTimestamp();
        }

        batch.set(notifRef, payload, SetOptions(merge: true));
        operations++;
        await commitIfNeeded();
      }

      // ลบที่ไม่ควรอยู่แล้ว
      for (final entry in existingMap.entries) {
        if (!keepIds.contains(entry.key)) {
          batch.delete(entry.value.reference);
          operations++;
          await commitIfNeeded();
        }
      }

      if (operations == 0) return;

      // 4) commit — ถ้าเขียน family ไม่ผ่าน ให้ fallback → personal
      try {
        await batch.commit();
      } catch (e) {
        final msg = e.toString();
        final isPerm =
            msg.contains('permission-denied') ||
            msg.contains('PERMISSION_DENIED');
        if (hasFamily && isPerm) {
          // fallback: เขียนเป็นส่วนตัวแทน
          final personalColl = firestore
              .collection('user_notifications')
              .doc(uid)
              .collection('items');
          final qs = await personalColl
              .where('type', isEqualTo: 'expiry')
              .get();
          final existingPersonal = {for (final d in qs.docs) d.id: d};
          WriteBatch fb = firestore.batch();
          var ops = 0;
          for (final id in keepIds) {
            final ref = personalColl.doc(id);
            final already = existingPersonal[id]?.data();
            fb.set(ref, {
              'id': id,
              'type': 'expiry',
              'scope': 'personal',
              'userId': uid,
              'toUid': uid,
              'createdAt': already != null
                  ? (already['createdAt'] ?? FieldValue.serverTimestamp())
                  : FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            ops++;
            if (ops >= 400) {
              await fb.commit();
              fb = firestore.batch();
              ops = 0;
            }
          }
          if (ops > 0) await fb.commit();
        } else {
          rethrow;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ซิงก์แจ้งเตือนไม่สำเร็จ: $e')));
      }
    } finally {
      _isSyncingNotifications = false;
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final fid = _familyId;
    final hasFamily = fid != null && fid.isNotEmpty;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('ศูนย์แจ้งเตือน')),
        body: const _CenteredError(
          error: 'กรุณาเข้าสู่ระบบเพื่อดูการแจ้งเตือน',
        ),
      );
    }

    final targetStream = hasFamily
        ? _familyNotifStream(fid!)
        : _personalNotifStream(user.uid);

    return Scaffold(
      appBar: AppBar(title: const Text('ศูนย์แจ้งเตือน')),
      body: _isLoadingFamily
          ? const _CenteredLoading(text: 'กำลังโหลดโปรไฟล์...')
          : _familyLoadError != null
          ? _CenteredError(error: _familyLoadError!)
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: targetStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const _CenteredLoading(text: 'กำลังโหลดแจ้งเตือน...');
                }
                if (snap.hasError) {
                  return _CenteredError(error: snap.error.toString());
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const _EmptyState();
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    await _syncExpiryNotifications(familyId: _familyId);
                    if (mounted) setState(() {});
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: docs.length,
                    separatorBuilder: (context, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final d = docs[i].data();
                      final title = (d['title'] ?? 'แจ้งเตือน') as String;
                      final body = (d['body'] ?? '') as String;
                      final level = _resolveLevel(d);
                      final createdAt = (d['createdAt'] as Timestamp?)
                          ?.toDate();
                      final updatedAt = (d['updatedAt'] as Timestamp?)
                          ?.toDate();
                      final expiresOn = (d['expiresOn'] as Timestamp?)
                          ?.toDate();
                      final ts = createdAt ?? updatedAt ?? expiresOn;
                      final isRead = (d['read'] ?? false) as bool;

                      return _NotificationCard(
                        title: title,
                        body: body,
                        level: level,
                        time: ts,
                        isRead: isRead,
                        onTap: () {
                          // TODO: นำทางไปหน้ารายการวัตถุดิบที่เกี่ยวข้องได้ถ้ามี itemRef/ownerId
                        },
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

/* ===================== Widgets ===================== */

class _NotificationCard extends StatelessWidget {
  final String title;
  final String body;
  final String level;
  final DateTime? time;
  final bool isRead;
  final VoidCallback? onTap;

  const _NotificationCard({
    required this.title,
    required this.body,
    required this.level,
    this.time,
    this.isRead = false,
    this.onTap,
  });

  String get _badgeText {
    switch (level) {
      case 'today':
        return 'วันนี้';
      case 'in_1':
        return 'อีก 1 วัน';
      case 'in_2':
        return 'อีก 2 วัน';
      case 'in_3':
        return 'อีก 3 วัน';
      default:
        return 'ทั่วไป';
    }
  }

  IconData get _icon {
    switch (level) {
      case 'today':
        return Icons.error_outline;
      case 'in_1':
        return Icons.warning_amber_outlined;
      case 'in_2':
        return Icons.event_available_outlined;
      case 'in_3':
        return Icons.event_note_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = time != null ? _formatTime(time!) : '';
    final titleColor = isRead
        ? Colors.grey.shade700
        : Colors.black.withValues(alpha: 0.85);
    final bodyColor = isRead ? Colors.grey.shade600 : Colors.grey.shade800;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              blurRadius: 10,
              color: Color(0x11000000),
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.grey.shade100,
              child: Icon(_icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                      ),
                      _Badge(text: _badgeText),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(body, style: TextStyle(color: bodyColor)),
                  if (ts.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      ts,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.blue),
      ),
    );
  }
}

class _CenteredLoading extends StatelessWidget {
  final String text;
  const _CenteredLoading({required this.text});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 12),
        Text(text),
      ],
    ),
  );
}

class _CenteredError extends StatelessWidget {
  final String error;
  const _CenteredError({required this.error});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text('เกิดข้อผิดพลาด\n$error', textAlign: TextAlign.center),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.notifications_off_outlined, size: 56),
          const SizedBox(height: 12),
          Text(
            'ยังไม่มีการแจ้งเตือน',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'จะมีแจ้งเตือนเมื่อวัตถุดิบใกล้หมดอายุหรือมีประกาศ',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    ),
  );
}
