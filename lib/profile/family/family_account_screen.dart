// lib/profile/family/family_account_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'dialogs/create_family_dialog.dart';
import 'dialogs/invite_code_dialog.dart';
import 'dialogs/qr_code_dialog.dart';
import 'family_hub_screen.dart';
import 'services/family_service.dart';

// ใช้ alias ป้องกันชื่อซ้อนกัน
import 'widgets/family_members_grid.dart' as grid;
import 'widgets/member_card.dart' as mc; // มี MemberCardAction
import 'widgets/quick_actions_row.dart';

class FamilyAccountScreen extends StatefulWidget {
  static const route = '/family/account';

  const FamilyAccountScreen({
    super.key,
    this.fidOverride,
    this.showBack = false,
  });

  final String? fidOverride;
  final bool showBack;

  @override
  State<FamilyAccountScreen> createState() => _FamilyAccountScreenState();
}

class _FamilyAccountScreenState extends State<FamilyAccountScreen> {
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  bool _loading = true;
  bool _isAdmin = false;
  bool _navigatingToHub = false;

  String? _fid;
  String? _familyName;

  FamilyService? _svc;
  // ฟังสถานะ users/{me}.familyId เพื่อเด้งออกเมื่อถูกลบจากครอบครัว
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _meSub;

  @override
  void dispose() {
    _meSub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _loading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) {
        _showErr('Please sign in first');
        _resetFamilyState();
        _goToHub();
        return;
      }

      // 1) หา fid เร็วที่สุดโดยไม่บล็อคด้วยงานอื่น
      String? fid = widget.fidOverride;
      if (fid == null || fid.isEmpty) {
        final userDoc = await _fs.collection('users').doc(user.uid).get();
        fid = (userDoc.data()?['familyId'] as String?)?.trim();
      }
      if (fid == null || fid.isEmpty) {
        _resetFamilyState();
        if (mounted) setState(() => _loading = false);
        return;
      }

      _fid = fid;
      _svc = FamilyService(fid);

      // 2) ยิงงาน "สำคัญ" แบบขนาน (รอผล) และงาน "ไม่เร่งด่วน" แบบ background (ไม่ await)
      final famDocF = _fs.collection('families').doc(fid).get();
      final isAdminF = _svc!.isCurrentUserAdmin();

      // งานไม่เร่งด่วน: ทำแบบไม่บล็อค UI
      // - ensureMemberHasNameEmail: อัปเดตชื่อ/อีเมลใน member ถ้ายังไม่มี
      // - syncFamilyMemberProfiles: ไล่ sync โปรไฟล์ทั้งบ้าน
      // ไม่ต้อง await เพื่อให้ UI ขึ้นก่อน
      unawaited(
        _svc!.ensureMemberHasNameEmail(uid: user.uid).catchError((_) {}),
      );
      unawaited(_svc!.syncFamilyMemberProfiles().catchError((_) {}));

      // 3) รอเฉพาะของที่ UI ต้องใช้ทันที (ชื่อบ้าน + สิทธิ์ admin)
      final famDoc = await famDocF;
      final isAdmin = await isAdminF;

      final familyName = (famDoc.data()?['name'] as String?)?.trim();

      if (!mounted) return;
      setState(() {
        _familyName = familyName;
        _isAdmin = isAdmin;
      });

      // 4) ตั้ง listener เด้งออกเมื่อโดนลบออกจากครอบครัว (ทำหลัง UI setState)
      await _meSub?.cancel();
      _meSub = _fs.collection('users').doc(user.uid).snapshots().listen((doc) {
        final data = doc.data();
        final fidLive = (data?['familyId'] as String?)?.trim();

        if ((_fid != null && _fid!.isNotEmpty) &&
            (fidLive == null || fidLive.isEmpty)) {
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => const FamilyHubScreen(showBack: true),
              ),
              (_) => false,
            );
          }
          return;
        }

        if (fidLive != null && fidLive.isNotEmpty && fidLive != _fid) {
          if (mounted) setState(() => _fid = fidLive);
        }
      });
    } catch (e) {
      _showErr('Failed to load data: $e');
    } finally {
      if (mounted && !_navigatingToHub) setState(() => _loading = false);
    }
  }

  Future<void> _handleMemberAction({
    required String targetUserId,
    required mc.MemberCardAction action, // ← ใช้ mc.
  }) async {
    if (_svc == null) return;
    try {
      if (action == mc.MemberCardAction.remove) {
        // ← ใช้ mc.
        await _svc!.removeMember(targetUserId: targetUserId);
        _showOk('Member removed from family');
      }
    } catch (e) {
      _showErr('Operation failed: $e');
    }
  }

  Future<void> _handleGridAction({
    required String action,
    required String targetUid,
    required String role,
  }) async {
    final mc.MemberCardAction? mapped = switch (action) {
      'remove' => mc.MemberCardAction.remove,
      _ => null,
    };
    if (mapped == null) return;
    await _handleMemberAction(targetUserId: targetUid, action: mapped);
  }

  Future<void> _showInviteQR() async {
    if (_svc == null) return;
    final current = _auth.currentUser;
    if (current == null) {
      _showErr('Please sign in first');
      return;
    }
    try {
      final result = await _svc!.createInviteCodeAndPayload(
        createdBy: current.uid,
      );
      if (!mounted) return;
      await QRCodeDialog.show(
        context: context,
        payload: result.payload,
        inviteCode: result.code,
      );
    } catch (e) {
      _showErr('Failed to create invite code: $e');
    }
  }

  Future<void> _joinByCode() async {
    final code = await InviteCodeDialog.show(context: context);
    if (code == null || code.isEmpty) return;

    final user = _auth.currentUser;
    if (user == null) {
      _showErr('Please sign in first');
      return;
    }

    try {
      await FamilyService('_tmp').joinFamilyByCode(code, userId: user.uid);
      await _init();
      _showOk('Joined family successfully');
    } catch (e) {
      _showErr('Failed to join family: $e');
    }
  }

  Future<void> _leaveFamily() async {
    final fid = _fid;
    if (fid == null) return;
    final ok = await _confirm(
      title: 'Leave family',
      message: 'Are you sure you want to leave this family?',
      danger: true,
    );
    if (!ok) return;

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await FamilyService.leaveFamily(uid: uid);
      _showOk('Left family successfully');
      _goToHub();
    } catch (e) {
      _showErr('Failed to leave family: $e');
    }
  }

  Future<void> _disbandFamily() async {
    final fid = _fid;
    if (fid == null) return;

    final ok = await _confirm(
      title: 'Disband family',
      message:
          'Disbanding the family removes all members and related data. This cannot be undone. Continue?',
      danger: true,
    );
    if (!ok) return;

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await FamilyService.disbandFamilyByAdmin(familyId: fid, currentUid: uid);
      _showOk('Family disbanded successfully');
      _goToHub();
    } catch (e) {
      _showErr('Failed to disband family: $e');
    }
  }

  Future<void> _createFamily() async {
    await CreateFamilyDialog.show(
      context: context,
      onCreated: (_) async {
        await _init();
      },
    );
  }

  Future<void> _renameFamily() async {
    final svc = _svc;
    if (svc == null) return;
    final currentName = _familyName ?? '';

    final controller = TextEditingController(text: currentName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename family'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(context).pop(controller.text),
          decoration: const InputDecoration(
            labelText: 'Family name',
            hintText: 'e.g. My Family',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    final trimmed = result?.trim();
    if (trimmed == null) return;
    if (trimmed.isEmpty) {
      _showErr('Please enter a family name');
      return;
    }
    if (trimmed == _familyName) return;

    try {
      await svc.renameFamily(trimmed);
      if (!mounted) return;
      setState(() => _familyName = trimmed);
      _showOk('Family name updated');
    } catch (e) {
      _showErr('Failed to update family name: $e');
    }
  }

  void _goToHub() {
    if (!mounted) return;
    _navigatingToHub = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const FamilyHubScreen(showBack: true)),
    );
  }

  void _resetFamilyState() {
    _fid = null;
    _svc = null;
    _familyName = null;
    _isAdmin = false;
  }

  void _showErr(String message) {
    if (!mounted) return;
    final sm = ScaffoldMessenger.of(context);
    sm.hideCurrentSnackBar();
    sm.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showOk(String message) {
    if (!mounted) return;
    final sm = ScaffoldMessenger.of(context);
    sm.hideCurrentSnackBar();
    sm.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? Colors.red : null,
            ),
            onPressed: () => Navigator.of(context).maybePop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  PreferredSizeWidget _appBar() {
    return AppBar(
      title: const Text('Family Account'),
      automaticallyImplyLeading: !widget.showBack,
      leading: widget.showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _handleBackToProfile,
            )
          : null,
    );
  }

  void _handleBackToProfile() {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.maybePop();
    } else {
      navigator.pushNamedAndRemoveUntil('/home/profile', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: _appBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_fid == null) {
      return const FamilyHubScreen(showBack: true);
    }

    return Scaffold(
      appBar: _appBar(),
      body: RefreshIndicator(
        onRefresh: _init,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FamilyHeaderCard(
                familyName: _familyName ?? 'My Family',
                isAdmin: _isAdmin,
                onRename: _isAdmin ? _renameFamily : null,
              ),
              const SizedBox(height: 24),
              const Text(
                'Family Members',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              grid.FamilyMembersGrid(
                familyId: _fid!,
                onAction: _handleGridAction,
              ),
              const SizedBox(height: 24),
              QuickActionsRow(
                hasFamily: true,
                isAdmin: _isAdmin,
                onInvite: _showInviteQR,
                onJoinFamily: _joinByCode,
                onLeaveFamily: _leaveFamily,
                onCreateFamily: _createFamily,
                onDisbandFamily: _isAdmin ? _disbandFamily : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FamilyHeaderCard extends StatelessWidget {
  const _FamilyHeaderCard({
    required this.familyName,
    required this.isAdmin,
    this.onRename,
  });

  final String familyName;
  final bool isAdmin;
  final Future<void> Function()? onRename;

  @override
  Widget build(BuildContext context) {
    final canRename = isAdmin && onRename != null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo.shade500, Colors.indigo.shade700],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.shade200.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  familyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const _ChipLabel(text: 'My Family'),
                    if (isAdmin) ...[
                      const SizedBox(width: 6),
                      const _ChipLabel(text: 'Admin'),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (canRename) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Rename family',
              onPressed: onRename,
              icon: const Icon(Icons.edit, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  const _ChipLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .2,
        ),
      ),
    );
  }
}
