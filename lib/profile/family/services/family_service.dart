// lib/profile/family/services/family_service.dart
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FamilyService {
  FamilyService(
    this.familyId, {
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final String familyId;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _members =>
      _firestore.collection('family_members');
  CollectionReference<Map<String, dynamic>> get _invites =>
      _firestore.collection('family_invites');
  CollectionReference<Map<String, dynamic>> get _stats =>
      _firestore.collection('family_stats');
  CollectionReference<Map<String, dynamic>> get _settings =>
      _firestore.collection('family_settings');

  String get _uid {
    final u = _auth.currentUser;
    if (u == null) throw Exception('โปรดเข้าสู่ระบบก่อน');
    return u.uid;
  }

  String _randomCode({int length = 8}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }

  String _normalizeRole(String role) {
    final r = role.trim().toLowerCase();
    return r == 'admin' ? 'admin' : 'member';
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Bootstrap / Create
  // ────────────────────────────────────────────────────────────────────────────

  static String _resolveAdminDisplayName(String? displayName, String? email) {
    final trimmedDisplay = displayName?.trim() ?? '';
    if (trimmedDisplay.isNotEmpty) return trimmedDisplay;
    final trimmedEmail = email?.trim() ?? '';
    if (trimmedEmail.contains('@')) {
      return trimmedEmail.split('@').first;
    }
    if (trimmedEmail.isNotEmpty) return trimmedEmail;
    return 'ไม่ระบุชื่อ';
  }

  static Future<String> createFamilyForUser({
    required String uid,
    String? displayName,
    String? email,
    String? photoUrl,
    String? familyName,
    FirebaseFirestore? firestore,
  }) async {
    final fs = firestore ?? FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();

    final familiesRef = fs.collection('families').doc();
    final familyId = familiesRef.id;

    final userRef = fs.collection('users').doc(uid);
    final memberRef = fs.collection('family_members').doc('${familyId}_$uid');

    final resolvedName = _resolveAdminDisplayName(displayName, email);

    await fs.runTransaction((txn) async {
      txn.set(familiesRef, {
        'id': familyId,
        'name': (familyName ?? 'ครอบครัวของฉัน').trim(),
        'createdBy': uid,
        'createdAt': now,
        'updatedAt': now,
      });

      txn.set(memberRef, {
        'familyId': familyId,
        'userId': uid,
        'role': 'admin',
        'displayName': resolvedName,
        'email': email ?? '',
        'photoUrl': photoUrl ?? '',
        'addedAt': now,
        'updatedAt': now,
      });

      txn.set(userRef, {
        'familyId': familyId,
        'familyRole': 'admin',
        if (resolvedName.isNotEmpty) 'displayName': resolvedName,
        'email': email ?? FieldValue.delete(),
        'photoUrl': photoUrl ?? FieldValue.delete(),
        'updatedAt': now,
      }, SetOptions(merge: true));
    });

    await fs.collection('family_stats').doc(familyId).set({
      'familyId': familyId,
      'members': 1,
      'admins': 1,
      'createdAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    return familyId;
  }

  static Future<void> ensureUserDoc({
    required String uid,
    FirebaseFirestore? firestore,
  }) async {
    final fs = firestore ?? FirebaseFirestore.instance;
    final ref = fs.collection('users').doc(uid);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Read / Stats
  // ────────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> loadFamilyData() async {
    final membersSnap = await _members
        .where('familyId', isEqualTo: familyId)
        .orderBy('addedAt', descending: false)
        .get();

    final members = membersSnap.docs
        .map((d) => {'id': d.id, ...d.data()})
        .toList();

    final statsDoc = await _stats.doc(familyId).get();
    final stats = statsDoc.data() ?? {};

    return {'members': members, 'stats': stats};
  }

  Future<Map<String, dynamic>> generateFamilyStats() async {
    final snap = await _members.where('familyId', isEqualTo: familyId).get();

    int total = 0;
    int admins = 0;
    for (final d in snap.docs) {
      total++;
      final role = (d.data()['role'] as String?)?.toLowerCase() ?? 'member';
      if (role == 'admin') admins++;
    }

    return {
      'familyId': familyId,
      'members': total,
      'admins': admins,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> saveFamilyStats(Map<String, dynamic> stats) async {
    await _stats.doc(familyId).set(stats, SetOptions(merge: true));
  }

  Future<void> updateFamilyStats() async {
    final s = await generateFamilyStats();
    await saveFamilyStats(s);
    final members = (s['members'] as int?) ?? 0;
    if (members == 0) {
      await _cleanupFamilyIfNoMembersStatic(
        firestore: _firestore,
        familyId: familyId,
      );
    }
  }

  Future<void> ensureMemberHasNameEmail({required String uid}) async {
    final ref = _members.doc('${familyId}_$uid');
    final snap = await ref.get();
    if (!snap.exists) return;

    Map<String, dynamic>? userData;
    try {
      final userSnap = await _users.doc(uid).get();
      userData = userSnap.data();
    } catch (_) {
      userData = null;
    }

    final current = snap.data() ?? <String, dynamic>{};
    final updates = <String, dynamic>{};

    final resolvedName = _resolveDisplayName(userData, current);
    final resolvedEmail = _resolveEmail(userData, current);
    final resolvedPhoto = _resolvePhoto(userData, current);

    if (resolvedName != null &&
        resolvedName.trim().isNotEmpty &&
        resolvedName != (current['displayName'] as String?)) {
      updates['displayName'] = resolvedName;
    }
    if (resolvedEmail != null &&
        resolvedEmail.trim().isNotEmpty &&
        resolvedEmail != (current['email'] as String?)) {
      updates['email'] = resolvedEmail;
    }
    if (resolvedPhoto != null &&
        resolvedPhoto.trim().isNotEmpty &&
        resolvedPhoto != (current['photoUrl'] as String?)) {
      updates['photoUrl'] = resolvedPhoto;
    }

    if (updates.isNotEmpty) {
      updates['updatedAt'] = FieldValue.serverTimestamp();
      await ref.set(updates, SetOptions(merge: true));
    }

    if (uid == _uid) {
      await _users.doc(uid).set({
        if (resolvedName != null && resolvedName.isNotEmpty)
          'displayName': resolvedName,
        if (resolvedEmail != null && resolvedEmail.isNotEmpty)
          'email': resolvedEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> syncFamilyMemberProfiles() async {
    final membersSnap = await _members
        .where('familyId', isEqualTo: familyId)
        .get();
    if (membersSnap.docs.isEmpty) return;

    for (final doc in membersSnap.docs) {
      final data = doc.data();
      final memberUid =
          (data['userId'] as String?) ?? (data['uid'] as String?) ?? '';
      if (memberUid.isEmpty) continue;
      try {
        await ensureMemberHasNameEmail(uid: memberUid);
      } catch (_) {
        // swallow individual failures to avoid breaking the whole sync
      }
    }
  }

  String? _resolveDisplayName(
    Map<String, dynamic>? userDoc,
    Map<String, dynamic> memberDoc,
  ) {
    final fromUser = _normalize(userDoc?['displayName']);
    if (fromUser != null) return fromUser;

    final fromMember = _normalize(memberDoc['displayName']);
    if (fromMember != null) return fromMember;

    final fallbackEmail =
        _normalize(userDoc?['email']) ?? _normalize(memberDoc['email']);
    if (fallbackEmail != null && fallbackEmail.contains('@')) {
      return fallbackEmail.split('@').first;
    }
    return fallbackEmail;
  }

  String? _resolveEmail(
    Map<String, dynamic>? userDoc,
    Map<String, dynamic> memberDoc,
  ) {
    final fromUser = _normalize(userDoc?['email']);
    final fromMember = _normalize(memberDoc['email']);
    return fromUser ?? fromMember;
  }

  String? _resolvePhoto(
    Map<String, dynamic>? userDoc,
    Map<String, dynamic> memberDoc,
  ) {
    final fromUser =
        _normalize(userDoc?['photoURL']) ?? _normalize(userDoc?['photoUrl']);
    final fromMember = _normalize(memberDoc['photoUrl']);
    return fromUser ?? fromMember;
  }

  String? _normalize(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Member Management
  // ────────────────────────────────────────────────────────────────────────────

  Future<bool> isCurrentUserAdmin() async {
    final q = await _members
        .where('familyId', isEqualTo: familyId)
        .where('userId', isEqualTo: _uid)
        .where('role', isEqualTo: 'admin')
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  Future<void> addFamilyMember({
    required String targetUserId,
    String role = 'member',
    String? displayName,
    String? email,
    String? photoUrl,
  }) async {
    if (!await isCurrentUserAdmin()) {
      throw Exception('สิทธิ์ไม่พอ (ต้องเป็นผู้ดูแล)');
    }
    final newRole = _normalizeRole(role);
    final now = FieldValue.serverTimestamp();
    final memberRef = _members.doc('${familyId}_$targetUserId');

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(memberRef);
      if (snap.exists) {
        txn.set(memberRef, {
          'role': newRole,
          if (displayName != null) 'displayName': displayName,
          if (email != null) 'email': email,
          if (photoUrl != null) 'photoUrl': photoUrl,
          'updatedAt': now,
        }, SetOptions(merge: true));
      } else {
        txn.set(memberRef, {
          'familyId': familyId,
          'userId': targetUserId,
          'role': newRole,
          'displayName': displayName ?? '',
          'email': email ?? '',
          'photoUrl': photoUrl ?? '',
          'addedAt': now,
          'updatedAt': now,
        });
      }

      txn.set(_users.doc(targetUserId), {
        'familyId': familyId,
        'familyRole': newRole,
        'updatedAt': now,
      }, SetOptions(merge: true));
    });

    await updateFamilyStats();
  }

  Future<void> updateFamilyMember({
    required String targetUserId,
    String? role,
    String? displayName,
    String? email,
    String? photoUrl,
  }) async {
    if (!await isCurrentUserAdmin()) {
      throw Exception('สิทธิ์ไม่พอ (ต้องเป็นผู้ดูแล)');
    }
    final now = FieldValue.serverTimestamp();
    final memberRef = _members.doc('${familyId}_$targetUserId');
    final newRole = role == null ? null : _normalizeRole(role);

    await _firestore.runTransaction((txn) async {
      final snap = await txn.get(memberRef);
      if (!snap.exists) {
        throw Exception('ไม่พบบุคคลนี้ในครอบครัว');
      }

      txn.set(memberRef, {
        if (newRole != null) 'role': newRole,
        if (displayName != null) 'displayName': displayName,
        if (email != null) 'email': email,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'updatedAt': now,
      }, SetOptions(merge: true));

      txn.set(_users.doc(targetUserId), {
        'familyId': familyId,
        if (newRole != null) 'familyRole': newRole,
        'updatedAt': now,
      }, SetOptions(merge: true));
    });

    await updateFamilyStats();
  }

  Future<void> renameFamily(String newName) async {
    if (!await isCurrentUserAdmin()) {
      throw Exception('สิทธิ์ไม่พอ (ต้องเป็นผู้ดูแล)');
    }

    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw Exception('กรุณากรอกชื่อครอบครัว');
    }

    final now = FieldValue.serverTimestamp();
    final famRef = _firestore.collection('families').doc(familyId);
    final statsRef = _stats.doc(familyId);

    await _firestore.runTransaction((txn) async {
      final famSnap = await txn.get(famRef);
      if (!famSnap.exists) {
        throw Exception('ไม่พบครอบครัวนี้แล้ว');
      }

      txn.set(famRef, {
        'name': trimmed,
        'updatedAt': now,
      }, SetOptions(merge: true));

      txn.set(statsRef, {'updatedAt': now}, SetOptions(merge: true));
    });
  }

  /// ลบสมาชิก (รองรับกรณี family_members ใช้ autoId)
  Future<void> removeMember({required String targetUserId}) async {
    if (!await isCurrentUserAdmin()) {
      throw Exception('สิทธิ์ไม่พอ (ต้องเป็นผู้ดูแล)');
    }
    final normalizedTarget = targetUserId.trim();
    if (normalizedTarget.isEmpty) {
      throw Exception('ไม่พบข้อมูลสมาชิกที่ต้องการนำออก');
    }
    if (normalizedTarget == _uid) {
      throw Exception('ไม่สามารถนำตัวเองออก ใช้เมนูออกจากครอบครัวแทน');
    }

    DocumentReference<Map<String, dynamic>>? resolvedRef;

    // รองรับข้อมูลเดิมที่เคยใช้ field uid หรือ docId รูปแบบ fid_uid
    final byUserId = await _members
        .where('familyId', isEqualTo: familyId)
        .where('userId', isEqualTo: normalizedTarget)
        .limit(1)
        .get();
    if (byUserId.docs.isNotEmpty) {
      resolvedRef = byUserId.docs.first.reference;
    } else {
      final byLegacyUid = await _members
          .where('familyId', isEqualTo: familyId)
          .where('uid', isEqualTo: normalizedTarget)
          .limit(1)
          .get();
      if (byLegacyUid.docs.isNotEmpty) {
        resolvedRef = byLegacyUid.docs.first.reference;
      } else {
        final fallbackDoc = await _members
            .doc('${familyId}_$normalizedTarget')
            .get();
        if (fallbackDoc.exists) {
          resolvedRef = fallbackDoc.reference;
        }
      }
    }

    final memberRef = resolvedRef;
    if (memberRef == null) {
      throw Exception('ไม่พบบุคคลนี้ในครอบครัว');
    }

    final userRef = _users.doc(normalizedTarget);
    final roleMirrorRef = _firestore
        .collection('family_roles')
        .doc(familyId)
        .collection('members')
        .doc(normalizedTarget);

    await _firestore.runTransaction((txn) async {
      final memSnap = await txn.get(memberRef);
      if (!memSnap.exists) {
        throw Exception('ไม่พบบุคคลนี้ในครอบครัว');
      }

      txn.delete(memberRef);
      txn.delete(roleMirrorRef);
    });

    await userRef.set({
      'familyId': null,
      'familyRole': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _cleanupFamilyIfNoMembersStatic(
      firestore: _firestore,
      familyId: familyId,
    );
    await updateFamilyStats();
  }

  static Future<void> leaveFamily({
    required String uid,
    FirebaseFirestore? firestore,
  }) async {
    final fs = firestore ?? FirebaseFirestore.instance;
    final users = fs.collection('users');
    final members = fs.collection('family_members');

    final uSnap = await users.doc(uid).get();
    final fid = uSnap.data()?['familyId'] as String?;
    if (fid == null || fid.isEmpty) return;

    // เช็คบทบาทตัวเอง
    final myMem = await members.doc('${fid}_$uid').get();
    final myRole =
        (myMem.data()?['role'] as String?)?.toLowerCase() ?? 'member';

    // ❌ แอดมิน "ออก" ไม่ได้ ให้ไปใช้ "ยุบครอบครัว"
    if (myRole == 'admin') {
      throw Exception(
        'ผู้ดูแลไม่สามารถออกจากครอบครัวได้ กรุณาใช้เมนู "ยุบครอบครัว"',
      );
    }

    // --- member leave ตามปกติ (ลบเอกสารตัวเอง + เคลียร์ users + อัปเดตสถิติ/ลบครอบครัวถ้าไม่เหลือใคร) ---
    final now = FieldValue.serverTimestamp();
    final famRef = fs.collection('families').doc(fid);
    final statsRef = fs.collection('family_stats').doc(fid);
    final settingsRef = fs.collection('family_settings').doc(fid);

    // ดูว่าเหลือคนไหม (ดึง 2 พอ)
    final memSnap = await members
        .where('familyId', isEqualTo: fid)
        .limit(2)
        .get();
    final onlySelf = memSnap.docs.length <= 1;

    await fs.runTransaction((txn) async {
      final memRef = members.doc('${fid}_$uid');
      final memDoc = await txn.get(memRef);
      if (memDoc.exists) txn.delete(memRef);

      if (onlySelf) {
        // ถ้าออกแล้วไม่เหลือใคร ให้ลบของครอบครัว
        if ((await txn.get(famRef)).exists) txn.delete(famRef);
        if ((await txn.get(statsRef)).exists) txn.delete(statsRef);
        if ((await txn.get(settingsRef)).exists) txn.delete(settingsRef);
      }

      txn.set(users.doc(uid), {
        'familyId': null,
        'familyRole': null,
        'updatedAt': now,
      }, SetOptions(merge: true));
    });

    if (!onlySelf) {
      final rem = await members.where('familyId', isEqualTo: fid).get();
      await statsRef.set({
        'familyId': fid,
        'members': rem.docs.length,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Invite / Join
  // ────────────────────────────────────────────────────────────────────────────

  /// สร้างโค้ดเชิญ (สมาชิกคนใดก็ได้ในครอบครัว)
  Future<String> createInviteCode({
    required String createdBy,
    Duration ttl = const Duration(hours: 24),
  }) async {
    if (createdBy.isEmpty) throw Exception('createdBy ว่าง');

    // เป็นสมาชิกของครอบครัวนี้พอ (ไม่ต้องเป็น admin)
    final memberCheck = await _members
        .where('familyId', isEqualTo: familyId)
        .where('userId', isEqualTo: createdBy)
        .limit(1)
        .get();
    if (memberCheck.docs.isEmpty) {
      throw Exception('สิทธิ์ไม่พอ (ต้องเป็นสมาชิกในครอบครัว)');
    }

    final now = DateTime.now().toUtc();
    final expiresAt = now.add(ttl);

    String code;
    DocumentSnapshot<Map<String, dynamic>> snap;
    do {
      code = _randomCode(length: 8);
      snap = await _invites.doc(code).get();
    } while (snap.exists);

    await _invites.doc(code).set({
      'code': code,
      'familyId': familyId,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    return code;
  }

  Future<InviteCodeResult> createInviteCodeAndPayload({
    required String createdBy,
  }) async {
    final code = await createInviteCode(createdBy: createdBy);
    final payload = 'CODE:$code|FID:$familyId';
    return InviteCodeResult(code: code, payload: payload);
  }

  Future<String> generateInviteQRData({required String createdBy}) async {
    final res = await createInviteCodeAndPayload(createdBy: createdBy);
    return res.payload;
  }

  Future<void> joinFamilyByQrPayload(
    String payload, {
    required String userId,
  }) async {
    final parts = payload.split('|');
    String? code;
    String? fid;
    for (final p in parts) {
      final kv = p.split(':');
      if (kv.length == 2) {
        if (kv[0] == 'CODE') code = kv[1];
        if (kv[0] == 'FID') fid = kv[1];
      }
    }
    if (code == null || fid == null) {
      throw Exception('ข้อมูล QR ไม่ถูกต้อง');
    }
    await joinFamilyByCode(code, userId: userId);
  }

  /// เข้าร่วมครอบครัว: บล็อกถ้ามีครอบครัวอยู่แล้ว + เขียนแบบสองจังหวะ + ใส่ชื่อ/อีเมล
  Future<void> joinFamilyByCode(String code, {required String userId}) async {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) throw Exception('โค้ดว่าง');

    // 0) บล็อกถ้ามีครอบครัวอยู่แล้ว
    final my = await _users.doc(userId).get();
    final currentFid = my.data()?['familyId'] as String?;
    if (currentFid != null && currentFid.isNotEmpty) {
      throw Exception('คุณมีครอบครัวอยู่แล้ว ไม่สามารถเข้าร่วมครอบครัวอื่นได้');
    }

    // 1) อ่านโค้ดเชิญ
    final doc = await _invites.doc(c).get();
    if (!doc.exists) throw Exception('โค้ดไม่ถูกต้อง');

    final data = doc.data()!;
    final fid = data['familyId'] as String?;
    final expiresAt = data['expiresAt'] as Timestamp?;
    if (fid == null) throw Exception('โค้ดเสียหาย');
    if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
      throw Exception('โค้ดหมดอายุแล้ว');
    }

    final now = FieldValue.serverTimestamp();

    // 2) users -> set family
    await _users.doc(userId).set({
      'familyId': fid,
      'familyRole': 'member',
      'updatedAt': now,
    }, SetOptions(merge: true));
    // 2.1) บังคับให้ users/{uid} มี email/displayName ตั้งแต่ตอน join
    final au = _auth.currentUser;
    final displayName = (au?.displayName?.trim().isNotEmpty == true)
        ? au!.displayName!.trim()
        : null;
    final email = au?.email ?? '';

    await _users.doc(userId).set({
      if (email.isNotEmpty) 'email': email,
      if ((displayName ?? '').isNotEmpty) 'displayName': displayName,
      'updatedAt': now,
    }, SetOptions(merge: true));

    // 3) family_members -> add
    final photo = au?.photoURL ?? '';

    await _members.doc('${fid}_$userId').set({
      'familyId': fid,
      'userId': userId,
      'role': 'member',
      'displayName': displayName ?? email,
      'email': email,
      'photoUrl': photo,
      'addedAt': now,
      'updatedAt': now,
    }, SetOptions(merge: true));

    // 4) พยายามอัปเดตสถิติ (หากไม่ใช่แอดมิน ให้เงียบ ๆ)
    try {
      await FamilyService(fid, firestore: _firestore).updateFamilyStats();
    } catch (_) {
      /* ignore */
    }

    try {
      final svc = FamilyService(fid, firestore: _firestore);
      await svc.ensureMemberHasNameEmail(uid: userId);
      await svc.syncFamilyMemberProfiles();
    } catch (_) {
      // best-effort sync; ignore failures here.
    }
  }

  /// ยุบครอบครัว (ผู้ดูแลเท่านั้น)
  static Future<void> disbandFamilyByAdmin({
    required String familyId,
    required String currentUid,
    FirebaseFirestore? firestore,
  }) async {
    final fs = firestore ?? FirebaseFirestore.instance;
    const batchSize = 450;

    Future<void> batchedDelete(Query<Map<String, dynamic>> query) async {
      while (true) {
        final snap = await query.limit(batchSize).get();
        if (snap.docs.isEmpty) break;

        final batch = fs.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        if (snap.docs.length < batchSize) break;
      }
    }

    Future<void> batchedUpdateUsers(Iterable<String> userIds) async {
      final ids = userIds.toList();
      for (var i = 0; i < ids.length; i += batchSize) {
        final chunk = ids.sublist(i, min(i + batchSize, ids.length));
        final batch = fs.batch();
        for (final uid in chunk) {
          batch.set(fs.collection('users').doc(uid), {
            'familyId': null,
            'familyRole': null,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        await batch.commit();
      }
    }

    final adminSnap = await fs
        .collection('family_members')
        .where('familyId', isEqualTo: familyId)
        .where('userId', isEqualTo: currentUid)
        .limit(1)
        .get();

    final adminData = adminSnap.docs.isNotEmpty
        ? adminSnap.docs.first.data()
        : null;
    final adminRole = (adminData?['role'] as String?)?.toLowerCase();
    if (adminData == null || adminRole != 'admin') {
      throw Exception('สิทธิ์ไม่พอหรือไม่ได้อยู่ในครอบครัวนี้แล้ว');
    }

    final membersSnap = await fs
        .collection('family_members')
        .where('familyId', isEqualTo: familyId)
        .get();

    final userIds = <String>{
      for (final doc in membersSnap.docs)
        ((doc.data()['userId'] as String?) ??
                (doc.data()['uid'] as String?) ??
                '')
            .trim(),
    }..removeWhere((uid) => uid.isEmpty);

    await batchedDelete(
      fs.collection('family_roles').doc(familyId).collection('members'),
    );
    await fs
        .collection('family_roles')
        .doc(familyId)
        .delete()
        .catchError((_) {});

    await batchedDelete(
      fs.collection('family_members').where('familyId', isEqualTo: familyId),
    );

    await fs
        .collection('family_stats')
        .doc(familyId)
        .delete()
        .catchError((_) {});
    await fs
        .collection('family_settings')
        .doc(familyId)
        .delete()
        .catchError((_) {});

    final backupsDoc = fs.collection('family_backups').doc(familyId);
    await batchedDelete(backupsDoc.collection('backups'));
    await backupsDoc.delete().catchError((_) {});

    await batchedDelete(
      fs.collection('family_invites').where('familyId', isEqualTo: familyId),
    );
    await fs.collection('families').doc(familyId).delete();

    if (userIds.isNotEmpty) {
      await batchedUpdateUsers(userIds);
    }
  }

  static Future<void> _cleanupFamilyIfNoMembersStatic({
    required FirebaseFirestore firestore,
    required String familyId,
  }) async {
    final rem = await firestore
        .collection('family_members')
        .where('familyId', isEqualTo: familyId)
        .limit(1)
        .get();
    if (rem.docs.isNotEmpty) return;

    await firestore
        .collection('families')
        .doc(familyId)
        .delete()
        .catchError((_) {});
    await firestore.collection('family_stats').doc(familyId).set({
      'familyId': familyId,
      'members': 0,
      'admins': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await firestore
        .collection('family_stats')
        .doc(familyId)
        .delete()
        .catchError((_) {});
    await firestore
        .collection('family_settings')
        .doc(familyId)
        .delete()
        .catchError((_) {});

    // ลบ roles/doc ด้วย (กันลืม)
    await firestore
        .collection('family_roles')
        .doc(familyId)
        .delete()
        .catchError((_) {});
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Settings
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> saveDefaultPermissions(Map<String, bool> permissions) async {
    await _settings.doc(familyId).set({
      'permissions': permissions,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, bool>> loadDefaultPermissions() async {
    final doc = await _settings.doc(familyId).get();
    final map = (doc.data()?['permissions'] as Map<String, dynamic>?) ?? {};
    return map.map((k, v) => MapEntry(k, v == true));
  }
}

class InviteCodeResult {
  final String code;
  final String payload;
  InviteCodeResult({required this.code, required this.payload});
}
