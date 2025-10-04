// lib/rawmaterial/screens/shopping_list_screen.dart — รายการวัตถุดิบ: ค้นหา/กรอง/หมวด/สแกน/เพิ่ม (กรองฝั่งแอปลดปัญหา index)
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:my_app/rawmaterial/addraw.dart';
import 'package:my_app/rawmaterial/barcode_scanner.dart'; // ใช้ WorkingBarcodeScanner ภายในไฟล์นี้

import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';

import 'package:my_app/rawmaterial/pages/item_detail_page.dart';
import 'package:my_app/rawmaterial/widgets/item_group_detail_card.dart';
import 'package:my_app/rawmaterial/widgets/quick_use_sheet.dart';
import 'package:my_app/rawmaterial/utils/unit_converter.dart';

import 'package:my_app/rawmaterial/widgets/shopping_item_card.dart';
import 'package:my_app/rawmaterial/widgets/grouped_item_card.dart';

// ใช้ค่านี้เป็น single source of truth สำหรับป้าย "ทั้งหมด"
const String _ALL = Categories.allLabel;

class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({Key? key}) : super(key: key);

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _searchCtrl = TextEditingController();
  final _customDaysCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();

  // debounce
  Timer? _searchDebounce;

  String searchQuery = ''; // เก็บเป็น lower-case เสมอ
  String selectedCategory = _ALL;

  String selectedExpiryFilter = 'ทั้งหมด';
  int? customDays;

  List<String> availableCategories = [_ALL];

  /// ตัวเลือกวันหมดอายุที่แสดงในเมนู
  final List<String> _expiryOptions = const [
    'ทั้งหมด',
    '7 วัน',
    '14 วัน',
    '30 วัน',
    'กำหนดเอง…',
  ];

  User? get currentUser => _auth.currentUser;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChange);
    _loadAvailableCategories();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _customDaysCtrl.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ===== Helpers: วันหมดอายุ =====

  /// แปลง label เช่น "7 วัน" → 7, ถ้าไม่ใช่ preset คืน null
  int? _parseDaysFromLabel(String label) {
    final m = RegExp(r'^(\d+)\s*วัน$').firstMatch(label.trim());
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  /// คืนจำนวนวันที่จะใช้กรองจริง:
  /// - ถ้าเลือก preset → คืนค่าตาม preset
  /// - ถ้าเลือก "กำหนดเอง" → คืน customDays
  /// - ถ้า "ทั้งหมด" → คืน null
  int? _effectiveDays() {
    final preset = _parseDaysFromLabel(selectedExpiryFilter);
    if (preset != null) return preset;
    if (selectedExpiryFilter == 'กำหนดเอง') return customDays;
    return null;
  }

  DateTime _stripDate(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _loadAvailableCategories() async {
    if (currentUser == null) return;
    try {
      final qs = await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .collection('raw_materials')
          .get();

      final activeItems = _activeItemsFromDocs(qs.docs);
      _scheduleAvailableCategoriesUpdate(activeItems, immediate: true);
    } catch (e) {
      debugPrint('Load categories error: $e');
    }
  }

  List<ShoppingItem> _activeItemsFromDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final today = _stripDate(DateTime.now());
    return docs
        .map((d) => ShoppingItem.fromMap(d.data(), d.id))
        .where((item) => item.quantity > 0)
        .where((item) {
          final expiry = item.expiryDate;
          if (expiry == null) return true;
          return !_stripDate(expiry).isBefore(today);
        })
        .toList(growable: false);
  }

  void _scheduleAvailableCategoriesUpdate(
    List<ShoppingItem> items, {
    bool immediate = false,
  }) {
    final categories =
        items
            .map((it) => it.category.trim())
            .where((cat) => cat.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.compareTo(b));
    final next = <String>[_ALL, ...categories];

    if (listEquals(next, availableCategories)) return;

    void apply() {
      if (!mounted) return;
      setState(() {
        availableCategories = next;
        if (!availableCategories.contains(selectedCategory)) {
          selectedCategory = _ALL;
        }
      });
    }

    if (immediate) {
      apply();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    }
  }

  void _clearSearch() {
    final hadText = _searchCtrl.text.isNotEmpty;
    final hadQuery = searchQuery.isNotEmpty;
    if (!hadText && !hadQuery) return;

    _searchDebounce?.cancel();
    if (hadText) {
      _searchCtrl.clear();
    }
    if (hadQuery && mounted) {
      setState(() => searchQuery = '');
    }
  }

  void _onSearchFocusChange() {
    if (!_searchFocusNode.hasFocus) {
      _clearSearch();
    }
  }

  void _handleOutsideTap() {
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    } else {
      _clearSearch();
    }
  }

  // ===== Quick use =====
  void _showQuickUseSheet(ShoppingItem item) {
    showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) {
        return QuickUseSheet(
          itemName: item.name,
          unit: item.unit,
          currentQty: item.quantity,
          onSave: (useQty, unit, note) async {
            if (useQty <= 0) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('กรุณาใส่จำนวนที่ใช้ให้ถูกต้อง')),
              );
              return;
            }

            final conversion = UnitConverter.applyUsage(
              currentQty: item.quantity,
              currentUnit: item.unit,
              useQty: useQty,
              useUnit: unit,
            );
            if (!conversion.isValid) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('จำนวนที่ใช้ต้องอยู่ระหว่าง 1 ถึงจำนวนคงเหลือ'),
                ),
              );
              return;
            }

            try {
              final user = _auth.currentUser;
              if (user == null) return;

              final docRef = _firestore
                  .collection('users')
                  .doc(user.uid)
                  .collection('raw_materials')
                  .doc(item.id);

              await docRef.collection('usage_logs').add({
                'quantity': useQty,
                'unit': unit,
                'note': note,
                'used_at': FieldValue.serverTimestamp(),
              });

              await docRef.update({
                'quantity': conversion.remainingQuantity,
                'unit': conversion.remainingUnit,
                'updated_at': FieldValue.serverTimestamp(),
              });

              if (!mounted) return;
              Future.microtask(() {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'บันทึกการใช้แล้ว - เหลือ ${conversion.remainingQuantity} ${conversion.remainingUnit}',
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              });

              try {
                await _loadAvailableCategories();
              } catch (err) {
                debugPrint('Refresh categories failed: $err');
              }
              if (!mounted) return;
              setState(() {}); // รีเฟรชลิสต์
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
            }
          },
        );
      },
    );
  }

  // ===== Custom days dialog (กำหนดเอง) =====
  Future<bool?> _showCustomDaysDialog() async {
    _customDaysCtrl.text = (customDays != null && customDays! > 0)
        ? '$customDays'
        : '';

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ... หัวไดอะล็อกคงเดิม ...
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: TextField(
                  controller: _customDaysCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  decoration: InputDecoration(
                    hintText: 'เช่น 5',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 24),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 20,
                    ),

                    // ✅ ใช้ suffixText แทน suffixIcon เพื่อไม่ทับตัวเลขที่พิมพ์
                    suffixText: 'วัน',
                    suffixStyle: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  autofocus: true,
                  onChanged: (v) {
                    final n = int.tryParse(v.trim());
                    setState(() {
                      customDays = (n != null && n > 0 && n <= 3650) ? n : null;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [1, 3, 7, 14, 30].map((d) {
                  return InkWell(
                    onTap: () {
                      _customDaysCtrl.text = d.toString();
                      setState(() {
                        customDays = d; // อัปเดตเรียลไทม์
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.yellow[300]!.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.yellow[400]!),
                      ),
                      child: Text(
                        '$d วัน',
                        style: TextStyle(
                          color: Colors.yellow[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () =>
                          Navigator.pop(context, false), // ← false = ยกเลิก
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.grey[100],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'ยกเลิก',
                        style: TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final days = int.tryParse(_customDaysCtrl.text.trim());
                        if (days != null && days > 0 && days <= 3650) {
                          setState(() {
                            customDays = days; // ตอกย้ำค่า
                            // selectedExpiryFilter เป็น 'กำหนดเอง' อยู่แล้ว
                          });
                          Navigator.pop(context, true); // ← true = ตกลง
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('กรองวัตถุดิบตามวันที่กำหนดเองแล้ว'),
                                ],
                              ),
                              backgroundColor: Colors.green[600],
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              margin: const EdgeInsets.all(16),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Row(
                                children: [
                                  Icon(Icons.error, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('กรุณาใส่จำนวนวันที่ถูกต้อง'),
                                ],
                              ),
                              backgroundColor: Colors.red[600],
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              margin: const EdgeInsets.all(16),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.yellow[300],
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_rounded),
                          SizedBox(width: 8),
                          Text(
                            'ยืนยัน',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
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

  // ===== Navigation =====
  void _goAddRaw() {
    if (currentUser == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddRawMaterialPage()),
    ).then((_) {
      _loadAvailableCategories();
      if (mounted) setState(() {});
    });
  }

  void _goScan() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WorkingBarcodeScanner()),
    );

    if (result is Map<String, dynamic>) {
      final String? scannedBarcode = result['scannedBarcode'] as String?;
      final Map<String, dynamic>? scannedProductData =
          (result['scannedProductData'] as Map?)?.cast<String, dynamic>();

      // ignore: use_build_context_synchronously
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddRawMaterialPage(
            scannedBarcode: scannedBarcode,
            scannedProductData: scannedProductData,
          ),
        ),
      ).then((_) {
        _loadAvailableCategories();
        if (mounted) setState(() {});
      });
    }
  }

  // ===== Streams (ทำ filter ที่ server) =====
  Stream<QuerySnapshot<Map<String, dynamic>>> _streamItems() {
    if (currentUser == null) return const Stream.empty();
    // ดึงทั้งหมด แล้วกรอง/เรียงที่ฝั่งแอป แก้ปัญหากดเลือกหมวดหมู่แล้วว่างจาก composite index
    return _firestore
        .collection('users')
        .doc(currentUser!.uid)
        .collection('raw_materials')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamCount() {
    if (currentUser == null) return const Stream.empty();
    return _firestore
        .collection('users')
        .doc(currentUser!.uid)
        .collection('raw_materials')
        .snapshots();
  }

  // ===== Mutations =====
  Future<void> _deleteGroupItems(List<ShoppingItem> items) async {
    if (currentUser == null || items.isEmpty) return;
    try {
      // Firestore จำกัด ~500 ops ต่อ batch → แบ่งก้อนกันพลาด
      const chunkSize = 450;
      for (var i = 0; i < items.length; i += chunkSize) {
        final chunk = items.sublist(i, (i + chunkSize).clamp(0, items.length));
        var batch = _firestore.batch();
        for (final it in chunk) {
          final ref = _firestore
              .collection('users')
              .doc(currentUser!.uid)
              .collection('raw_materials')
              .doc(it.id);
          batch.delete(ref);
        }
        await batch.commit();
      }

      await _loadAvailableCategories();
      if (mounted) {
        setState(() {});
        final removed = items.length;
        final preview = items.take(3).map((e) => e.name).join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              removed <= 3
                  ? 'ลบกลุ่มแล้ว: $preview'
                  : 'ลบกลุ่มแล้ว $removed รายการ (เช่น $preview...)',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ลบกลุ่มไม่สำเร็จ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteItem(String id) async {
    if (currentUser == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .collection('raw_materials')
          .doc(id)
          .delete();
      await _loadAvailableCategories();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('เกิดข้อผิดพลาดในการลบรายการ'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ===== Build =====
  @override
  Widget build(BuildContext context) {
    final themeGrey = Colors.grey[100];

    return Scaffold(
      backgroundColor: themeGrey,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _handleOutsideTap(),
        child: NestedScrollView(
          floatHeaderSlivers: true,
          headerSliverBuilder: (context, innerScrolled) => [
            // 1) AppBar + แถวค้นหา/กรอง (ตรึงไว้ตลอด)
            SliverAppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              elevation: 0,
              pinned: true,
              floating: false,
              snap: false,
              title: Row(
                children: [
                  const Text(
                    'วัตถุดิบ',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _streamCount(),
                    builder: (_, s) {
                      final docs = s.data?.docs;
                      if (docs == null) {
                        return Text(
                          '0 ชิ้น',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                        );
                      }

                      final activeItems = _activeItemsFromDocs(docs);
                      _scheduleAvailableCategoriesUpdate(activeItems);
                      final cnt = activeItems.length;

                      return Text(
                        '$cnt ชิ้น',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      );
                    },
                  ),
                ],
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(72), // เฉพาะค้นหา/กรอง
                child: Column(
                  children: [
                    // ===== ค้นหา + ตัวกรองหมดอายุ =====
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              focusNode: _searchFocusNode,
                              keyboardType: TextInputType.text,
                              textInputAction: TextInputAction.search,
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'ค้นหาวัตถุดิบ',
                                hintStyle: TextStyle(color: Colors.grey[400]),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  color: Colors.grey[400],
                                  size: 20,
                                ),
                                suffixIcon: searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(
                                          Icons.clear,
                                          color: Colors.grey[400],
                                          size: 20,
                                        ),
                                        onPressed: _clearSearch,
                                      )
                                    : null,
                                filled: true,
                                fillColor: Colors.grey[50],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide(
                                    color: Colors.grey[300]!,
                                    width: 1.3,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide(
                                    color: Colors.grey[300]!,
                                    width: 1.3,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide(
                                    color: Colors.grey[400]!,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              onChanged: (v) {
                                _searchDebounce?.cancel();
                                _searchDebounce = Timer(
                                  const Duration(milliseconds: 250),
                                  () {
                                    if (!mounted) return;
                                    setState(
                                      () =>
                                          searchQuery = v.trim().toLowerCase(),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          // ปุ่มตัวกรองวันหมดอายุ (ทึบ ไม่โปร่ง)
                          Material(
                            color: selectedExpiryFilter == 'ทั้งหมด'
                                ? Colors.grey[100]!
                                : Colors.yellow[300]!,
                            surfaceTintColor: Colors.transparent,
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: selectedExpiryFilter == 'ทั้งหมด'
                                    ? Colors.grey[400]!
                                    : Colors.yellow[600]!,
                                width: 1.5,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: PopupMenuButton<String>(
                              color: Colors.white,
                              tooltip:
                                  'กรองตามวันหมดอายุ (จะแสดงเรียงใกล้หมดอายุก่อน)',
                              offset: const Offset(0, 40),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              itemBuilder: (_) => _expiryOptions.map((opt) {
                                final isCustomTrigger = opt == 'กำหนดเอง…';
                                final isPreset =
                                    _parseDaysFromLabel(opt) != null;

                                // เช็คว่า item นี้ถือว่า "selected" ไหม
                                final bool isSelected = () {
                                  if (isCustomTrigger) {
                                    // แสดงติ๊กเมื่อผู้ใช้กำหนดเองอยู่แล้ว
                                    return selectedExpiryFilter == 'กำหนดเอง';
                                  }
                                  if (isPreset) {
                                    return selectedExpiryFilter == opt;
                                  }
                                  return selectedExpiryFilter ==
                                      opt; // 'ทั้งหมด'
                                }();

                                // ปรับ label ถ้ากำหนดเอง + มีตัวเลขอยู่
                                String label = opt;
                                if (isCustomTrigger &&
                                    selectedExpiryFilter == 'กำหนดเอง' &&
                                    customDays != null) {
                                  label = 'กำหนดเอง (${customDays} วัน)';
                                }

                                return PopupMenuItem<String>(
                                  value: opt,
                                  child: Row(
                                    children: [
                                      if (isSelected)
                                        const Icon(
                                          Icons.check,
                                          size: 18,
                                          color: Colors.black,
                                        )
                                      else
                                        const SizedBox(width: 18),
                                      const SizedBox(width: 6),
                                      Text(label),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onSelected: (val) async {
                                if (val == 'กำหนดเอง…') {
                                  final prevFilter = selectedExpiryFilter;
                                  final prevDays = customDays;

                                  // ให้ป้ายข้างหลังแสดงเป็น "กำหนดเอง" ทันที ระหว่างพิมพ์
                                  setState(() {
                                    selectedExpiryFilter = 'กำหนดเอง';
                                    // ไม่ต้องแตะ customDays ที่นี่ ให้ user พิมพ์/เลือกใน dialog
                                  });

                                  final confirmed =
                                      await _showCustomDaysDialog(); // ← จะคืน true/false
                                  if (confirmed != true) {
                                    // ถ้ากดยกเลิก ให้ย้อนกลับค่าก่อนหน้า
                                    setState(() {
                                      selectedExpiryFilter = prevFilter;
                                      customDays = prevDays;
                                    });
                                  }
                                } else {
                                  // preset เช่น "7 วัน"
                                  setState(() {
                                    selectedExpiryFilter = val;
                                    customDays = null;
                                  });
                                }
                              },

                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      color: selectedExpiryFilter == 'ทั้งหมด'
                                          ? Colors.grey[600]
                                          : Colors.black,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      selectedExpiryFilter == 'ทั้งหมด'
                                          ? 'กรองตามวันหมดอายุ'
                                          : (selectedExpiryFilter == 'กำหนดเอง'
                                                ? 'หมดอายุในอีก (${customDays ?? 0} วัน)'
                                                : 'หมดอายุในอีก $selectedExpiryFilter'),
                                      style: TextStyle(
                                        color: selectedExpiryFilter == 'ทั้งหมด'
                                            ? Colors.grey[600]
                                            : Colors.black,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_drop_down,
                                      color: selectedExpiryFilter == 'ทั้งหมด'
                                          ? Colors.grey[600]
                                          : Colors.black,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // หมวดหมู่ย้ายไป SliverAppBar ที่ลอย (ด้านล่าง)
                  ],
                ),
              ),
            ),

            // 2) แถบหมวดหมู่แบบลอย (ซ่อนเมื่อเลื่อนลง โผล่เมื่อเลื่อนขึ้น)
            SliverAppBar(
              primary: false,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              elevation: 0,
              pinned: false,
              floating: true,
              snap: true,
              toolbarHeight: 0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: SizedBox(
                  height: 56,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: availableCategories.length,
                    itemBuilder: (_, idx) {
                      final c = availableCategories[idx];
                      final isSelected = selectedCategory == c;
                      return GestureDetector(
                        onTap: () => setState(() => selectedCategory = c),
                        child: Container(
                          margin: const EdgeInsets.only(
                            right: 12,
                            top: 8,
                            bottom: 8,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.yellow[600]
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Center(
                            child: Text(
                              c,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[600],
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _streamItems(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Text(
                    'เกิดข้อผิดพลาด: ${snap.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return _emptyState();
              }

              final all = _activeItemsFromDocs(snap.data!.docs);
              List<ShoppingItem> filtered = List.of(all);

              // กรองหมวดหมู่
              if (selectedCategory != _ALL) {
                filtered = filtered
                    .where((it) => (it.category) == selectedCategory)
                    .toList();
              }

              // กรองคำค้นหา
              if (searchQuery.isNotEmpty) {
                filtered = filtered
                    .where((it) => it.name.toLowerCase().contains(searchQuery))
                    .toList();
              }

              // กรองวันหมดอายุ: ภายใน N วันนับจาก "วันนี้" (รวมวันสิ้นสุด)
              final int? withinDays = _effectiveDays();
              if (withinDays != null && withinDays > 0) {
                final today = _stripDate(DateTime.now());
                final end = today.add(Duration(days: withinDays));
                filtered = filtered.where((it) {
                  final ed = it.expiryDate;
                  if (ed == null) return false;
                  final only = _stripDate(ed);
                  final geToday = !only.isBefore(today);
                  final leEnd = !only.isAfter(end);
                  return geToday && leEnd;
                }).toList();
              }

              // เรียงใกล้หมดอายุก่อน (null ไปท้าย)
              filtered.sort((a, b) {
                final ad = a.expiryDate;
                final bd = b.expiryDate;
                if (ad == null && bd == null) return 0;
                if (ad == null) return 1;
                if (bd == null) return -1;
                return ad.compareTo(bd);
              });

              if (filtered.isEmpty) {
                return _emptyAfterFilter();
              }

              // กลุ่มตามชื่อ (key เป็น lower-case เพื่อรวมชื่อซ้ำ)
              final Map<String, List<ShoppingItem>> grouped = {};
              for (final it in filtered) {
                final key = it.name.trim().toLowerCase();
                grouped.putIfAbsent(key, () => []).add(it);
              }

              final entries = grouped.entries.toList(growable: false);

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 120),
                itemCount: entries.length,
                cacheExtent: 600,
                itemBuilder: (_, idx) {
                  final e = entries[idx];
                  final groupItems = e.value;
                  if (groupItems.length == 1) {
                    final item = groupItems.first;
                    return KeyedSubtree(
                      key: ValueKey(item.id),
                      child: ShoppingItemCard(
                        item: item,
                        onDelete: () => _deleteItem(item.id),
                        onTap: () async {
                          Navigator.of(context).push<bool>(
                            PageRouteBuilder(
                              opaque: false,
                              barrierColor: Colors.transparent,
                              pageBuilder: (_, __, ___) =>
                                  ItemDetailPage(item: item),
                              transitionsBuilder: (_, a, __, child) =>
                                  FadeTransition(opacity: a, child: child),
                            ),
                          );
                        },
                        onQuickUse: () => _showQuickUseSheet(item),
                        // ถ้าต้องการให้ยืนยันลบเฉพาะ parent ให้ใส่ confirmDelete: false แล้วทำ confirm ที่นี่แทน
                        // confirmDelete: false,
                      ),
                    );
                  } else {
                    final displayName = groupItems.first.name;
                    return KeyedSubtree(
                      key: ValueKey('group-${e.key}'),
                      child: GroupedItemCard(
                        name: displayName,
                        items: groupItems,
                        onTap: () async {
                          await showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => ItemGroupDetailSheet(
                              groupName: displayName,
                              items: groupItems,
                            ),
                          );
                        },
                        // ✅ ผูกการลบทั้งกลุ่ม
                        onDeleteGroup: () => _deleteGroupItems(groupItems),
                      ),
                    );
                  }
                },
              );
            },
          ),
        ),
      ),
      // FAB: Write & Scan
      floatingActionButton: Container(
        decoration: BoxDecoration(
          color: Colors.yellow[700],
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              onPressed: _goAddRaw,
              icon: const Icon(Icons.edit, color: Colors.black),
              label: const Text(
                'Write',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _goScan,
              icon: const Icon(
                FontAwesomeIcons.barcode,
                size: 20,
                color: Colors.black,
              ),
              label: const Text(
                'Scan',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Small helpers =====
  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 12),
          Text(
            'ไม่มีรายการวัตถุดิบ',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _emptyAfterFilter() {
    final text = (selectedExpiryFilter != 'ทั้งหมด')
        ? 'ไม่มีวัตถุดิบที่หมดอายุภายใน ${selectedExpiryFilter == 'กำหนดเอง' ? '$customDays วัน' : selectedExpiryFilter}'
        : (searchQuery.isNotEmpty ? 'ไม่พบรายการที่ค้นหา' : 'ไม่มีรายการ');

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            selectedExpiryFilter != 'ทั้งหมด'
                ? Icons.schedule
                : Icons.search_off,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: Colors.grey[600])),
          if (searchQuery.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'คำค้นหา: "$searchQuery"',
                style: TextStyle(color: Colors.grey[500]),
              ),
            ),
        ],
      ),
    );
  }
}
