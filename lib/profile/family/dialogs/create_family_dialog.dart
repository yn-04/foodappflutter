// lib/profile/family/dialogs/create_family_dialog.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/family_service.dart'; // ← ใช้ FamilyService เพื่อสร้างอย่างถูกต้อง

/// Dialog สร้างครอบครัวใหม่
/// - ผู้สร้างจะถูกตั้งเป็น admin (คนเดียว)
/// - users/{uid}.familyId จะถูกผูกกับครอบครัวที่สร้าง
/// - เพิ่มเอกสารตัวเองเข้าใน family_members (role=admin)
/// - อัปเดต family_stats ให้ด้วย (ผ่าน FamilyService)
class CreateFamilyDialog {
  /// แสดง dialog
  /// [onCreated] จะถูกเรียกเมื่อสร้างสำเร็จและส่งกลับ familyId
  static Future<void> show({
    required BuildContext context,
    void Function(String familyId)? onCreated,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateFamilyDialogBody(),
    ).then((fid) {
      if (fid is String && onCreated != null) {
        onCreated(fid);
      }
    });
  }
}

class _CreateFamilyDialogBody extends StatefulWidget {
  const _CreateFamilyDialogBody();

  @override
  State<_CreateFamilyDialogBody> createState() =>
      _CreateFamilyDialogBodyState();
}

class _CreateFamilyDialogBodyState extends State<_CreateFamilyDialogBody> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // ใส่ชื่อเริ่มต้นจากโปรไฟล์ผู้ใช้ (เพื่อความเป็นมิตร)
    final u = FirebaseAuth.instance.currentUser;
    final display = (u?.displayName?.trim().isNotEmpty == true)
        ? u!.displayName!.trim()
        : null;
    _nameCtrl.text = display != null ? 'ครอบครัวของ$display' : 'ครอบครัวของฉัน';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'กรุณาเข้าสู่ระบบก่อน');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      // ใน _create() ของ create_family_dialog.dart
      final u = FirebaseAuth.instance.currentUser!;
      final familyName = _nameCtrl.text.trim();
      final userDisplay =
          (u.displayName != null && u.displayName!.trim().isNotEmpty)
          ? u.displayName!.trim()
          : (u.email ?? 'ไม่ระบุ');

      final fid = await FamilyService.createFamilyForUser(
        uid: u.uid,
        displayName: userDisplay, // ✅ ส่ง displayName ของ user
        email: u.email,
        photoUrl: u.photoURL,
        familyName: familyName, // ✅ ชื่อครอบครัวจากฟอร์ม
      );

      Navigator.of(context).pop(fid);
    } on FirebaseException catch (e) {
      setState(() {
        _error = e.message ?? e.code;
        _submitting = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_submitting;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // หัวข้อ
              const Text(
                'สร้างครอบครัวใหม่',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'ผู้สร้างจะเป็นผู้ดูแล (admin) อัตโนมัติ\nคุณสามารถเชิญสมาชิกคนอื่นเข้าร่วมภายหลังได้',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700]),
              ),
              const SizedBox(height: 16),

              // ฟอร์ม
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อครอบครัว',
                    hintText: 'เช่น ครอบครัวสมิธ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'กรุณากรอกชื่อครอบครัว';
                    if (t.length > 50) return 'ชื่อยาวเกินไป (จำกัด 50 อักษร)';
                    return null;
                  },
                  onFieldSubmitted: (_) => _create(),
                ),
              ),

              const SizedBox(height: 12),

              // แถบ error (ถ้ามี)
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // ปุ่ม
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: canSubmit
                          ? () => Navigator.of(context).maybePop()
                          : null,
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: canSubmit ? _create : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('สร้างครอบครัว'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
