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
import 'package:my_app/rawmaterial/pages/expired_raw.dart';

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
  late final StreamController<List<ShoppingItem>> _itemsController;
  late final Stream<List<ShoppingItem>> _itemsStream;
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _memberItemSubs = {};
  final Map<String, List<ShoppingItem>> _memberItems = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _familyMembersSub;
  String? _currentFamilyId;
  List<ShoppingItem> _latestItems = const [];

  bool _isSyncingFamilyIds = false;
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
    _itemsController = StreamController<List<ShoppingItem>>.broadcast();
    _itemsStream = _itemsController.stream;
    _searchFocusNode.addListener(_onSearchFocusChange);
    // เริ่มฟังข้อมูลวัตถุดิบ (รวมของคนในครอบครัว)
    _startInventoryListeners();
    if (!_itemsController.isClosed) {
      _itemsController.add(const []);
    }
    _loadAvailableCategories();
  }

  @override
  void dispose() {
    if (_userDocSub != null) {
      unawaited(_userDocSub!.cancel());
      _userDocSub = null;
    }
    if (_familyMembersSub != null) {
      unawaited(_familyMembersSub!.cancel());
      _familyMembersSub = null;
    }
    for (final sub in _memberItemSubs.values) {
      unawaited(sub.cancel());
    }
    _memberItemSubs.clear();
    _memberItems.clear();
    if (!_itemsController.isClosed) {
      _itemsController.close();
    }
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
    _scheduleAvailableCategoriesUpdate(_latestItems, immediate: true);
  }

  void _startInventoryListeners() {
    final user = currentUser;
    if (user == null) {
      _currentFamilyId = null;

      _isSyncingFamilyIds = false;
      _updateMemberSubscriptions({});
      _latestItems = const [];
      if (!_itemsController.isClosed) {
        _itemsController.add(const []);
      }
      return;
    }

    _updateMemberSubscriptions({user.uid});

    _userDocSub = _firestore
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snap) {
            final data = snap.data();
            final rawFamily = data?['familyId'] ?? data?['family_id'];
            final familyId = rawFamily == null
                ? null
                : rawFamily.toString().trim();

            if (familyId == null || familyId.isEmpty) {
              _currentFamilyId = null;
              if (_familyMembersSub != null) {
                unawaited(_familyMembersSub!.cancel());
                _familyMembersSub = null;
              }
              _scheduleFamilySync(null, uid: user.uid);
              _updateMemberSubscriptions({user.uid});
              return;
            }

            final shouldResubscribe =
                _currentFamilyId != familyId || _familyMembersSub == null;

            if (shouldResubscribe) {
              _currentFamilyId = familyId;
              _scheduleFamilySync(familyId, uid: user.uid);
              if (_familyMembersSub != null) {
                unawaited(_familyMembersSub!.cancel());
                _familyMembersSub = null;
              }
              // คงการฟังของตัวเองไว้ระหว่างรอข้อมูลสมาชิก
              _updateMemberSubscriptions({user.uid});

              _familyMembersSub = _firestore
                  .collection('family_members')
                  .where('familyId', isEqualTo: familyId)
                  .snapshots()
                  .listen(
                    (memberSnap) {
                      final ids = <String>{user.uid};
                      for (final doc in memberSnap.docs) {
                        final data = doc.data();
                        final memberRaw = data['userId'] ?? data['uid'];
                        if (memberRaw == null) continue;
                        final memberId = memberRaw.toString().trim();
                        if (memberId.isNotEmpty) ids.add(memberId);
                      }
                      _updateMemberSubscriptions(ids);
                    },
                    onError: (error, stack) {
                      if (!_itemsController.isClosed) {
                        _itemsController.addError(error, stack);
                      }
                    },
                  );
            }
          },
          onError: (error, stack) {
            if (!_itemsController.isClosed) {
              _itemsController.addError(error, stack);
            }
          },
        );
  }

  void _updateMemberSubscriptions(Set<String> targetIds) {
    final sanitized = targetIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final currentIds = _memberItemSubs.keys.toSet();
    final toRemove = currentIds.difference(sanitized);
    final toAdd = sanitized.difference(currentIds);

    for (final id in toRemove) {
      _memberItemSubs.remove(id)?.cancel();
      _memberItems.remove(id);
    }
    if (toRemove.isNotEmpty) _emitAggregatedItems();

    for (final id in toAdd) {
      _memberItems[id] = const [];

      // ✨ ใช้ where เฉพาะตอนอ่านของ “คนอื่น”
      final coll = _firestore
          .collection('users')
          .doc(id)
          .collection('raw_materials');
      Query<Map<String, dynamic>> query;
      if (id == currentUser?.uid) {
        query = coll; // ของตัวเองอ่านตรงๆ
      } else {
        final fid = _currentFamilyId;
        // ถ้าไม่มี familyId ก็ไม่ควร subscribe คนอื่นอยู่แล้ว
        query = (fid != null && fid.isNotEmpty)
            ? coll.where('familyId', isEqualTo: fid)
            : coll.where('ownerId', isEqualTo: id); // กันพลาด
      }

      final sub = query.snapshots().listen(
        (snap) {
          if (id == currentUser?.uid) {
            unawaited(_syncFamilyIdsForSelf(snap.docs));
          }
          final items = _activeItemsFromDocs(snap.docs, ownerId: id);
          _memberItems[id] = items;
          _emitAggregatedItems();
        },
        onError: (e, st) {
          if (!_itemsController.isClosed) _itemsController.addError(e, st);
        },
      );
      _memberItemSubs[id] = sub;
    }
  }

  void _scheduleFamilySync(String? fid, {String? uid}) {
    fid?.trim();
    final targetUid = (uid ?? currentUser?.uid)?.trim();
    if (targetUid == null || targetUid.isEmpty) return;
    unawaited(
      _firestore
          .collection('users')
          .doc(targetUid)
          .collection('raw_materials')
          .get()
          .then((snap) => _syncFamilyIdsForSelf(snap.docs)),
    );
  }

  Future<void> _syncFamilyIdsForSelf(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (_isSyncingFamilyIds) return;
    final fid = _currentFamilyId?.trim();
    final userId = currentUser?.uid;
    if (userId == null) return;

    final targets = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final doc in docs) {
      final data = doc.data();
      final rawFamily = data['familyId'] ?? data['family_id'];
      final ownerId = (data['ownerId'] ?? data['owner_id'])?.toString().trim();
      if (ownerId != null && ownerId.isNotEmpty && ownerId != userId) continue;
      final currentFamily = rawFamily?.toString().trim();
      final shouldUpdate = (fid == null)
          ? (currentFamily != null &&
                currentFamily.isNotEmpty) // มีค่าอยู่ → ต้องล้าง
          : (currentFamily == null || currentFamily != fid);
      if (shouldUpdate) targets.add(doc);
    }
    if (targets.isEmpty) return;

    _isSyncingFamilyIds = true;
    try {
      WriteBatch batch = _firestore.batch();
      var ops = 0;
      for (final doc in targets) {
        batch.set(doc.reference, {
          if (fid == null) 'familyId': FieldValue.delete() else 'familyId': fid,
          'family_id': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        ops++;
        if (ops >= 400) {
          await batch.commit();
          batch = _firestore.batch();
          ops = 0;
        }
      }
      if (ops > 0) await batch.commit();
    } catch (e, st) {
      debugPrint('sync familyId failed: $e');
      debugPrintStack(stackTrace: st);
    } finally {
      _isSyncingFamilyIds = false;
    }
  }

  void _emitAggregatedItems() {
    final aggregated = _memberItems.values
        .expand((items) => items)
        .toList(growable: false);
    _latestItems = aggregated;
    if (!_itemsController.isClosed) {
      _itemsController.add(aggregated);
    }
    if (mounted) {
      _scheduleAvailableCategoriesUpdate(aggregated);
    }
  }

  DocumentReference<Map<String, dynamic>>? _itemDocRef(ShoppingItem item) {
    if (item.reference != null) return item.reference;
    final ownerId = item.ownerId.isNotEmpty
        ? item.ownerId
        : currentUser?.uid ?? '';
    if (ownerId.isEmpty) return null;
    return _firestore
        .collection('users')
        .doc(ownerId)
        .collection('raw_materials')
        .doc(item.id);
  }

  Future<void> _manualRefresh() async {
    final user = currentUser;
    if (user == null) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return;
    }

    final ids = <String>{
      ..._memberItems.keys,
      ..._memberItemSubs.keys,
      user.uid,
    }..removeWhere((id) => id.trim().isEmpty);

    try {
      final fid = _currentFamilyId;
      final futures = ids
          .map((uid) async {
            final base = _firestore
                .collection('users')
                .doc(uid)
                .collection('raw_materials');
            Query<Map<String, dynamic>> q;
            if (uid == user.uid) {
              q = base;
            } else {
              q = (fid != null && fid.isNotEmpty)
                  ? base.where('familyId', isEqualTo: fid)
                  : base.where('ownerId', isEqualTo: uid);
            }
            final snap = await q.get();
            final items = _activeItemsFromDocs(snap.docs, ownerId: uid);
            return MapEntry(uid, items);
          })
          .toList(growable: false);

      final results = await Future.wait(futures);
      for (final entry in results) {
        _memberItems[entry.key] = entry.value;
      }
      _emitAggregatedItems();
      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('Manual refresh failed: $e');
      debugPrintStack(stackTrace: st);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('รีเฟรชไม่สำเร็จ: $e')));
      }
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  Widget _placeholderList(Widget child) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 64),
      children: [Center(child: child)],
    );
  }

  List<ShoppingItem> _activeItemsFromDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String ownerId,
  }) {
    final today = _stripDate(DateTime.now());
    return docs
        .map((d) {
          final data = d.data();
          final rawFamily = data['familyId'] ?? data['family_id'];
          final familyStr = rawFamily == null
              ? null
              : rawFamily.toString().trim();
          return ShoppingItem.fromMap(
            data,
            d.id,
            ownerId: ownerId,
            familyId: familyStr,
            reference: d.reference,
          );
        })
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

              final docRef = _itemDocRef(item);
              if (docRef == null) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ไม่พบข้อมูลเจ้าของวัตถุดิบ')),
                );
                return;
              }

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
              setState(() {});
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
            }
          },
        );
      },
    ).then((used) {
      if (used == true) {
        unawaited(_manualRefresh());
      }
    });
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

  // ===== Mutations =====

  Future<void> _useUpItem(
    ShoppingItem item, {
    required int usedQty,
    required String usedUnit,
  }) async {
    if (currentUser == null) return;
    final ref = _itemDocRef(item);
    if (ref == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่พบข้อมูลของ "${item.name}"')),
        );
      }
      return;
    }
    try {
      final batch = _firestore.batch();

      // 1) เขียน usage_log (subcollection) — ใช้ doc id ใหม่ใน batch ได้
      final logRef = ref.collection('usage_logs').doc();
      batch.set(logRef, {
        'action': 'use_up', // ชัดเจนว่าใช้หมดแล้ว
        'quantity': usedQty, // จำนวนที่การ์ดแสดง/ส่งมา
        'unit': usedUnit, // หน่วยที่การ์ดแสดง/ส่งมา
        'used_at': FieldValue.serverTimestamp(),
      });

      // 2) อัปเดตสต็อกให้เป็น 0 (และออปชัน inactive)
      batch.update(ref, {
        'quantity': 0,
        'updated_at': FieldValue.serverTimestamp(),
        'inactive': true, // ช่วยซ่อนจาก UI/filter ได้
      });

      await batch.commit();

      await _loadAvailableCategories();
      await _manualRefresh();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('บันทึกการใช้หมดสำหรับ "${item.name}" แล้ว'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('บันทึกการใช้ไม่สำเร็จ: $e'),
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
                  StreamBuilder<List<ShoppingItem>>(
                    stream: _itemsStream,
                    builder: (_, snapshot) {
                      final count = snapshot.data?.length ?? 0;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$count ชิ้น',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              const SizedBox(width: 8),
                              IconButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ExpiredRawPage(),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons
                                      .history_rounded, // ✅ ไอคอนประวัติ/ย้อนหลัง
                                  color: Colors.red, // สีแดงเตือนหมดอายุ
                                  size: 24, // ปรับขนาดได้
                                ),
                                tooltip:
                                    'หมดอายุแล้ว', // โผล่เมื่อ hover/long press
                              ),
                            ],
                          ),
                        ],
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
                                : Colors.yellow[700]!,
                            surfaceTintColor: Colors.transparent,
                            shape: StadiumBorder(
                              side: BorderSide(
                                color: selectedExpiryFilter == 'ทั้งหมด'
                                    ? Colors.grey[400]!
                                    : Colors.yellow[700]!,
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

                              // ⬇️ เพิ่มหัวข้อด้านบนของเมนู
                              itemBuilder: (_) => <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  enabled: false,
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.filter_alt_rounded,
                                        size: 18,
                                        color: Colors.black,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'กรองตามวันหมดอายุ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(height: 8),

                                // ตัวเลือกเดิมทั้งหมด
                                ..._expiryOptions.map((opt) {
                                  final isCustomTrigger = opt == 'กำหนดเอง…';
                                  final isPreset =
                                      _parseDaysFromLabel(opt) != null;

                                  final bool isSelected = () {
                                    if (isCustomTrigger)
                                      return selectedExpiryFilter == 'กำหนดเอง';
                                    if (isPreset)
                                      return selectedExpiryFilter == opt;
                                    return selectedExpiryFilter ==
                                        opt; // 'ทั้งหมด'
                                  }();

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
                              ],

                              onSelected: (val) async {
                                if (val == 'กำหนดเอง…') {
                                  final prevFilter = selectedExpiryFilter;
                                  final prevDays = customDays;
                                  setState(
                                    () => selectedExpiryFilter = 'กำหนดเอง',
                                  );
                                  final confirmed =
                                      await _showCustomDaysDialog();
                                  if (confirmed != true) {
                                    setState(() {
                                      selectedExpiryFilter = prevFilter;
                                      customDays = prevDays;
                                    });
                                  }
                                } else {
                                  setState(() {
                                    selectedExpiryFilter = val;
                                    customDays = null;
                                  });
                                }
                              },

                              // ⬇️ ปุ่มด้านหน้าจะโชว์เฉพาะไอคอน sort + caret
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.sort_rounded,
                                      color: selectedExpiryFilter == 'ทั้งหมด'
                                          ? Colors.grey[600]
                                          : Colors.black,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 4),
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

                      // เลือกไอคอน: "ทั้งหมด" ใช้ไอคอนรวมหมวด, อื่น ๆ ใช้จาก Categories.iconFor
                      final IconData icon = (c == _ALL)
                          ? Icons
                                .apps // หรือ Icons.dashboard_customize_outlined
                          : Categories.iconFor(c);

                      return GestureDetector(
                        onTap: () => setState(() => selectedCategory = c),
                        child: Container(
                          margin: const EdgeInsets.only(
                            right: 12,
                            top: 8,
                            bottom: 8,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.yellow[700]
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(20),
                            // (ถ้าอยากมีเส้นขอบจาง ๆ ให้เปิด block นี้)
                            // border: Border.all(
                            //   color: isSelected ? Colors.yellow[700]! : Colors.grey[300]!,
                            // ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icon,
                                size: 18,
                                // ✅ ไอคอนสีดำเสมอ
                                color: Colors.black,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                c,
                                // ✅ ตัวหนังสือสีดำเสมอ (ตามที่ขอ) และหนาขึ้นเมื่อถูกเลือก
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
          body: StreamBuilder<List<ShoppingItem>>(
            stream: _itemsStream,
            builder: (_, snap) {
              Widget child;

              if (snap.hasError) {
                child = _placeholderList(
                  Text(
                    'เกิดข้อผิดพลาด: ${snap.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                );
              } else {
                final all = snap.data ?? const <ShoppingItem>[];

                if (snap.connectionState == ConnectionState.waiting &&
                    all.isEmpty) {
                  child = _placeholderList(
                    const SizedBox(
                      height: 140,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                } else if (all.isEmpty) {
                  child = _placeholderList(_emptyState());
                } else {
                  List<ShoppingItem> filtered = List.of(all);

                  if (selectedCategory != _ALL) {
                    filtered = filtered
                        .where((it) => (it.category) == selectedCategory)
                        .toList();
                  }

                  if (searchQuery.isNotEmpty) {
                    filtered = filtered
                        .where(
                          (it) => it.name.toLowerCase().contains(searchQuery),
                        )
                        .toList();
                  }

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

                  filtered.sort((a, b) {
                    final ad = a.expiryDate;
                    final bd = b.expiryDate;
                    if (ad == null && bd == null) return 0;
                    if (ad == null) return 1;
                    if (bd == null) return -1;
                    return ad.compareTo(bd);
                  });

                  if (filtered.isEmpty) {
                    child = _placeholderList(_emptyAfterFilter());
                  } else {
                    final Map<String, List<ShoppingItem>> grouped = {};
                    for (final it in filtered) {
                      final key = it.name.trim().toLowerCase();
                      grouped.putIfAbsent(key, () => []).add(it);
                    }

                    final entries = grouped.entries.toList(growable: false);

                    child = ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 120),
                      itemCount: entries.length,
                      cacheExtent: 600,
                      itemBuilder: (_, idx) {
                        final entry = entries[idx];
                        final groupItems = entry.value;

                        if (groupItems.length == 1) {
                          final item = groupItems.first;
                          return KeyedSubtree(
                            key: ValueKey(item.id),
                            child: ShoppingItemCard(
                              item: item,
                              onUseUp: (usedQty, usedUnit) => _useUpItem(
                                item,
                                usedQty: usedQty,
                                usedUnit: usedUnit,
                              ),
                              onTap: () async {
                                final changed = await Navigator.of(context)
                                    .push<bool>(
                                      PageRouteBuilder(
                                        opaque: false,
                                        barrierColor: Colors.transparent,
                                        pageBuilder: (_, __, ___) =>
                                            ItemDetailPage(item: item),
                                        transitionsBuilder: (_, a, __, child) =>
                                            FadeTransition(
                                              opacity: a,
                                              child: child,
                                            ),
                                      ),
                                    );
                                if (!mounted) return;
                                if (changed == true) {
                                  await _manualRefresh();
                                }
                              },
                              onQuickUse: () => _showQuickUseSheet(item),
                              // ถ้าต้องการให้ยืนยันลบเฉพาะ parent ให้ใส่ confirmDelete: false แล้วทำ confirm ที่นี่แทน
                              // confirmDelete: false,
                            ),
                          );
                        } else {
                          final displayName = groupItems.first.name;
                          return KeyedSubtree(
                            key: ValueKey('group-${entry.key}'),
                            child: GroupedItemCard(
                              name: displayName,
                              items: groupItems,
                              onTap: () async {
                                final changed =
                                    await showModalBottomSheet<bool>(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => ItemGroupDetailSheet(
                                        groupName: displayName,
                                        items: groupItems,
                                      ),
                                    );
                                if (!mounted) return;
                                if (changed == true) {
                                  await _manualRefresh();
                                }
                              },
                              onUseUpGroup: (items) async {
                                // ที่นี่ให้คุณ loop ทีละ item:
                                // - เขียนลง subcollection usage_logs
                                // - update quantity = 0, updated_at = serverTimestamp
                                // ทำเป็น batch/chunk เหมือนที่คุณทำ _deleteGroupItems ก็ได้
                              },
                            ),
                          );
                        }
                      },
                    );
                  }
                }
              }

              return RefreshIndicator(
                onRefresh: _manualRefresh,
                displacement: 60,
                child: child,
              );
            },
          ),
        ),
      ),
      // FAB: Add & Scan
      floatingActionButton: Material(
        color: Colors.yellow[700],
        elevation: 12, // 👈 เงาหลัก
        shadowColor: Colors.black.withOpacity(0.3),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: null, // ปิด tap ทั้งก้อน (เราใช้ปุ่มด้านในแทน)
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: _goAddRaw,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.black,
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.edit),
                  label: const Text(
                    'Add',
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
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.black,
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(FontAwesomeIcons.barcode, size: 20),
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
