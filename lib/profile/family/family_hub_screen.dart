// lib/profile/family/family_hub_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'family_account_screen.dart';
import 'join_family_scan_screen.dart';
import 'services/family_service.dart';

class FamilyHubScreen extends StatefulWidget {
  static const route = '/family/hub';
  const FamilyHubScreen({super.key, this.showBack = false});
  final bool showBack;
  @override
  State<FamilyHubScreen> createState() => _FamilyHubScreenState();
}

class _FamilyHubScreenState extends State<FamilyHubScreen> {
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _checkFamily();
  }

  Future<void> _checkFamily() async {
    setState(() => _checking = true);
    try {
      final u = _auth.currentUser;
      if (u == null) {
        _showErr('กรุณาเข้าสู่ระบบก่อน');
        return;
      }
      final userRef = _fs.collection('users').doc(u.uid);
      final userDoc = await userRef.get();
      final fid = userDoc.data()?['familyId'] as String?;

      if (fid == null || fid.isEmpty) {
        // ไม่มีครอบครัว → แสดง Hub ตามเดิม
        return;
      }

      // ✅ เช็คว่า families/{fid} ยังมีอยู่และเราอ่านได้ไหม
      final famDoc = await _fs.collection('families').doc(fid).get();
      if (!famDoc.exists) {
        // เคลียร์ familyId ที่ users เพื่อกันวนลูป
        await userRef.set({
          'familyId': null,
          'familyRole': null,
        }, SetOptions(merge: true));
        return;
      }

      if (!mounted) return;
      // ตอนเจอ fid หรือสร้างเสร็จ
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FamilyAccountScreen(fidOverride: fid, showBack: true),
        ),
      );
    } catch (e) {
      _showErr('ตรวจสอบครอบครัวไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  // ───────────────── Create family
  Future<void> _createFamilyFlow() async {
    final u = _auth.currentUser;
    if (u == null) {
      _showErr('กรุณาเข้าสู่ระบบก่อน');
      return;
    }

    final nameCtrl = TextEditingController(text: u.displayName ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('สร้างครอบครัวใหม่'),
        content: TextField(
          controller: nameCtrl,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.pop(c, true),
          decoration: const InputDecoration(
            labelText: 'ชื่อครอบครัว',
            hintText: 'เช่น ครอบครัวของฉัน',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('สร้าง'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await FamilyService.ensureUserDoc(uid: u.uid);

      final chosen = nameCtrl.text.trim();
      // แก้ (ถูก): displayName = ชื่อผู้ใช้ (fallback เป็นอีเมล), familyName = ชื่อครอบครัวจากช่องฟอร์ม
      final userDisplay =
          (u.displayName != null && u.displayName!.trim().isNotEmpty)
          ? u.displayName!.trim()
          : (u.email ?? 'ไม่ระบุ');

      final fid = await FamilyService.createFamilyForUser(
        uid: u.uid,
        displayName: userDisplay, // ✅ ชื่อผู้ใช้
        email: u.email,
        photoUrl: u.photoURL,
        familyName: chosen.isEmpty
            ? 'ครอบครัวของฉัน'
            : chosen, // ✅ ชื่อครอบครัว
      );

      if (!mounted) return;
      _showOk('สร้างครอบครัวสำเร็จ');
      // ตอนเจอ fid หรือสร้างเสร็จ
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FamilyAccountScreen(fidOverride: fid, showBack: true),
        ),
      );
    } catch (e) {
      _showErr('สร้างครอบครัวไม่สำเร็จ: $e');
    }
  }

  // ───────────────── Join by code or scan
  Future<void> _joinByCode() async {
    final codeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('เข้าร่วมด้วยโค้ด'),
        content: TextField(
          controller: codeCtrl,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
            UpperCaseTextFormatter(), // ด้านล่าง
          ],
          decoration: const InputDecoration(
            labelText: 'โค้ดเชิญ',
            hintText: 'พิมพ์โค้ดที่ได้รับ',
          ),
          onSubmitted: (_) => Navigator.pop(c, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('เข้าร่วม'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final raw = codeCtrl.text;
    final code = raw.replaceAll(' ', '').toUpperCase();
    if (code.isEmpty) return;

    try {
      final u = _auth.currentUser;
      if (u == null) throw 'กรุณาเข้าสู่ระบบก่อน';
      await FamilyService('_tmp').joinFamilyByCode(code, userId: u.uid);

      if (!mounted) return;
      _showOk('เข้าร่วมครอบครัวสำเร็จ');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const FamilyAccountScreen(showBack: true),
        ),
        (_) => false,
      );
    } catch (e) {
      _showErr('เข้าร่วมไม่สำเร็จ: $e');
    }
  }

  Future<void> _joinByScan() async {
    final joined = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const JoinFamilyScanScreen()),
    );
    if (joined == true && mounted) {
      _showOk('เข้าร่วมครอบครัวสำเร็จ');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const FamilyAccountScreen(showBack: true),
        ),
        (_) => false,
      );
    }
  }

  // ───────────────── UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.showBack,
        title: const Text('บัญชีครอบครัว'),
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  final popped = await Navigator.maybePop(context);
                  if (!popped) {
                    Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil('/home/profile', (r) => false);
                  }
                },
              )
            : null,
      ),
      body: _checking
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.diversity_3_outlined,
                            size: 56,
                            color: const Color.fromRGBO(
                              251,
                              192,
                              45,
                              1,
                            ), // << ,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'คุณยังไม่มีบัญชีครอบครัว',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'สร้างหรือเข้าร่วมครอบครัวเพื่อแชร์\nข้อมูลสต็อกวัตถุดิบกับสมาชิกครอบครัวของคุณ',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.grey[700]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Cards
                      _ActionCard(
                        icon: Icons.add_home,
                        title: 'สร้างครอบครัว',
                        subtitle: 'ตั้งค่าครอบครัวใหม่ คุณจะเป็นผู้ดูแล',
                        onTap: _createFamilyFlow,
                        variant: _ActionVariant.primary, // ให้เป็นการ์ดหลัก
                        bgColor: const Color.fromRGBO(
                          251,
                          192,
                          45,
                          1,
                        ), // << สีพื้นหลัง
                        fgColor: Colors.black, // << สีตัวหนังสือ/ไอคอน
                      ),

                      const SizedBox(height: 12),
                      _ActionCard(
                        icon: Icons.qr_code_scanner,
                        title: 'เข้าร่วมครอบครัว',
                        subtitle: 'สแกนจากผู้ดูแลหรือกรอกโค้ดเชิญ',
                        onTap: _joinByScan,
                        // variant: _ActionVariant.neutral (ค่าเริ่มต้น)
                      ),

                      // ปุ่มเสริม (ถ้าต้องการแยกเข้าร่วมด้วยโค้ด)
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _joinByCode,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black87, // สีตัวหนังสือ
                        ),
                        icon: Icon(
                          Icons.vpn_key,
                          color: const Color.fromRGBO(
                            251,
                            192,
                            45,
                            1,
                          ), // << สีไอคอน
                        ), // สีไอคอน
                        label: const Text('เข้าร่วมด้วยโค้ดเชิญ'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  void _showOk(String m) {
    if (!mounted) return;
    final sm = ScaffoldMessenger.of(context);
    sm.hideCurrentSnackBar();
    sm.showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.green));
  }

  void _showErr(String m) {
    if (!mounted) return;
    final sm = ScaffoldMessenger.of(context);
    sm.hideCurrentSnackBar();
    sm.showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));
  }
}

// ───────────────── UI pieces

// ignore: unused_element
class _HeaderCard extends StatelessWidget {
  const _HeaderCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'ยังไม่มีบัญชีครอบครัว',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'แชร์ข้อมูลสต็อกวัตถุดิบกับสมาชิกครอบครัวของคุณ',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).textTheme.bodyMedium?.color?.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_field
enum _ActionType { primary, normal }

// ignore: unused_element
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final _ActionType type;

  const _ActionButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    final isPrimary = type == _ActionType.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isPrimary ? Colors.indigo : Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isPrimary
                  ? Colors.white.withValues(alpha: .15)
                  : Colors.black.withValues(alpha: .06),
              child: Icon(
                icon,
                color: isPrimary ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isPrimary ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isPrimary ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isPrimary ? Colors.white : Colors.black54,
            ),
          ],
        ),
      ),
    );
  }
}

/// ทำให้ TextField โค้ดเชิญกลายเป็นตัวใหญ่ตลอด
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

enum _ActionVariant { primary, neutral }

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final _ActionVariant variant;
  final Color? bgColor; // สีพื้นหลังแบบกำหนดเอง (เฉพาะ primary)
  final Color? fgColor; // สีตัวอักษร/ไอคอนแบบกำหนดเอง (เฉพาะ primary)

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.variant = _ActionVariant.neutral,
    this.bgColor,
    this.fgColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPrimary = variant == _ActionVariant.primary;

    // ถ้าเป็น primary และมีสีส่งมา → ใช้สีที่ส่งมา
    final Color bg = isPrimary
        ? (bgColor ?? theme.colorScheme.primary)
        : Colors.white;
    final Color fg = isPrimary
        ? (fgColor ?? theme.colorScheme.onPrimary)
        : Colors.black87;

    final Color sub = isPrimary ? fg.withOpacity(0.85) : Colors.grey[700]!;
    final Color? border = isPrimary ? null : Colors.grey[300];
    final Color iconBg = isPrimary
        ? fg.withOpacity(0.08)
        : Colors.black.withOpacity(0.05);
    final Color chevron = isPrimary ? fg.withOpacity(0.9) : Colors.black54;

    return DecoratedBox(
      decoration: BoxDecoration(
        // เงาซ้อน 2 ชั้น: ชั้นใหญ่ฟุ้ง + ชั้นเล็กคม
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 25, // ฟุ้งมาก
            spreadRadius: 0,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12, // คมขึ้นใกล้ตัว
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: bg,
        elevation: isPrimary ? 10 : 6, // ดัน elevation เพิ่ม
        shadowColor: Colors.black.withOpacity(0.20), // เงาหนักขึ้น
        surfaceTintColor: Colors.transparent, // ปิดทินท์ M3 (ให้สี bg เดิมชัด)
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: border == null ? BorderSide.none : BorderSide(color: border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: fg),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(color: sub),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: chevron),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
