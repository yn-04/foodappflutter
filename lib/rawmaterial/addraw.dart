// lib/rawmaterial/addraw.dart — หน้าสร้าง/เพิ่มวัตถุดิบใหม่ (Minimal, Fast, Grey Tone)
// - ดึงหมวดหมู่จาก Categories.list
// - แนะนำชื่อวัตถุดิบแบบกรองอัตโนมัติ (จำกัดจำนวน แสดงโทนเทา)
// - Dropdown/เมนูต่าง ๆ เลื่อนดูได้ (menuMaxHeight)
// - ปุ่ม +/− สีเทา ไม่มีไอคอน
// - ช่อง "หมายเหตุ" เตี้ยลง
// - ไม่มีอิโมจิใน UI

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/constants/units.dart';

class AddRawMaterialPage extends StatefulWidget {
  // รับข้อมูลจากบาร์โค้ด (ถ้ามี)
  final String? scannedBarcode;
  final Map<String, dynamic>? scannedProductData;

  const AddRawMaterialPage({
    super.key,
    this.scannedBarcode,
    this.scannedProductData,
  });

  @override
  State<AddRawMaterialPage> createState() => _AddRawMaterialPageState();
}

class _AddRawMaterialPageState extends State<AddRawMaterialPage> {
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _notesController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _brandController = TextEditingController();
  final _quantityController = TextEditingController();

  int _quantity = 1;
  String _selectedUnit = Units.all.first;
  String _selectedExpiry = ''; // บังคับเลือก
  String? _selectedCategory;
  DateTime? _customExpiryDate;
  bool _isLoading = false;

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ใช้จาก categories.dart
  List<String> get _categories => Categories.list;

  // recent & suggestions
  List<String> _recentMaterials = []; // รายการล่าสุด (ไม่ซ้ำ)
  List<String> _nameSuggestions = []; // ที่กรองตามข้อความ ณ ตอนพิมพ์

  // หน้าตาโทนเทา
  static const _greyBorder = Colors.black; // กรอบโทนเข้ม (ยังดูมินิมอล)
  static final _hintGrey = Colors.grey[500];
  static final _chipGreyBg = Colors.grey[200];
  static final _chipGreyText = Colors.grey[800];

  @override
  void initState() {
    super.initState();
    _enableFirestoreIfNeeded();
    _loadRecentMaterials(); // ดึงชื่อที่เคยใช้ (จำกัด)
    _initializeWithScannedData(); // เติมข้อมูลจากบาร์โค้ด
    _quantityController.text = _quantity.toString();

    // สร้าง suggestion เริ่มต้นว่าง
    _nameSuggestions = [];
    _nameController.addListener(_recomputeNameSuggestions);
  }

  @override
  void dispose() {
    _nameController.removeListener(_recomputeNameSuggestions);
    _nameController.dispose();
    _priceController.dispose();
    _notesController.dispose();
    _barcodeController.dispose();
    _brandController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _enableFirestoreIfNeeded() async {
    try {
      await _firestore.enableNetwork();
    } catch (_) {
      // ignore
    }
  }

  Future<void> _loadRecentMaterials() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // จำกัด 30 รายการล่าสุด แล้ว unique
      final snap = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .orderBy('created_at', descending: true)
          .limit(30)
          .get();

      final set = <String>{};
      for (final d in snap.docs) {
        final n = (d.data()['name'] ?? '').toString().trim();
        if (n.isNotEmpty) set.add(n);
      }

      if (!mounted) return;
      setState(() {
        _recentMaterials = set.toList();
      });
      _recomputeNameSuggestions();
    } catch (_) {
      // ไม่ต้องโวยวาย UI
    }
  }

  void _initializeWithScannedData() {
    if (widget.scannedBarcode != null) {
      _barcodeController.text = widget.scannedBarcode!;
    }
    final data = widget.scannedProductData;
    if (data == null) return;

    _nameController.text = (data['name'] ?? '').toString();
    _brandController.text = (data['brand'] ?? '').toString();

    final cat = Categories.normalize(data['category']);
    if (cat.isNotEmpty && _categories.contains(cat)) {
      _selectedCategory = cat;
    }

    final unit = Units.safe(data['unit']);
    if (Units.isValid(unit)) {
      _selectedUnit = unit;
    }

    final dq = data['defaultQuantity'];
    if (dq is num && dq > 0) {
      _quantity = dq.toInt();
      _quantityController.text = _quantity.toString();
    }

    final price = data['price'];
    if (price != null) {
      _priceController.text = price.toString();
    }
  }

  void _recomputeNameSuggestions() {
    final q = _nameController.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _nameSuggestions = []);
      return;
    }
    // กรองแบบ startsWith ก่อน, ไม่งั้นค่อย contains, จำกัด 6 รายการ
    final starts = _recentMaterials
        .where((e) => e.toLowerCase().startsWith(q))
        .toList();
    final contains = _recentMaterials
        .where((e) => !starts.contains(e) && e.toLowerCase().contains(q))
        .toList();

    final merged = <String>[...starts, ...contains];

    setState(() {
      _nameSuggestions = merged.take(6).toList();
    });
  }

  // ===== Validate & Save =====
  Future<void> _saveRawMaterial() async {
    if (_nameController.text.trim().isEmpty) {
      _toastError('กรุณาใส่ชื่อวัตถุดิบ');
      return;
    }
    if (_selectedCategory == null) {
      _toastError('กรุณาเลือกหมวดหมู่');
      return;
    }
    if (_quantity <= 0) {
      _toastError('กรุณาระบุจำนวนที่มากกว่า 0');
      return;
    }
    if (!Units.isValid(_selectedUnit)) {
      _toastError('กรุณาเลือกหน่วย');
      return;
    }
    if (_selectedExpiry.isEmpty) {
      _toastError('กรุณาเลือกวันหมดอายุ');
      return;
    }
    if (_selectedExpiry == 'กำหนดเอง' && _customExpiryDate == null) {
      _toastError('กรุณาเลือกวันที่หมดอายุ');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) {
        _toastError('กรุณาเข้าสู่ระบบก่อน');
        return;
      }

      DateTime? expiryDate;
      switch (_selectedExpiry) {
        case '+ 3 วัน':
          expiryDate = DateTime.now().add(const Duration(days: 3));
          break;
        case '+ 7 วัน':
          expiryDate = DateTime.now().add(const Duration(days: 7));
          break;
        case '+ 14 วัน':
          expiryDate = DateTime.now().add(const Duration(days: 14));
          break;
        case 'กำหนดเอง':
          expiryDate = _customExpiryDate;
          break;
      }

      final normalizedName = _nameController.text.trim();
      final normalizedUnit = Units.safe(_selectedUnit);
      final normalizedCategory = _selectedCategory!;

      final data = <String, dynamic>{
        'name': normalizedName,
        'quantity': _quantity,
        'unit': normalizedUnit,
        'category': normalizedCategory,
        'expiry_date': expiryDate != null
            ? Timestamp.fromDate(expiryDate)
            : null,
        'price': _priceController.text.isNotEmpty
            ? double.tryParse(_priceController.text)
            : null,
        'notes': _notesController.text.trim(),
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'user_id': user.uid,
        'imageUrl': '',
        // keys for grouping/search
        'name_key': normalizedName.toLowerCase(),
        'unit_key': normalizedUnit.toLowerCase(),
        'category_key': normalizedCategory.toLowerCase(),
      };
      if (widget.scannedBarcode != null) {
        data['barcode'] = widget.scannedBarcode!;
      }
      if (_brandController.text.trim().isNotEmpty) {
        data['brand'] = _brandController.text.trim();
      }

      // เขียนจริง
      final ref = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .doc();
      await ref.set(data);

      // cache ชื่อให้แนะนำได้เร็ว
      if (!_recentMaterials.contains(normalizedName)) {
        _recentMaterials.insert(0, normalizedName);
      }

      _toastOk('เพิ่มวัตถุดิบเรียบร้อย');
      if (mounted) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) Navigator.pop(context, true);
        });
      }
    } catch (e) {
      _toastError('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toastError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _toastOk(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _customExpiryDate = picked;
        _selectedExpiry = 'กำหนดเอง';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'เพิ่มวัตถุดิบ',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (widget.scannedBarcode != null)
              _bannerBarcode(widget.scannedProductData != null),
            const SizedBox(height: 20),

            // ชื่อ + แนะนำแบบกรอง
            _fieldNameWithSuggestions(),
            const SizedBox(height: 16),

            // หมวดหมู่
            _dropdownCategory(),
            const SizedBox(height: 24),

            // ส่วนรายละเอียด
            _sectionTitle('รายละเอียดวัตถุดิบ'),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(flex: 2, child: _quantityControls()),
                const SizedBox(width: 12),
                Expanded(child: _dropdownUnit()),
              ],
            ),
            const SizedBox(height: 16),

            _priceField(),
            const SizedBox(height: 24),

            // วันหมดอายุ
            _sectionTitle('วันหมดอายุ'),
            const SizedBox(height: 12),
            _expiryOptions(),
            const SizedBox(height: 24),

            if (widget.scannedBarcode != null) ...[
              _sectionTitle('ข้อมูลเพิ่มเติม'),
              const SizedBox(height: 12),
              _extraInfo(),
              const SizedBox(height: 16),
            ],

            // หมายเหตุ (เตี้ยลง)
            _notesField(),
            const SizedBox(height: 28),

            // ปุ่มบันทึก
            _submitButton(),
          ],
        ),
      ),
    );
  }

  // ===== UI Blocks =====

  Widget _bannerBarcode(bool found) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: found ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (found ? Colors.green[200] : Colors.grey[300])!,
        ),
      ),
      child: Text(
        found ? 'พบข้อมูลจากบาร์โค้ดในระบบ' : 'ไม่พบข้อมูลบาร์โค้ดในระบบ',
        style: TextStyle(
          color: found ? Colors.green[800] : Colors.grey[700],
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _fieldNameWithSuggestions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ช่องชื่อ
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _greyBorder),
          ),
          child: TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.black, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'ชื่อวัตถุดิบ',
              hintStyle: TextStyle(color: _hintGrey),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
          ),
        ),
        // ชิพแนะนำ (เทา) — แสดงเมื่อมีข้อความและมีผลลัพธ์
        if (_nameSuggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _nameSuggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              itemBuilder: (_, i) {
                final s = _nameSuggestions[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _nameController.text = s),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _chipGreyBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      s,
                      style: TextStyle(
                        color: _chipGreyText,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _dropdownCategory() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _greyBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCategory,
          isExpanded: true,
          hint: Text(
            'หมวดหมู่',
            style: TextStyle(color: _hintGrey, fontSize: 16),
          ),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
          dropdownColor: Colors.white,
          style: const TextStyle(color: Colors.black, fontSize: 16),
          items: _categories.map((cat) {
            return DropdownMenuItem<String>(
              value: cat,
              child: Row(
                children: [
                  Icon(
                    Categories.iconFor(cat),
                    size: 18,
                    color: Colors.grey[700],
                  ),
                  const SizedBox(width: 8),
                  Text(cat),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) => setState(() => _selectedCategory = v),
          menuMaxHeight: 300, // ทำให้เลื่อนดูได้
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: Colors.black,
        ),
      ),
    );
  }

  Widget _quantityControls() {
    return Row(
      children: [
        // −
        _squareGreyButton(
          onTap: () {
            if (_quantity > 1) {
              setState(() {
                _quantity--;
                _quantityController.text = _quantity.toString();
              });
            }
          },
          child: const Text(
            '−',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),

        // กล่องตัวเลข
        Expanded(
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _greyBorder),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '1',
                hintStyle: TextStyle(color: _hintGrey),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) {
                final x = int.tryParse(v);
                setState(() => _quantity = (x != null && x > 0) ? x : 1);
              },
            ),
          ),
        ),
        const SizedBox(width: 8),

        // +
        _squareGreyButton(
          onTap: () {
            setState(() {
              _quantity++;
              _quantityController.text = _quantity.toString();
            });
          },
          child: const Text(
            '+',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _squareGreyButton({
    required VoidCallback onTap,
    required Widget child,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Ink(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _dropdownUnit() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _greyBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: Units.isValid(_selectedUnit) ? _selectedUnit : Units.all.first,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
          dropdownColor: Colors.white,
          style: const TextStyle(color: Colors.black, fontSize: 16),
          items: Units.all.map((u) {
            return DropdownMenuItem<String>(
              value: u,
              child: Text(u, style: const TextStyle(color: Colors.black)),
            );
          }).toList(),
          onChanged: (v) => setState(() => _selectedUnit = Units.safe(v)),
          menuMaxHeight: 280, // เลื่อนดูได้
        ),
      ),
    );
  }

  Widget _priceField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _greyBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: _priceController,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.black, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'ราคาต่อหน่วย (ไม่บังคับ)',
          hintStyle: TextStyle(color: _hintGrey),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _expiryOptions() {
    Widget chip(String text, bool selected, VoidCallback onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? Colors.grey[300] : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _greyBorder, width: selected ? 2 : 1),
            ),
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            chip('+ 3 วัน', _selectedExpiry == '+ 3 วัน', () {
              setState(() {
                _selectedExpiry = '+ 3 วัน';
                _customExpiryDate = null;
              });
            }),
            const SizedBox(width: 12),
            chip('+ 7 วัน', _selectedExpiry == '+ 7 วัน', () {
              setState(() {
                _selectedExpiry = '+ 7 วัน';
                _customExpiryDate = null;
              });
            }),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            chip('+ 14 วัน', _selectedExpiry == '+ 14 วัน', () {
              setState(() {
                _selectedExpiry = '+ 14 วัน';
                _customExpiryDate = null;
              });
            }),
            const SizedBox(width: 12),
            chip(
              _customExpiryDate != null
                  ? '${_customExpiryDate!.day}/${_customExpiryDate!.month}/${_customExpiryDate!.year}'
                  : 'กำหนดเอง',
              _selectedExpiry == 'กำหนดเอง',
              _pickCustomDate,
            ),
          ],
        ),
      ],
    );
  }

  Widget _extraInfo() {
    return Column(
      children: [
        // บาร์โค้ด (อ่านอย่างเดียว)
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: TextField(
            controller: _barcodeController,
            style: const TextStyle(color: Colors.black, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'บาร์โค้ด',
              hintStyle: TextStyle(color: _hintGrey),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
            enabled: false,
          ),
        ),
        const SizedBox(height: 12),

        // ยี่ห้อ
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _greyBorder),
          ),
          child: TextField(
            controller: _brandController,
            style: const TextStyle(color: Colors.black, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'ยี่ห้อ (ไม่บังคับ)',
              hintStyle: TextStyle(color: _hintGrey),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _notesField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _greyBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: _notesController,
        maxLines: 2, // เตี้ยลง
        style: const TextStyle(color: Colors.black, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'หมายเหตุ (ไม่บังคับ)',
          hintStyle: TextStyle(color: _hintGrey),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _submitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _saveRawMaterial,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'บันทึก',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
      ),
    );
  }
}
