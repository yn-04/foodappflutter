// lib/rawmaterial/pages/item_detail_page.dart — หน้าเต็มจอ แก้ไข/ลบ วัตถุดิบ เมื่อกดจากการ์ดวัตถุดิบ
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:my_app/rawmaterial/constants/units.dart';
import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/models/shopping_item.dart';

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
  late TextEditingController _consumeCtrl;
  late TextEditingController _noteCtrl;

  late String _category;
  late String _unit;
  DateTime? _expiry;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _nameCtrl = TextEditingController(text: i.name);
    _qtyCtrl = TextEditingController(text: i.quantity.toString());
    _consumeCtrl = TextEditingController();
    _noteCtrl = TextEditingController();

    _category = i.category;
    _unit = Units.safe(i.unit);
    _expiry = i.expiryDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _consumeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String _formatThaiDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year2 = (d.year + 543).toString().substring(2);
    return '$day/$month/$year2';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  Future<void> _save() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final newName = _nameCtrl.text.trim();
    final newQty = int.tryParse(_qtyCtrl.text) ?? widget.item.quantity;
    if (newName.isEmpty || newQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณากรอกชื่อและจำนวนให้ถูกต้อง')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .doc(widget.item.id)
          .update({
            'name': newName,
            'category': _category,
            'quantity': newQty,
            'unit': _unit,
            'expiry_date': _expiry != null
                ? Timestamp.fromDate(_expiry!)
                : null,
            'updated_at': FieldValue.serverTimestamp(),
          });
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final user = _auth.currentUser;
    if (user == null) return;
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
    if (ok != true) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .doc(widget.item.id)
          .delete();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ลบไม่สำเร็จ: $e')));
    }
  }

  Future<void> _duplicate() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final data = {
        'name': _nameCtrl.text.trim(),
        'category': _category,
        'quantity': int.tryParse(_qtyCtrl.text) ?? widget.item.quantity,
        'unit': _unit,
        'expiry_date': _expiry != null ? Timestamp.fromDate(_expiry!) : null,
        'imageUrl': widget.item.imageUrl,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'user_id': user.uid,
      };
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .add(data);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ทำซ้ำแล้ว')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ทำซ้ำไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = () {
      if (_expiry == null) return ('ยังไม่ระบุวันหมดอายุ', Colors.green);
      final d = _expiry!.difference(DateTime.now()).inDays;
      if (d < 0) return ('หมดอายุแล้ว', Colors.red);
      if (d <= 3) return ('ใกล้หมดอายุ', Colors.orange);
      return ('ยังไม่หมดอายุ', Colors.green);
    }();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'รายละเอียดวัตถุดิบ',
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'ทำซ้ำ',
            onPressed: _duplicate,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'ลบ',
            onPressed: _delete,
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            16 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // สถานะหมดอายุ
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: status.$2.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status.$1,
                  style: TextStyle(
                    color: status.$2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ชื่อ
              const Text(
                'ชื่อวัตถุดิบ',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              TextField(controller: _nameCtrl, decoration: _inputDecoration()),
              const SizedBox(height: 12),

              // หมวดหมู่
              const Text(
                'หมวดหมู่',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _category,
                items: <String>[...Categories.list]
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
                decoration: _inputDecoration(),
              ),
              const SizedBox(height: 12),

              // จำนวน + หน่วย
              const Text(
                'จำนวน',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      final n = int.tryParse(_qtyCtrl.text) ?? 1;
                      if (n > 1) _qtyCtrl.text = (n - 1).toString();
                    },
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.red,
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: _qtyCtrl,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration(isDense: true),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      final n = int.tryParse(_qtyCtrl.text) ?? 0;
                      _qtyCtrl.text = (n + 1).toString();
                    },
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _unit,
                      items: Units.all
                          .map(
                            (u) => DropdownMenuItem(value: u, child: Text(u)),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _unit = Units.safe(v)),
                      decoration: _inputDecoration().copyWith(
                        prefixIcon: Icon(
                          Icons.straighten,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // วันหมดอายุ
              const Text(
                'วันหมดอายุ',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(
                        _expiry == null
                            ? 'แตะเพื่อเลือกวันที่'
                            : _formatThaiDate(_expiry!),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      if (_expiry != null)
                        InkWell(
                          onTap: () => setState(() => _expiry = null),
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
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
              const SizedBox(height: 24),

              // ใช้วัตถุดิบ (ตัดสต็อก + ลง log)

              // ปุ่มบันทึก
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow[300],
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.black),
                          ),
                        )
                      : const Text(
                          'บันทึกการเปลี่ยนแปลง',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({bool isDense = false}) => InputDecoration(
    isDense: isDense,
    filled: true,
    fillColor: Colors.grey[50],
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
  );
}
