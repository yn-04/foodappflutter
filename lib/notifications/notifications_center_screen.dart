//lib/notifications/notifications_center_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';

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

      String cleanString(dynamic value) {
        if (value is String) return value.trim();
        if (value == null) return '';
        return value.toString().trim();
      }

      String resolveCategory(Map<String, dynamic> data) {
        const directKeys = [
          'category',
          'category_key',
          'categoryName',
          'category_name',
          'categoryLabel',
          'category_label',
          'groupCategory',
          'group_category',
          'categoryId',
          'category_id',
        ];
        for (final key in directKeys) {
          final value = cleanString(data[key]);
          if (value.isNotEmpty) return value;
        }
        const subKeys = [
          'subcategory',
          'subcategory_key',
          'subCategory',
          'sub_category',
        ];
        for (final key in subKeys) {
          final sub = cleanString(data[key]);
          if (sub.isEmpty) continue;
          final cat = Categories.categoryForSubcategory(sub);
          if (cat != null && cat.isNotEmpty) return cat;
        }
        final inferred = Categories.autoDetect(cleanString(data['name']));
        final cat = inferred['category'];
        if (cat != null && cat.isNotEmpty) return cat;
        return '';
      }

      String resolveSubcategory(Map<String, dynamic> data) {
        const subKeys = [
          'subcategory',
          'subcategory_key',
          'subCategory',
          'sub_category',
        ];
        for (final key in subKeys) {
          final value = cleanString(data[key]);
          if (value.isNotEmpty) return value;
        }
        final inferred = Categories.autoDetect(cleanString(data['name']));
        final sub = inferred['subcategory'];
        if (sub != null && sub.isNotEmpty) return sub;
        return '';
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
        final category = resolveCategory(data);
        final subcategory = resolveSubcategory(data);
        final ownerId = (data['ownerId'] ?? data['owner_id'] ?? '').toString();
        final refPath = doc.reference.path;
        final docId = '${refPath.replaceAll('/', '_')}_d$daysLeft';

        keepIds.add(docId);
        final existingData = existingMap[docId]?.data();

        final title = daysLeft == 0
            ? 'หมดอายุวันนี้'
            : 'ใกล้หมดอายุในอีก $daysLeft วัน';
        final formattedDate = formatter.format(expiryOnly);
        final body = 'วันหมดอายุ: $formattedDate';

        final notifRef = targetNotifColl.doc(docId);
        final payload = <String, dynamic>{
          'id': docId,
          'type': 'expiry',
          'refPath': refPath,
          'itemId': doc.id,
          'itemName': itemName,
          'category': category,
          if (subcategory.isNotEmpty) 'subcategory': subcategory,
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
    final rawFamilyId = _familyId;
    final fid = rawFamilyId != null ? rawFamilyId.trim() : '';
    final hasFamily = fid.isNotEmpty;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('ศูนย์แจ้งเตือน')),
        body: const _CenteredError(
          error: 'กรุณาเข้าสู่ระบบเพื่อดูการแจ้งเตือน',
        ),
      );
    }

    final targetStream = hasFamily
        ? _familyNotifStream(fid)
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
                final rawDocs = snap.data?.docs ?? [];

                final now = DateTime.now();
                final todayOnly = DateTime(now.year, now.month, now.day);

                int? resolveDaysLeft(Map<String, dynamic> data) {
                  final daysLeftRaw = (data['daysLeft'] as num?)?.toInt();
                  if (daysLeftRaw != null) return daysLeftRaw;
                  final expiryRaw = data['expiresOn'];
                  if (expiryRaw is Timestamp) {
                    final expiry = expiryRaw.toDate();
                    final onlyExpiry = DateTime(
                      expiry.year,
                      expiry.month,
                      expiry.day,
                    );
                    return onlyExpiry.difference(todayOnly).inDays;
                  } else if (expiryRaw is DateTime) {
                    final onlyExpiry = DateTime(
                      expiryRaw.year,
                      expiryRaw.month,
                      expiryRaw.day,
                    );
                    return onlyExpiry.difference(todayOnly).inDays;
                  }
                  return null;
                }

                DateTime? asDate(dynamic value) {
                  if (value is Timestamp) return value.toDate();
                  if (value is DateTime) return value;
                  return null;
                }

                final docs = rawDocs.where((doc) {
                  final data = doc.data();
                  if ((data['type'] ?? '') != 'expiry') return false;
                  final daysLeft = resolveDaysLeft(data);
                  if (daysLeft == null) return false;
                  return daysLeft >= 0 && daysLeft <= 3;
                }).toList();

                docs.sort((a, b) {
                  final dataA = a.data();
                  final dataB = b.data();
                  final daysA = resolveDaysLeft(dataA) ?? 999;
                  final daysB = resolveDaysLeft(dataB) ?? 999;
                  final cmpDays = daysA.compareTo(daysB);
                  if (cmpDays != 0) return cmpDays;
                  final expiryA = asDate(dataA['expiresOn']);
                  final expiryB = asDate(dataB['expiresOn']);
                  if (expiryA != null && expiryB != null) {
                    final cmpExpiry = expiryA.compareTo(expiryB);
                    if (cmpExpiry != 0) return cmpExpiry;
                  }
                  final createdA = asDate(dataA['createdAt']);
                  final createdB = asDate(dataB['createdAt']);
                  if (createdA != null && createdB != null) {
                    final cmpCreated = createdA.compareTo(createdB);
                    if (cmpCreated != 0) return cmpCreated;
                  } else if (createdA != null) {
                    return -1;
                  } else if (createdB != null) {
                    return 1;
                  }
                  return a.id.compareTo(b.id);
                });

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
                      final level = _resolveLevel(d);
                      final daysLeft = resolveDaysLeft(d);
                      final itemNameSource = d['itemName'];
                      final itemName =
                          itemNameSource is String &&
                                  itemNameSource.trim().isNotEmpty
                              ? itemNameSource.trim()
                              : title;
                      String? category;
                      final categoryRaw = d['category'];
                      if (categoryRaw is String) {
                        category = categoryRaw;
                      } else if (categoryRaw != null) {
                        category = categoryRaw.toString();
                      }
                      if (category == null || category.trim().isEmpty) {
                        final subRaw = d['subcategory'];
                        String? subcategory;
                        if (subRaw is String) {
                          subcategory = subRaw.trim();
                        } else if (subRaw != null) {
                          subcategory = subRaw.toString().trim();
                        }
                        if (subcategory != null && subcategory.isNotEmpty) {
                          final catFromSub =
                              Categories.categoryForSubcategory(subcategory);
                          if (catFromSub != null && catFromSub.isNotEmpty) {
                            category = catFromSub;
                          }
                        }
                      }
                      final expiresOn =
                          (d['expiresOn'] as Timestamp?)?.toDate();
                      final isRead = (d['read'] ?? false) as bool;

                      return _NotificationCard(
                        title: itemName,
                        level: level,
                        daysLeft: daysLeft,
                        category: category,
                        expiryDate: expiresOn,
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
  final String level;
  final int? daysLeft;
  final String? category;
  final DateTime? expiryDate;
  final bool isRead;
  final VoidCallback? onTap;

  const _NotificationCard({
    required this.title,
    required this.level,
    this.daysLeft,
    this.category,
    this.expiryDate,
    this.isRead = false,
    this.onTap,
  });

  String get _badgeText {
    final dl = daysLeft;
    if (dl != null) {
      return dl <= 0 ? 'หมดอายุวันนี้' : 'หมดอายุในอีก $dl วัน';
    }
    switch (level) {
      case 'today':
        return 'หมดอายุวันนี้';
      case 'in_1':
        return 'หมดอายุในอีก 1 วัน';
      case 'in_2':
        return 'หมดอายุในอีก 2 วัน';
      case 'in_3':
        return 'หมดอายุในอีก 3 วัน';
      default:
        return 'หมดอายุเร็ว ๆ นี้';
    }
  }

  IconData get _icon {
    final cat = category?.trim();
    if (cat != null && cat.isNotEmpty) {
      return Categories.iconFor(cat);
    }
    final dl = daysLeft;
    if (dl != null) {
      if (dl <= 0) return Icons.error_outline;
      if (dl == 1) return Icons.warning_amber_outlined;
      if (dl <= 3) return Icons.event_available_outlined;
      return Icons.notifications_outlined;
    }
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

  Color get _badgeColor {
    final dl = daysLeft;
    if (dl != null) {
      if (dl <= 1) return Colors.red;
      if (dl <= 3) return Colors.orange;
      return Colors.green;
    }
    switch (level) {
      case 'today':
      case 'in_1':
        return Colors.red;
      case 'in_2':
      case 'in_3':
        return Colors.orange;
      default:
        return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleColor = isRead
        ? Colors.grey.shade700
        : Colors.black.withValues(alpha: 0.85);
    final detailColor =
        isRead ? Colors.grey.shade600 : Colors.grey.shade700;
    final hasCategoryIcon = (category?.trim().isNotEmpty ?? false);
    final avatarBg =
        hasCategoryIcon ? Colors.grey.shade200 : Colors.grey.shade100;
    final iconColor = hasCategoryIcon
        ? Colors.grey.shade700
        : Colors.black.withValues(alpha: 0.7);
    final categoryLabel = (category?.trim().isNotEmpty ?? false)
        ? Categories.normalize(category!.trim())
        : 'ไม่ระบุหมวดหมู่';
    final expiryLabel = expiryDate != null
        ? DateFormat('dd/MM/yyyy').format(expiryDate!)
        : '-';

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
              backgroundColor: avatarBg,
              child: Icon(_icon, color: iconColor),
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
                      _Badge(text: _badgeText, color: _badgeColor),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    categoryLabel,
                    style: TextStyle(
                      color: detailColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'วันหมดอายุ: $expiryLabel',
                    style: TextStyle(
                      color: detailColor.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w600,
        ),
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
