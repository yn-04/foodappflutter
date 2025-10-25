// lib/rawmaterial/pages/expired_raw.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/constants/units.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';

class ExpiredRawPage extends StatefulWidget {
  const ExpiredRawPage({super.key});

  @override
  State<ExpiredRawPage> createState() => _ExpiredRawPageState();
}

class _ExpiredRawPageState extends State<ExpiredRawPage> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  late DateTime _startDate; // เริ่มต้น = วันนี้ - 30 วัน
  late DateTime _endDate; // เริ่มต้น = วันนี้
  Future<List<ShoppingItem>>? _future;

  String? _currentFamilyId;
  List<String> _familyMemberIds = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _endDate = DateTime(now.year, now.month, now.day); // ตัดเวลา
    _startDate = _endDate.subtract(const Duration(days: 30));
    _future = _loadAll();
  }

  Future<List<ShoppingItem>> _loadAll() async {
    final user = _auth.currentUser;
    if (user == null) return const [];

    // ดึง familyId ของฉัน
    final meDoc = await _firestore.collection('users').doc(user.uid).get();
    final rawFamily = (meDoc.data()?['familyId'] ?? meDoc.data()?['family_id'])
        ?.toString()
        .trim();
    _currentFamilyId = (rawFamily != null && rawFamily.isNotEmpty)
        ? rawFamily
        : null;

    // สร้างชุด userIds ที่จะดึง (ถ้ามี family → สมาชิกทั้งหมด + ตัวเอง)
    final memberIds = <String>{user.uid};
    if (_currentFamilyId != null) {
      final familySnap = await _firestore
          .collection('family_members')
          .where('familyId', isEqualTo: _currentFamilyId)
          .get();
      for (final d in familySnap.docs) {
        final m = (d.data()['userId'] ?? d.data()['uid'])?.toString().trim();
        if (m != null && m.isNotEmpty) memberIds.add(m);
      }
    }
    _familyMemberIds = memberIds.toList();

    // ช่วงวันที่ต้องการ (เฉพาะ field เดียว: expiry_date)
    final tsStart = Timestamp.fromDate(_startDate);
    // รวมถึงวันนี้ -> ใช้ <= end; Firestore รองรับ <= ด้วย isLessThanOrEqualTo
    final tsEnd = Timestamp.fromDate(_endDate);

    final List<ShoppingItem> acc = [];

    for (final uid in _familyMemberIds) {
      final base = _firestore
          .collection('users')
          .doc(uid)
          .collection('raw_materials');

      Query<Map<String, dynamic>> q = base
          .where('expiry_date', isGreaterThanOrEqualTo: tsStart)
          .where('expiry_date', isLessThanOrEqualTo: tsEnd);

      // ถ้าเป็นของคนอื่นและมี family → กันหลุดด้วย familyId
      if (_currentFamilyId != null && uid != user.uid) {
        q = q.where('familyId', isEqualTo: _currentFamilyId);
      }

      final snap = await q.get();

      for (final d in snap.docs) {
        final data = d.data();

        // แปลงเป็น ShoppingItem (เหมือนหน้าหลัก)
        final item = ShoppingItem.fromMap(
          data,
          d.id,
          ownerId: uid,
          familyId: (data['familyId'] ?? data['family_id'])?.toString().trim(),
          reference: d.reference,
        );

        // เงื่อนไข: quantity != 0 และ "หมดอายุแล้ว"
        final ed = item.expiryDate;
        if (item.quantity != 0 && ed != null) {
          final only = DateTime(ed.year, ed.month, ed.day);
          final today = DateTime.now();
          final todayOnly = DateTime(today.year, today.month, today.day);
          if (!only.isAfter(todayOnly)) {
            // ed <= today
            acc.add(item);
          }
        }
      }
    }

    // เรียงล่าสุดไปเก่าสุด (อยากเห็นที่เพิ่งหมดก่อน)
    acc.sort((a, b) {
      final ad = a.expiryDate!;
      final bd = b.expiryDate!;
      return bd.compareTo(ad);
    });
    return acc;
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(_endDate.year - 2),
      lastDate: _endDate,
      helpText: 'เลือกวันที่เริ่ม (ย้อนหลัง)',
    );
    if (picked == null) return;
    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day);
      _future = _loadAll();
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(_startDate.year - 2),
      lastDate: DateTime.now(),
      helpText: 'เลือกวันที่สิ้นสุด',
    );
    if (picked == null) return;
    setState(() {
      _endDate = DateTime(picked.year, picked.month, picked.day);
      if (_endDate.isBefore(_startDate)) {
        _startDate = _endDate.subtract(const Duration(days: 1));
      }
      _future = _loadAll();
    });
  }

  String _fmt(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = (d.year + 543).toString(); // แสดง พ.ศ.
    return '$dd/$mm/$yyyy';
  }

  String _expiredAgoText(DateTime ed) {
    final today = DateTime.now();
    final t = DateTime(today.year, today.month, today.day);
    final e = DateTime(ed.year, ed.month, ed.day);
    final diff = t.difference(e).inDays;
    if (diff <= 0) return 'หมดอายุวันนี้';
    return 'หมดมาแล้ว $diff วัน';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('วัตถุดิบที่หมดอายุ'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ฟิลเตอร์ช่วงวันที่
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _DateBox(
                    label: 'จาก',
                    value: _fmt(_startDate),
                    onTap: _pickStart,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateBox(
                    label: 'ถึง',
                    value: _fmt(_endDate),
                    onTap: _pickEnd,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: FutureBuilder<List<ShoppingItem>>(
              future: _future,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
                }
                final items = snap.data ?? const <ShoppingItem>[];
                if (items.isEmpty) {
                  return _emptyState();
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _future = _loadAll());
                    await _future;
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final it = items[i];
                      final icon = Categories.iconFor(it.category);
                      final color = Categories.colorFor(it.category);
                      final ed = it.expiryDate!;
                      return Material(
                        elevation: 2,
                        shadowColor: Colors.black.withOpacity(0.08),
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {}, // ถ้าจะลิงก์ไปหน้า detail เพิ่มได้
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // แถวบน: ชื่อ + สรุปหมดแล้วกี่วัน
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        it.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.history, // วงกลมลูกศรย้อน
                                          size: 18,
                                          color: Colors.red,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _expiredAgoText(ed),
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                // แถวกลาง: หมวดหมู่ + ปริมาณ (ไม่มีกรอบ/ชิป)
                                Row(
                                  children: [
                                    Icon(icon, size: 16, color: color),
                                    const SizedBox(width: 6),
                                    Text(
                                      Categories.normalize(it.category),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('•'),
                                    const SizedBox(width: 10),
                                    Text(
                                      '${it.quantity} ${Units.safe(it.unit)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 8),
                                // แถวล่าง: วันหมดอายุ (ปกติ)
                                Row(
                                  children: [
                                    Icon(
                                      Icons.event_outlined,
                                      size: 16,
                                      color: Colors.grey[700],
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _fmt(ed),
                                      style: TextStyle(
                                        color: Colors.grey[800],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 80),
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'ไม่มีวัตถุดิบที่หมดอายุในช่วงนี้',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ],
    );
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$label: $value',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.edit_calendar, size: 18),
          ],
        ),
      ),
    );
  }
}
