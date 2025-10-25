// lib/rawmaterial/pages/item_detail_page.dart
// หน้า “รายละเอียดวัตถุดิบ” แบบกระทัดรัด การ์ดกลางจอ + แถบหัวไอคอนล้วน
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:my_app/rawmaterial/constants/units.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';
import 'dart:math' as math;

/// ข้อมูลร่างสำหรับทำซ้ำ (แก้ไขได้ใน dialog)
class _DupDraft {
  _DupDraft({
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    this.expiry,
  });

  String name;
  String category;
  int quantity;
  String unit;
  DateTime? expiry;
}

class ItemDetailPage extends StatefulWidget {
  final ShoppingItem item;
  const ItemDetailPage({super.key, required this.item});

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late TextEditingController _nameCtrl;
  late TextEditingController _qtyCtrl;

  late String _category;
  late String _unit;
  DateTime? _expiry;

  bool _saving = false;
  bool _isPopping = false; // บล็อคทุก action ระหว่างกำลังปิด

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _nameCtrl = TextEditingController(text: i.name);
    _qtyCtrl = TextEditingController(text: i.quantity.toString());
    _category = Categories.normalize(i.category);
    _unit = Units.safe(i.unit);
    _expiry = i.expiryDate;
  }

  @override
  void dispose() {
    // ตัดโฟกัสก่อน dispose controller
    FocusManager.instance.primaryFocus?.unfocus();
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  // ---------- Safe helpers ----------
  void _safePop([dynamic result]) {
    if (_isPopping) return;
    _isPopping = true;
    FocusManager.instance.primaryFocus?.unfocus();
    final nav = Navigator.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (nav.mounted && nav.canPop()) {
        nav.pop(result);
      }
    });
  }

  void _safePopUsing(BuildContext ctx, [dynamic result]) {
    if (_isPopping) return;
    _isPopping = true;
    FocusManager.instance.primaryFocus?.unfocus();
    final nav = Navigator.of(ctx);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (nav.mounted && nav.canPop()) {
        nav.pop(result);
      }
    });
  }

  void _showSnack(String message) {
    final m = ScaffoldMessenger.maybeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      m?.showSnackBar(SnackBar(content: Text(message)));
    });
  }
  // -----------------------------------

  DocumentReference<Map<String, dynamic>>? _itemRef() {
    if (widget.item.reference != null) return widget.item.reference;
    final ownerId = widget.item.ownerId.isNotEmpty
        ? widget.item.ownerId
        : _auth.currentUser?.uid ?? '';
    if (ownerId.isEmpty) return null;
    return _firestore
        .collection('users')
        .doc(ownerId)
        .collection('raw_materials')
        .doc(widget.item.id);
  }

  String _formatThaiDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year2 = (d.year + 543).toString().substring(2);
    return '$day/$month/$year2';
  }

  Future<void> _pickDate() async {
    if (_saving || _isPopping) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: 'เลือกวันหมดอายุ',
    );
    if (!mounted || _isPopping) return;
    if (picked != null) setState(() => _expiry = picked);
  }

  Future<void> _save() async {
    if (_saving || _isPopping) return;
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบใหม่อีกครั้ง')),
      );
      return;
    }

    final newName = _nameCtrl.text.trim();
    final newQty = int.tryParse(_qtyCtrl.text.trim());

    if (newName.isEmpty || newQty == null || newQty <= 0) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่อและจำนวนให้ถูกต้อง')),
      );
      return;
    }

    final docRef = _itemRef();
    if (docRef == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('ไม่พบข้อมูลรายการนี้ในคลัง')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await docRef.update({
        'name': newName,
        'category': _category,
        'quantity': newQty,
        'unit': _unit,
        'expiry_date': _expiry != null ? Timestamp.fromDate(_expiry!) : null,
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      _safePop(true);
    } catch (e, st) {
      debugPrint('Save error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (_saving || _isPopping) return;
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบใหม่อีกครั้ง')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ลบวัตถุดิบ'),
        content: Text('ต้องการลบ "${widget.item.name}" ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (!mounted || _isPopping) return;
    if (ok != true) return;

    try {
      final docRef = _itemRef();
      if (docRef == null) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('ไม่พบข้อมูลรายการนี้ในคลัง')),
        );
        return;
      }
      await docRef.delete();
      if (!mounted) return;
      _safePop(true);
    } catch (e, st) {
      debugPrint('Delete error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('ลบไม่สำเร็จ: $e')));
    }
  }

  // เปิด dialog แก้ไขรายละเอียดก่อน "ทำซ้ำ" — ป้องกัน disposed controller + overflow
  Future<_DupDraft?> _openDuplicateDialog() async {
    // controller เฉพาะ dialog
    final nameCtrl = TextEditingController(text: _nameCtrl.text.trim());
    final qtyCtrl = TextEditingController(text: _qtyCtrl.text.trim());
    String category = _category;
    String unit = _unit;
    DateTime? expiry = _expiry;

    String? nameError;
    String? qtyError;
    bool closing =
        false; // ✅ เมื่อ true จะไม่วาด TextField อีก (กัน re-build ท้าย ๆ)

    String fmtThai(DateTime d) {
      final day = d.day.toString().padLeft(2, '0');
      final month = d.month.toString().padLeft(2, '0');
      final year2 = (d.year + 543).toString().substring(2);
      return '$day/$month/$year2';
    }

    Future<void> pickDate(BuildContext dialogCtx) async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: dialogCtx,
        initialDate: expiry ?? now,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 5),
        helpText: 'เลือกวันหมดอายุ',
      );
      if (picked != null) expiry = picked;
    }

    final result = await showDialog<_DupDraft>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) {
        final m = MediaQuery.of(dialogCtx);
        final kb = m.viewInsets.bottom;
        final avail = m.size.height - kb - 32; // เว้นระยะบนล่างรวม ๆ
        final maxH = math.min(avail * 0.96, 560.0); // ✅ ลอจิกเดียวกัน

        return AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: m.viewInsets.bottom + 16,
            top: 16,
            left: 16,
            right: 16,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: maxH, // ✅ เดิมเคยใช้ m.size.height * 0.9
              ),
              child: Material(
                color: Colors.white,
                elevation: 24,
                shadowColor: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: StatefulBuilder(
                  builder: (ctx, setState) {
                    void doCloseWith([_DupDraft? draft]) {
                      // ปิดคีย์บอร์ด + ตั้ง closing ให้ UI ไม่วาด TextField อีก
                      FocusScope.of(dialogCtx).unfocus();
                      setState(() => closing = true);
                      // pop หลังเฟรม
                      final nav = Navigator.of(dialogCtx);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (nav.mounted && nav.canPop()) {
                          nav.pop(draft);
                        }
                      });
                    }

                    void validateAndSubmit() {
                      final name = nameCtrl.text.trim();
                      final qty = int.tryParse(qtyCtrl.text.trim());
                      String? ne;
                      String? qe;

                      if (name.isEmpty) ne = 'กรุณากรอกชื่อวัตถุดิบ';
                      if (qty == null || qty <= 0) qe = 'จำนวนไม่ถูกต้อง';

                      setState(() {
                        nameError = ne;
                        qtyError = qe;
                      });

                      if (ne != null || qe != null) return;

                      final normalizedUnit = Units.safe(unit);
                      final normalizedCat = Categories.normalize(category);

                      doCloseWith(
                        _DupDraft(
                          name: name,
                          category: normalizedCat,
                          quantity: qty!,
                          unit: normalizedUnit,
                          expiry: expiry,
                        ),
                      );
                    }

                    if (closing) {
                      // ลดโอกาสใช้ controller หลัง dispose โดยไม่วาดฟอร์มอีก
                      return const SizedBox.shrink();
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                          child: Row(
                            children: [
                              const Icon(Icons.copy_all_rounded),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'ทำซ้ำวัตถุดิบ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'ยกเลิก',
                                icon: const Icon(Icons.close),
                                onPressed: () => doCloseWith(null),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),

                        // เนื้อหาเลื่อนขึ้นลงได้
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            child: Column(
                              children: [
                                TextField(
                                  controller: nameCtrl,
                                  decoration: _decoration().copyWith(
                                    labelText: 'ชื่อวัตถุดิบ',
                                    prefixIcon: const Icon(
                                      Icons.fastfood_outlined,
                                    ),
                                    errorText: nameError,
                                  ),
                                  textInputAction: TextInputAction.next,
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                  value: category,
                                  isExpanded: true,
                                  menuMaxHeight: 320,
                                  items: Categories.list.map((c) {
                                    final icon = Categories.iconFor(c);
                                    final color = Categories.colorFor(c);
                                    return DropdownMenuItem(
                                      value: c,
                                      child: Row(
                                        children: [
                                          Icon(icon, size: 18, color: color),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              c,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),

                                  selectedItemBuilder: (context) {
                                    return Categories.list.map((c) {
                                      final icon = Categories.iconFor(c);
                                      final color = Categories.colorFor(c);
                                      return Row(
                                        children: [
                                          Icon(icon, size: 18, color: color),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              c,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList();
                                  },

                                  onChanged: (v) => setState(
                                    () => category = Categories.normalize(
                                      v ?? category,
                                    ),
                                  ),

                                  decoration: _decoration().copyWith(
                                    labelText: 'หมวดหมู่',
                                    // prefixIcon ตัดออกได้เหมือนกัน
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: qtyCtrl,
                                        textAlign: TextAlign.center,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: _decoration(isDense: true)
                                            .copyWith(
                                              labelText: 'จำนวน',
                                              errorText: qtyError,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: unit,
                                        isExpanded: true,
                                        items: Units.all
                                            .map(
                                              (u) => DropdownMenuItem(
                                                value: u,
                                                child: Text(u),
                                              ),
                                            )
                                            .toList(),
                                        selectedItemBuilder: (_) => Units.all
                                            .map(
                                              (u) => Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  u,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) => setState(
                                          () => unit = Units.safe(v ?? unit),
                                        ),
                                        decoration: _decoration().copyWith(
                                          labelText: 'หน่วย',
                                          prefixIcon: const Icon(
                                            Icons.straighten_outlined,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // วันหมดอายุ
                                InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () async {
                                    await pickDate(dialogCtx);
                                    setState(() {});
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey[300]!,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.event_outlined,
                                          color: Colors.grey[700],
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            expiry == null
                                                ? 'แตะเพื่อเลือกวันที่'
                                                : fmtThai(expiry!),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (expiry != null)
                                          InkWell(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            onTap: () =>
                                                setState(() => expiry = null),
                                            child: const Padding(
                                              padding: EdgeInsets.all(6),
                                              child: Icon(
                                                Icons.clear,
                                                size: 18,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => doCloseWith(null),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors
                                        .black, // ✅ ตัวหนังสือ + ripple เป็นสีดำ
                                  ),

                                  child: const Text('ยกเลิก'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: validateAndSubmit,
                                  icon: const Icon(
                                    Icons.check_circle,
                                    color: Color.fromARGB(255, 0, 0, 0),
                                  ),
                                  label: const Text('ยืนยันทำซ้ำ'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        Colors.yellow[600], // ✅ สีพื้นหลังเขียว
                                    foregroundColor: const Color.fromARGB(
                                      255,
                                      0,
                                      0,
                                      0,
                                    ), // ✅ สีข้อความ/ไอคอนขาว
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );

    // เลื่อน dispose controller ของ dialog ไปหลังเฟรมที่ dialog ปิด
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameCtrl.dispose();
      qtyCtrl.dispose();
    });

    return result;
  }

  Future<void> _duplicate() async {
    if (_saving || _isPopping) return;

    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบใหม่อีกครั้ง')),
      );
      return;
    }

    final draft = await _openDuplicateDialog();
    if (draft == null || !mounted || _isPopping) return;

    final ctx = context;

    try {
      if (!mounted || _isPopping) return;
      setState(() => _saving = true);

      String? familyId = widget.item.familyId;
      if (familyId == null || familyId.isEmpty) {
        final userDoc = await _firestore
            .collection('users')
            .doc(user.uid)
            .get();
        final rawUserData = userDoc.data();
        final fetchedFamilyId =
            ((rawUserData?['familyId'] ?? rawUserData?['family_id']) as String?)
                ?.trim();
        if (fetchedFamilyId != null && fetchedFamilyId.isNotEmpty) {
          familyId = fetchedFamilyId;
        }
      }

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .add({
            'name': draft.name.trim(),
            'category': draft.category,
            'quantity': draft.quantity,
            'unit': draft.unit,
            'expiry_date': draft.expiry != null
                ? Timestamp.fromDate(draft.expiry!)
                : null,
            'imageUrl': widget.item.imageUrl,
            'created_at': FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
            'user_id': user.uid,
            'ownerId': user.uid,
            if (familyId != null) 'familyId': familyId,
          });

      if (!mounted) return;
      _safePopUsing(ctx, true);
      _showSnack('ทำซ้ำแล้ว');
    } catch (e, st) {
      debugPrint('Duplicate error: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        ctx,
      )?.showSnackBar(SnackBar(content: Text('ทำซ้ำไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ข้อความสรุป “จะหมดอายุอีกกี่วัน” + สีสถานะ
  (String, Color) _expiryCountdown() {
    if (_expiry == null) return ('ยังไม่ระบุวันหมดอายุ', Colors.blueGrey);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(_expiry!.year, _expiry!.month, _expiry!.day);
    final diff = exp.difference(today).inDays;

    if (diff < 0) return ('หมดอายุแล้ว ${diff.abs()} วัน', Colors.red);
    if (diff == 0) return ('หมดอายุวันนี้', Colors.orange);
    if (diff <= 3) return ('จะหมดอายุในอีก $diff วัน', Colors.orange);
    return ('จะหมดอายุในอีก $diff วัน', Colors.green);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    // ✅ ความสูงจอจริงที่เหลืออยู่หลังคีย์บอร์ด
    final kb = media.viewInsets.bottom;
    final verticalMargin = 24.0; // top 12 + bottom 12 จาก AnimatedPadding
    final availableHeight = media.size.height - kb - verticalMargin;

    // ✅ ให้การ์ดสูงสุดไม่เกิน 92% ของพื้นที่ที่เหลือ หรือ 560 (แล้วแต่ต่ำกว่า)
    final cardMaxHeight = math.min(availableHeight * 0.92, 560.0);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black.withValues(alpha: 0.45),
      body: SafeArea(
        child: Center(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(
              top: 12,
              bottom: 12 + kb, // ✅ ขยับทั้งใบขึ้นตามคีย์บอร์ด
              left: 12,
              right: 12,
            ),
            child: FractionallySizedBox(
              widthFactor: 0.94,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: cardMaxHeight, // ✅ ใช้ความสูงที่คำนวณแล้ว
                ),
                child: Material(
                  color: Colors.white,
                  elevation: 16,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _IconHeaderBar(
                        onClose: _safePop,
                        onDuplicate: _saving ? null : _duplicate,
                        onDelete: _saving ? null : _delete,
                        onSave: _saving ? null : _save,
                      ),
                      if (_saving) const LinearProgressIndicator(minHeight: 2),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SectionCard(
                                title: 'ข้อมูลพื้นฐาน',
                                children: [
                                  TextField(
                                    controller: _nameCtrl,
                                    textInputAction: TextInputAction.next,
                                    decoration: _decoration().copyWith(
                                      labelText: 'ชื่อวัตถุดิบ',
                                      prefixIcon: const Icon(
                                        Icons.fastfood_outlined,
                                      ),
                                      hintText: 'เช่น อกไก่, ไข่ไก่, แอปเปิล',
                                    ),
                                  ),
                                  DropdownButtonFormField<String>(
                                    value: _category,
                                    isExpanded: true,
                                    menuMaxHeight: 320,
                                    items: Categories.list.map((c) {
                                      final icon = Categories.iconFor(c);
                                      final color = Categories.colorFor(c);
                                      return DropdownMenuItem(
                                        value: c,
                                        child: Row(
                                          children: [
                                            Icon(icon, size: 18, color: color),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                c,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),

                                    // แสดงค่าเลือกปัจจุบันพร้อมไอคอนใน “ช่อง”
                                    selectedItemBuilder: (context) {
                                      return Categories.list.map((c) {
                                        final icon = Categories.iconFor(c);
                                        final color = Categories.colorFor(c);
                                        return Row(
                                          children: [
                                            Icon(icon, size: 18, color: color),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                c,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        );
                                      }).toList();
                                    },

                                    onChanged: (v) {
                                      if (v == null || _isPopping) return;
                                      setState(
                                        () =>
                                            _category = Categories.normalize(v),
                                      );
                                    },

                                    decoration: _decoration().copyWith(
                                      labelText: 'หมวดหมู่',
                                      // prefixIcon ไม่จำเป็นแล้วเพราะเราแสดงไอคอนในค่าเลือกอยู่แล้ว
                                      // ถ้ายังอยากคงไว้ก็ได้ แต่จะเห็นไอคอนสองจุด
                                    ),
                                  ),
                                ],
                              ),
                              _SectionCard(
                                title: 'จำนวนและหน่วย',
                                children: [
                                  // บรรทัดจำนวน (เต็มบรรทัด)
                                  Row(
                                    children: [
                                      _qtyButton(
                                        icon: Icons.remove_circle_outline,
                                        color: Colors.red,
                                        onTap: () {
                                          if (_isPopping || _saving) return;
                                          final n =
                                              int.tryParse(
                                                _qtyCtrl.text.trim(),
                                              ) ??
                                              1;
                                          if (n > 1) {
                                            setState(
                                              () => _qtyCtrl.text = (n - 1)
                                                  .toString(),
                                            );
                                          }
                                        },
                                      ),
                                      Expanded(
                                        child: TextField(
                                          controller: _qtyCtrl,
                                          textAlign: TextAlign.center,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          decoration: _decoration(isDense: true)
                                              .copyWith(
                                                labelText: 'จำนวน',
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12,
                                                    ),
                                              ),
                                        ),
                                      ),
                                      _qtyButton(
                                        icon: Icons.add_circle_outline,
                                        color: Colors.green,
                                        onTap: () {
                                          if (_isPopping || _saving) return;
                                          final n =
                                              int.tryParse(
                                                _qtyCtrl.text.trim(),
                                              ) ??
                                              0;
                                          setState(
                                            () => _qtyCtrl.text = (n + 1)
                                                .toString(),
                                          );
                                        },
                                      ),
                                    ],
                                  ),

                                  // บรรทัดหน่วย (เต็มความกว้าง)
                                  DropdownButtonFormField<String>(
                                    value: _unit,
                                    isExpanded: true,
                                    items: Units.all
                                        .map(
                                          (u) => DropdownMenuItem(
                                            value: u,
                                            child: Text(u),
                                          ),
                                        )
                                        .toList(),
                                    selectedItemBuilder: (_) => Units.all
                                        .map(
                                          (u) => Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              u,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (v) {
                                      if (v == null || _isPopping) return;
                                      setState(() => _unit = Units.safe(v));
                                    },
                                    menuMaxHeight: 320,
                                    decoration: _decoration().copyWith(
                                      labelText: 'หน่วย',
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                      prefixIcon: const Icon(
                                        Icons.straighten_outlined,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              _SectionCard(
                                title: 'วันหมดอายุ',
                                children: [
                                  InkWell(
                                    onTap: _pickDate,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey[300]!,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.event_outlined,
                                            color: Colors.grey[700],
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _expiry == null
                                                  ? 'แตะเพื่อเลือกวันที่'
                                                  : _formatThaiDate(_expiry!),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (_expiry != null)
                                            InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              onTap: () {
                                                if (_isPopping || _saving) {
                                                  return;
                                                }
                                                setState(() => _expiry = null);
                                              },
                                              child: const Padding(
                                                padding: EdgeInsets.all(6),
                                                child: Icon(
                                                  Icons.clear,
                                                  size: 18,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // ป้าย “หมดอายุอีกกี่วัน”
                                  Builder(
                                    builder: (_) {
                                      final info = _expiryCountdown();
                                      return Container(
                                        margin: const EdgeInsets.only(top: 10),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: info.$2.withValues(
                                            alpha: 0.10,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: info.$2.withValues(
                                              alpha: 0.25,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Icon(
                                              Icons.schedule_outlined,
                                              size: 16,
                                              color: info.$2,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                info.$1,
                                                softWrap: true,
                                                style: TextStyle(
                                                  color: info.$2,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------- UI helpers -------
  InputDecoration _decoration({bool isDense = false}) => InputDecoration(
    isDense: isDense,
    filled: true,
    fillColor: Colors.grey[50],
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey[700]!),
    ),
  );

  Widget _qtyButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: color.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: color),
          ),
        ),
      ),
    );
  }
}

class _IconHeaderBar extends StatelessWidget {
  const _IconHeaderBar({
    required this.onClose,
    required this.onDuplicate,
    required this.onDelete,
    required this.onSave,
  });

  final VoidCallback onClose;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey[200]!, width: 1)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'ปิด',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'ทำซ้ำ',
            onPressed: onDuplicate,
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: 'ลบ',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, color: Colors.red),
          ),
          IconButton(
            tooltip: 'บันทึก',
            onPressed: onSave,
            icon: const Icon(Icons.check_circle, color: Colors.green),
          ),
        ],
      ),
    );
  }
}

/// การ์ดส่วน (Section) มาตรฐาน แบบกระทัดรัด
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ..._gap(children, 10),
          ],
        ),
      ),
    );
  }

  List<Widget> _gap(List<Widget> ch, double gap) {
    final out = <Widget>[];
    for (var i = 0; i < ch.length; i++) {
      out.add(ch[i]);
      if (i != ch.length - 1) out.add(SizedBox(height: gap));
    }
    return out;
  }
}
