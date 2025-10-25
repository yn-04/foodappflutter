// lib/rawmaterial/addraw.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/constants/shelf_life.dart';
import 'package:my_app/rawmaterial/constants/units.dart';
import 'package:my_app/welcomeapp/home.dart';

class AddRawMaterialPage extends StatefulWidget {
  const AddRawMaterialPage({
    super.key,
    this.scannedBarcode,
    this.scannedProductData,
  });

  final String? scannedBarcode;
  final Map<String, dynamic>? scannedProductData;

  @override
  State<AddRawMaterialPage> createState() => _AddRawMaterialPageState();
}

class _AddRawMaterialPageState extends State<AddRawMaterialPage> {
  final _nameController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _notesController = TextEditingController();
  final _customExpiryTextController = TextEditingController();

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _isSaving = false;
  bool _dictionaryReady = false;
  bool _loadedFromHistory = false;

  int _quantity = 1;
  String _selectedUnit = Units.all.first;
  String? _selectedCategory;
  String? _selectedSubcategory;
  String _selectedExpiryMode = 'custom'; // room | fridge | freezer | custom

  Duration? _fridgeDuration;
  Duration? _freezerDuration;
  Duration? _roomDuration;
  DateTime? _customExpiryDate;
  String? _dateErrorText;

  bool _categoryLocked = false;
  bool _subcategoryLocked = false;
  bool _unitLocked = false;

  String? _lastAction;
  Timer? _hideActionTimer;

  final List<String> _recentMaterials = <String>[];
  final List<String> _nameSuggestions = <String>[];
  late final List<String> _dictionaryTerms;

  InputDecoration _softInput({
    String? label,
    String? hint,
    Widget? suffixIcon,
    String? errorText,
    EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 12,
    ),
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      isDense: true,
      contentPadding: contentPadding,
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[400]!, width: 1.2),
      ),
      suffixIcon: suffixIcon,
    );
  }

  @override
  void initState() {
    super.initState();
    _prepareDictionary();
    _loadRecentMaterials();
    _initializeWithScannedData();
    _nameController.addListener(_handleNameChanged);
  }

  @override
  void dispose() {
    _hideActionTimer?.cancel();
    _nameController.removeListener(_handleNameChanged);
    _nameController.dispose();
    _barcodeController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _notesController.dispose();
    _customExpiryTextController.dispose();
    super.dispose();
  }

  void _prepareDictionary() {
    _dictionaryTerms = ShelfLife.dictionaryTerms;
    _dictionaryReady = true;
  }

  Future<void> _loadRecentMaterials() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final snap = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .orderBy('created_at', descending: true)
          .limit(80)
          .get();

      final seen = <String>{};
      for (final doc in snap.docs) {
        final name = (doc.data()['name'] ?? '').toString().trim();
        if (name.isNotEmpty) seen.add(name);
      }
      _recentMaterials
        ..clear()
        ..addAll(seen);
      _recomputeNameSuggestions();
    } catch (_) {}
  }

  void _initializeWithScannedData() {
    if (widget.scannedBarcode != null && widget.scannedBarcode!.isNotEmpty) {
      _barcodeController.text = widget.scannedBarcode!;
    }

    final data = widget.scannedProductData;
    if (data == null) return;

    final name = (data['name'] ?? '').toString().trim();
    if (name.isNotEmpty) {
      _nameController.text = name;
    }

    // ✅ หมวดหมู่: ต้อง validate กับ Categories.list
    final normalized = Categories.normalize(data['category']);
    if (normalized.isNotEmpty && Categories.list.contains(normalized)) {
      _selectedCategory = normalized;
    } else {
      _selectedCategory = null; // ถ้าไม่ match, ปล่อยให้ผู้ใช้เลือกเอง
    }

    final unit = Units.safe(data['unit']);
    if (Units.isValid(unit)) {
      _selectedUnit = unit;
      _unitLocked = true;
    }

    final quantity = data['defaultQuantity'];
    if (quantity is num && quantity > 0) {
      _quantity = quantity.toInt();
      _quantityController.text = _quantity.toString();
    }

    final price = data['price'];
    if (price != null) {
      _priceController.text = price.toString();
    }

    _refreshStorageDurations();
  }

  void _handleNameChanged() {
    _recomputeNameSuggestions();

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _selectedCategory = null;
        _selectedSubcategory = null;
        _loadedFromHistory = false;
        _categoryLocked = false;
        _subcategoryLocked = false;
        _unitLocked = false;
        _customExpiryDate = null;
        _customExpiryTextController.clear();
        _dateErrorText = null;
      });
      _refreshStorageDurations();
      return;
    }

    _tryLoadLastUsed(name);
    _applyShelfLifeInference(name);
  }

  Future<void> _tryLoadLastUsed(String rawName) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final snap = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .where('name_key', isEqualTo: rawName.toLowerCase())
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        if (_loadedFromHistory) {
          setState(() => _loadedFromHistory = false);
        }
        return;
      }

      final data = snap.docs.first.data();
      setState(() {
        _loadedFromHistory = true;
        final category = (data['category'] ?? '').toString().trim();
        if (Categories.list.contains(category)) {
          _selectedCategory = category;
          _categoryLocked = true;
        }

        final subcategory = (data['subcategory'] ?? '').toString().trim();
        if (subcategory.isNotEmpty && _selectedCategory != null) {
          final subs = Categories.subcategoriesOf(_selectedCategory!);
          if (subs.contains(subcategory)) {
            _selectedSubcategory = subcategory;
            _subcategoryLocked = true;
          }
        }

        final storedUnit = Units.safe(data['unit']);
        if (Units.isValid(storedUnit)) {
          _selectedUnit = storedUnit;
          _unitLocked = true;
        }
      });
      _refreshStorageDurations();
    } catch (_) {}
  }

  void _applyShelfLifeInference(String name) {
    String? nextCategory = _selectedCategory;
    String? nextSubcategory = _selectedSubcategory;
    String nextUnit = _selectedUnit;
    bool categoryChanged = false;
    bool subcategoryChanged = false;
    bool unitChanged = false;

    final shelfSub = ShelfLife.subcategoryForItem(name);
    final shelfCategory = shelfSub != null
        ? Categories.categoryForSubcategory(shelfSub)
        : null;

    if (!_categoryLocked &&
        shelfCategory != null &&
        Categories.list.contains(shelfCategory)) {
      if (nextCategory != shelfCategory) {
        nextCategory = shelfCategory;
        categoryChanged = true;
      }
    }

    if (!_subcategoryLocked && shelfSub != null && nextCategory != null) {
      final subs = Categories.subcategoriesOf(nextCategory);
      if (subs.contains(shelfSub) && nextSubcategory != shelfSub) {
        nextSubcategory = shelfSub;
        subcategoryChanged = true;
      }
    }

    if ((!categoryChanged || nextSubcategory == null) && !_categoryLocked) {
      final detected = Categories.autoDetect(name);
      final detectedCategory = detected['category'];
      final detectedSub = detected['subcategory'];
      if (detectedCategory != null &&
          Categories.list.contains(detectedCategory)) {
        if (nextCategory != detectedCategory) {
          nextCategory = detectedCategory;
          categoryChanged = true;
        }
        if (!_subcategoryLocked && detectedSub != null) {
          final subs = Categories.subcategoriesOf(detectedCategory);
          if (subs.contains(detectedSub) && nextSubcategory != detectedSub) {
            nextSubcategory = detectedSub;
            subcategoryChanged = true;
          }
        }
      }
    }

    if (nextCategory != null && !_subcategoryLocked) {
      final subs = Categories.subcategoriesOf(nextCategory);
      if (nextSubcategory == null || !subs.contains(nextSubcategory)) {
        final fallback = Categories.defaultSubcategoryFor(nextCategory);
        if (fallback != null && fallback != nextSubcategory) {
          nextSubcategory = fallback;
          subcategoryChanged = true;
        }
      }
    }

    if (!_unitLocked) {
      final suggestedUnit = ShelfLife.defaultUnitForItem(name);
      if (suggestedUnit != null && Units.isValid(suggestedUnit)) {
        final safe = Units.safe(suggestedUnit);
        if (safe.isNotEmpty && safe != nextUnit) {
          nextUnit = safe;
          unitChanged = true;
        }
      }
    }

    if (categoryChanged || subcategoryChanged || unitChanged) {
      setState(() {
        if (categoryChanged) {
          _selectedCategory = nextCategory;
        }
        if (subcategoryChanged) {
          _selectedSubcategory = nextSubcategory;
        }
        if (unitChanged) {
          _selectedUnit = nextUnit;
        }
      });
      _refreshStorageDurations();

      // ข้อความแจ้งเตือนสั้น ๆ ทันสมัย
      if (categoryChanged || subcategoryChanged) {
        _showAction('กำหนดหมวดหมู่อัตโนมัติ');
      } else if (unitChanged) {
        _showAction('ปรับหน่วยอัตโนมัติเป็น $_selectedUnit');
      }
    } else {
      _refreshStorageDurations();
    }
  }

  void _refreshStorageDurations() {
    final sub =
        _selectedSubcategory ??
        Categories.defaultSubcategoryFor(_selectedCategory);
    _roomDuration = ShelfLife.forRoom(sub);
    _fridgeDuration = ShelfLife.forFridge(sub);
    _freezerDuration = ShelfLife.forFreezer(sub);

    if (_fridgeDuration == null &&
        _freezerDuration == null &&
        _roomDuration == null) {
      setState(() {
        _selectedExpiryMode = 'custom';
        _customExpiryDate = null;
        _customExpiryTextController.clear();
        _dateErrorText = null;
      });
      return;
    }

    // ถ้าโหมดที่เลือกอยู่ใช้ไม่ได้ ให้สลับให้เหมาะสม
    if (_selectedExpiryMode != 'custom') {
      if (_selectedExpiryMode == 'fridge' && _fridgeDuration == null) {
        setState(
          () => _selectedExpiryMode = _freezerDuration != null
              ? 'freezer'
              : (_roomDuration != null ? 'room' : 'custom'),
        );
      } else if (_selectedExpiryMode == 'freezer' && _freezerDuration == null) {
        setState(
          () => _selectedExpiryMode = _fridgeDuration != null
              ? 'fridge'
              : (_roomDuration != null ? 'room' : 'custom'),
        );
      } else if (_selectedExpiryMode == 'room' && _roomDuration == null) {
        setState(
          () => _selectedExpiryMode = _fridgeDuration != null
              ? 'fridge'
              : (_freezerDuration != null ? 'freezer' : 'custom'),
        );
      }
    }

    // 🆕 อัตโนมัติเลือกโหมดเมื่อเหลือตัวเลือกเดียว (เช่น น้ำมัน)
    _autoPickStorageMode();
  }

  void _autoPickStorageMode() {
    // ถ้า user ตั้ง custom เองแล้ว ไม่ไปยุ่ง
    if (_selectedExpiryMode == 'custom' && _customExpiryDate != null) return;

    // กรณีมีเฉพาะ room
    if (_roomDuration != null &&
        _fridgeDuration == null &&
        _freezerDuration == null) {
      setState(() => _selectedExpiryMode = 'room');
      _applyComputedExpiryFrom(_roomDuration);
      _showAction(
        'เลือกรูปแบบการเก็บ: อุณหภูมิห้อง · หมดอายุ ${_customExpiryDate != null ? _formatDate(_customExpiryDate!) : ''}',
      );
      return;
    }

    // กรณีมี Fridge อย่างเดียว
    if (_roomDuration == null &&
        _fridgeDuration != null &&
        _freezerDuration == null) {
      setState(() => _selectedExpiryMode = 'fridge');
      _applyComputedExpiryFrom(_fridgeDuration);
      _showAction(
        'เลือกรูปแบบการเก็บ: ตู้เย็น · หมดอายุ ${_customExpiryDate != null ? _formatDate(_customExpiryDate!) : ''}',
      );
      return;
    }

    // กรณีมี Freezer อย่างเดียว
    if (_roomDuration == null &&
        _fridgeDuration == null &&
        _freezerDuration != null) {
      setState(() => _selectedExpiryMode = 'freezer');
      _applyComputedExpiryFrom(_freezerDuration);
      _showAction(
        'เลือกรูปแบบการเก็บ: ช่องแช่แข็ง · หมดอายุ ${_customExpiryDate != null ? _formatDate(_customExpiryDate!) : ''}',
      );
      return;
    }
  }

  // ตัวช่วยคำนวณและอัปเดตช่อง Expiry
  void _applyComputedExpiryFrom(Duration? duration) {
    if (duration == null) return;
    final now = DateTime.now();
    final expiry = DateTime(now.year, now.month, now.day).add(duration);
    setState(() {
      _customExpiryDate = expiry;
      _customExpiryTextController.text = _formatDate(expiry);
      _dateErrorText = null;
    });
  }

  void _selectExpiryMode(String mode) {
    if (mode == _selectedExpiryMode) return;
    if (mode == 'room' && _roomDuration == null) return;
    if (mode == 'fridge' && _fridgeDuration == null) return;
    if (mode == 'freezer' && _freezerDuration == null) return;

    setState(() {
      _selectedExpiryMode = mode;
      if (mode == 'custom') {
        // เปิดให้กรอกเอง
        _dateErrorText = null;
      } else {
        // คิดวันหมดอายุอัตโนมัติ + เติมลงช่อง
        if (mode == 'room') _applyComputedExpiryFrom(_roomDuration);
        if (mode == 'fridge') _applyComputedExpiryFrom(_fridgeDuration);
        if (mode == 'freezer') _applyComputedExpiryFrom(_freezerDuration);
      }
    });

    // แสดง Action บอกผู้ใช้ว่าถูกเลือกแล้ว + วันหมดอายุคร่าว ๆ
    String label;
    switch (mode) {
      case 'room':
        label = 'อุณหภูมิห้อง';
        break;
      case 'fridge':
        label = 'ตู้เย็น';
        break;
      case 'freezer':
        label = 'ช่องแช่แข็ง';
        break;
      default:
        label = 'กำหนดเอง';
    }
    final dateText = _customExpiryDate != null
        ? ' · หมดอายุ ${_formatDate(_customExpiryDate!)}'
        : '';
    _showAction('เลือกรูปแบบการเก็บ: $label$dateText');
  }

  void _setCustomExpiry(DateTime date) {
    final formatted = _formatDate(date);
    setState(() {
      _customExpiryDate = DateTime(date.year, date.month, date.day);
      _customExpiryTextController.text = formatted;
      _selectedExpiryMode = 'custom';
      _dateErrorText = null;
    });
  }

  void _onCustomExpiryChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _customExpiryDate = null;
        _dateErrorText = null;
      });
      return;
    }
    final parsed = _parseDate(trimmed);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (parsed == null) {
      setState(() {
        _customExpiryDate = null;
        _dateErrorText = 'กำหนดวันหมดอายุเอง';
      });
      return;
    }
    if (parsed.isBefore(today)) {
      setState(() {
        _customExpiryDate = null;
        _dateErrorText = 'วันที่หมดอายุต้องเป็นอนาคต';
      });
      return;
    }
    setState(() {
      _customExpiryDate = parsed;
      _selectedExpiryMode = 'custom';
      _dateErrorText = null;
    });
  }

  void _recomputeNameSuggestions() {
    if (!_dictionaryReady) return;
    final query = _nameController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _nameSuggestions.clear());
      return;
    }

    final pool = <String>{..._recentMaterials, ..._dictionaryTerms};
    final startsWith = <String>[];
    final contains = <String>[];
    final fuzzy = <String>[];
    for (final candidate in pool) {
      final lower = candidate.toLowerCase();
      if (lower.startsWith(query)) {
        startsWith.add(candidate);
      } else if (lower.contains(query)) {
        contains.add(candidate);
      } else if (_similar(lower, query) >= 0.35) {
        fuzzy.add(candidate);
      }
    }

    final combined = <String>[...startsWith.take(6), ...contains.take(6)];
    for (final item in fuzzy) {
      if (combined.length >= 12) break;
      if (!combined.contains(item)) combined.add(item);
    }
    setState(() {
      _nameSuggestions
        ..clear()
        ..addAll(combined.take(12));
    });
  }

  double _similar(String a, String b) {
    Set<String> bigrams(String input) {
      final clean = input.replaceAll(RegExp(r"\s+"), '');
      final result = <String>{};
      for (var i = 0; i < clean.length - 1; i++) {
        result.add(clean.substring(i, i + 2));
      }
      return result;
    }

    final setA = bigrams(a);
    final setB = bigrams(b);
    if (setA.isEmpty || setB.isEmpty) return 0;
    final intersection = setA.intersection(setB).length.toDouble();
    final union = (setA.length + setB.length - intersection).toDouble();
    if (union == 0) return 0;
    return intersection / union;
  }

  void _showAction(String message) {
    _hideActionTimer?.cancel();
    setState(() => _lastAction = message);
    _hideActionTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() => _lastAction = null);
      }
    });
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final initial = _customExpiryDate ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: 'เลือกวันหมดอายุ',
    );
    if (picked != null) {
      _setCustomExpiry(picked);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnackBar('กรุณากรอกชื่อวัตถุดิบ');
      return;
    }
    if (_selectedCategory == null || _selectedCategory!.isEmpty) {
      _showSnackBar('กรุณาเลือกหมวดหมู่ของวัตถุดิบ');
      return;
    }
    if (_selectedSubcategory == null || _selectedSubcategory!.isEmpty) {
      _showSnackBar('กรุณาเลือกหมวดย่อย');
      return;
    }
    if (_quantity <= 0) {
      _showSnackBar('กรุณากรอกจำนวนที่ถูกต้อง (มากกว่า 0)');
      return;
    }
    if (!Units.isValid(_selectedUnit)) {
      _showSnackBar('กรุณาเลือกหน่วยให้ถูกต้อง');
      return;
    }

    if ((_roomDuration == null &&
            _fridgeDuration == null &&
            _freezerDuration == null) ||
        _selectedExpiryMode == 'custom') {
      _selectExpiryMode('custom');
      final text = _customExpiryTextController.text.trim();
      _onCustomExpiryChanged(text);
      if (_customExpiryDate == null || _dateErrorText != null) {
        _showSnackBar('กรุณากรอกวันที่หมดอายุให้ถูกต้อง');
        return;
      }
    } else if (_selectedExpiryMode == 'room' && _roomDuration == null) {
      _showSnackBar('ไม่มีข้อมูลอายุการเก็บรักษาที่อุณหภูมิห้อง');
      return;
    } else if (_selectedExpiryMode == 'fridge' && _fridgeDuration == null) {
      _showSnackBar('ไม่มีข้อมูลอายุการเก็บรักษาในตู้เย็น');
      return;
    } else if (_selectedExpiryMode == 'freezer' && _freezerDuration == null) {
      _showSnackBar('ไม่มีข้อมูลอายุการเก็บรักษาในช่องแช่แข็ง');
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      _showSnackBar('โปรดเข้าสู่ระบบก่อนบันทึกข้อมูล');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    try {
      DateTime? expiryDate;
      Duration? selectedDuration;
      switch (_selectedExpiryMode) {
        case 'room':
          selectedDuration = _roomDuration;
          break;
        case 'fridge':
          selectedDuration = _fridgeDuration;
          break;
        case 'freezer':
          selectedDuration = _freezerDuration;
          break;
        default:
          selectedDuration = null;
      }
      if (_selectedExpiryMode == 'custom') {
        expiryDate = _customExpiryDate;
      } else if (selectedDuration != null) {
        final now = DateTime.now();
        expiryDate = DateTime(
          now.year,
          now.month,
          now.day,
        ).add(selectedDuration);
        // ให้ field แสดงตรงกับที่จะบันทึก (กันหลุด)
        _customExpiryDate = expiryDate;
        _customExpiryTextController.text = _formatDate(expiryDate);
      }

      final now = DateTime.now();
      final priceText = _priceController.text.trim();
      double? price;
      if (priceText.isNotEmpty) {
        price = double.tryParse(priceText.replaceAll(',', ''));
      }

      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final rawUserData = userDoc.data();
      final familyIdValue =
          ((rawUserData?['familyId'] ?? rawUserData?['family_id']) as String?)
              ?.trim();
      final normalizedFamilyId =
          (familyIdValue != null && familyIdValue.isNotEmpty)
          ? familyIdValue
          : null;

      if (expiryDate == null) {
        _showSnackBar('กรุณาเลือกวันที่หมดอายุ');
        if (mounted) setState(() => _isSaving = false);
        return;
      }

      final doc = <String, dynamic>{
        'name': name,
        'name_key': name.toLowerCase(),
        'barcode': _barcodeController.text.trim(),
        'quantity': _quantity,
        'unit': _selectedUnit,
        'category': _selectedCategory,
        'subcategory': _selectedSubcategory,
        'storage_mode': _selectedExpiryMode == 'custom'
            ? null
            : _selectedExpiryMode,
        'expiry_mode': _selectedExpiryMode,
        'expiry_date': expiryDate.toIso8601String(),
        'recommended_fridge_days': _fridgeDuration?.inDays,
        'recommended_freezer_days': _freezerDuration?.inDays,
        'custom_expiry_input': _customExpiryTextController.text.trim(),
        'price': price,
        'notes': _notesController.text.trim(),
        'created_at': FieldValue.serverTimestamp(),
        'created_at_local': now.toIso8601String(),
        'ownerId': user.uid,
        if (normalizedFamilyId != null) 'familyId': normalizedFamilyId,
      };

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('raw_materials')
          .add(doc);

      if (!mounted) return;
      _showSnackBar('บันทึกสำเร็จ', success: true);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen(initialIndex: 1)),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('บันทึกไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildActionBanner() {
    if (_lastAction == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: Colors.black87),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _lastAction!,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _lastAction = null),
            icon: const Icon(Icons.close, size: 16, color: Colors.black54),
            splashRadius: 16,
          ),
        ],
      ),
    );
  }

  Widget _buildDetectStatus() {
    final nameFilled = _nameController.text.trim().isNotEmpty;
    String text;
    IconData icon;
    Color color;
    if (!nameFilled) {
      text = 'ยังไม่ได้กรอกชื่อวัตถุดิบ';
      icon = Icons.hourglass_empty;
      color = Colors.grey[700]!;
    } else if (!_categoryLocked || !_subcategoryLocked) {
      text = 'ระบบกำลังช่วยตรวจสอบหมวดหมู่';
      icon = Icons.lightbulb_outline;
      color = Colors.blue[700]!;
    } else {
      text = 'หมวดหมู่ถูกกำหนดแล้ว';
      icon = Icons.lock_outline;
      color = Colors.green[700]!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.sentences,
          decoration: _softInput(
            label: 'ชื่อวัตถุดิบ',
            hint: 'เช่น ไข่ไก่, แป้งสาลี',
          ),
        ),

        const SizedBox(height: 8),
        _buildDetectStatus(),
        if (_nameSuggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _nameSuggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final suggestion = _nameSuggestions[index];
                return ActionChip(
                  label: Text(suggestion),
                  onPressed: () {
                    _nameController.text = suggestion;
                    _nameController.selection = TextSelection.collapsed(
                      offset: suggestion.length,
                    );
                    _showAction('เลือก: $suggestion');
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryDropdown() {
    final items = Categories.list.toSet().toList()
      ..sort((a, b) => a.compareTo(b));
    final String? safeValue =
        (_selectedCategory != null &&
            Categories.list.contains(_selectedCategory))
        ? _selectedCategory
        : null;

    return SizedBox(
      width: double.infinity, // 👈 กว้างเท่าช่องกรอกอื่น
      child: DropdownButtonFormField<String>(
        value: safeValue,
        isExpanded: true,
        menuMaxHeight: 320,
        borderRadius: BorderRadius.circular(16),
        decoration: _softInput(label: 'หมวดหมู่'),
        icon: const Icon(Icons.arrow_drop_down),

        // แสดงไอคอนบนค่าที่เลือก (ในช่อง)
        selectedItemBuilder: (context) {
          return items.map((cat) {
            final icon = Categories.iconFor(cat);
            final color = Categories.colorFor(cat);
            return Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Flexible(child: Text(cat, overflow: TextOverflow.ellipsis)),
              ],
            );
          }).toList();
        },

        // รายการในเมนู
        items: items.map((cat) {
          final icon = Categories.iconFor(cat);
          final color = Categories.colorFor(cat);
          return DropdownMenuItem<String>(
            value: cat,
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(cat, overflow: TextOverflow.ellipsis)),
              ],
            ),
          );
        }).toList(),

        onChanged: (value) {
          setState(() {
            _selectedCategory = value;
            _categoryLocked = true;
            _subcategoryLocked = false;

            final subs = value == null
                ? const <String>[]
                : Categories.subcategoriesOf(value);
            if (!subs.contains(_selectedSubcategory)) {
              _selectedSubcategory = Categories.defaultSubcategoryFor(value);
            }
          });
          _refreshStorageDurations();
          _showAction('ตั้งค่าหมวดหมู่');
        },
      ),
    );
  }

  Widget _buildSubcategoryDropdown() {
    final subs = _selectedCategory == null
        ? const <String>[]
        : Categories.subcategoriesOf(_selectedCategory!);

    return SizedBox(
      width: double.infinity, // 👈 กว้างเต็ม
      child: DropdownButtonFormField<String>(
        value: subs.contains(_selectedSubcategory)
            ? _selectedSubcategory
            : null,
        isExpanded: true,
        menuMaxHeight: 320,
        borderRadius: BorderRadius.circular(16),
        decoration: _softInput(label: 'หมวดย่อย'),
        icon: const Icon(Icons.arrow_drop_down),

        items: subs.map((sub) {
          // ใส่ไอคอนหมวดหลักให้รองรับภาพรวมสวยๆ (optional)
          final parentIcon = Categories.iconFor(_selectedCategory ?? '');
          return DropdownMenuItem<String>(
            value: sub,
            child: Row(
              children: [
                Icon(parentIcon, size: 16, color: Colors.black54),
                const SizedBox(width: 8),
                Expanded(child: Text(sub, overflow: TextOverflow.ellipsis)),
              ],
            ),
          );
        }).toList(),

        onChanged: (value) {
          setState(() {
            _selectedSubcategory = value;
            _subcategoryLocked = true;
          });
          _refreshStorageDurations();
          _showAction('ตั้งค่าหมวดย่อย');
        },
      ),
    );
  }

  Widget _iconOnlyButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: () {
        FocusScope.of(context).unfocus();
        onTap();
      },
      icon: Icon(icon, size: 18, color: Colors.black), // ไอคอนล้วน ๆ
      padding: EdgeInsets.zero,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      constraints: const BoxConstraints.tightFor(
        width: 32,
        height: 32,
      ), // เล็กมาก
      splashRadius: 18, // ripple เล็กพอดีมือ
    );
  }

  // 1) ปรับปุ่มให้กำหนดขนาดได้ (เล็กลงได้)

  Widget _buildStorageButtons() {
    if (_roomDuration == null &&
        _fridgeDuration == null &&
        _freezerDuration == null) {
      return const SizedBox.shrink();
    }

    final width = MediaQuery.of(context).size.width;
    // กว้างขั้นต่ำของแต่ละการ์ด ~ครึ่งจอ (ลบเผื่อช่องว่าง) และไม่เล็กเกิน 150
    final cardMinWidth = width >= 360
        ? (width - 16 - 16 - 12) / 2
        : width - 16 - 16;

    final children = <Widget>[
      if (_roomDuration != null)
        _storageButton(
          mode: 'room',
          label: 'อุณหภูมิห้อง',
          duration: _roomDuration!,
          icon: Icons.home_outlined,
          minWidth: cardMinWidth,
        ),
      if (_fridgeDuration != null)
        _storageButton(
          mode: 'fridge',
          label: 'ตู้เย็น',
          duration: _fridgeDuration!,
          icon: Icons.kitchen_outlined,
          minWidth: cardMinWidth,
        ),
      if (_freezerDuration != null)
        _storageButton(
          mode: 'freezer',
          label: 'ช่องแช่แข็ง',
          duration: _freezerDuration!,
          icon: Icons.ac_unit_outlined,
          minWidth: cardMinWidth,
        ),
    ];

    return Wrap(spacing: 12, runSpacing: 12, children: children);
  }

  Widget _storageButton({
    required String mode,
    required String label,
    required Duration duration,
    required IconData icon,
    required double minWidth,
  }) {
    final selected = _selectedExpiryMode == mode;
    final days = duration.inDays;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minWidth.clamp(150, double.infinity),
      ),
      child: InkWell(
        onTap: () => _selectExpiryMode(mode),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.grey[200],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.black : Colors.grey[400]!,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      offset: const Offset(0, 3),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: Colors.black),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '~ $days วัน',
                      style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle, size: 18, color: Colors.black87),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomExpiryField() {
    return TextField(
      controller: _customExpiryTextController,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9/]')),
        _DdMmYyyyFormatter(),
      ],
      decoration: _softInput(
        label: 'วันหมดอายุ (วว/ดด/ปปปป)',
        hint: 'เช่น 25/12/2025',
        errorText: _dateErrorText,
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () {
            _selectExpiryMode('custom');
            _pickCustomDate();
          },
        ),
      ),
      onTap: () => _selectExpiryMode('custom'),
      onChanged: _onCustomExpiryChanged,
    );
  }

  Widget _buildSection({
    required String title,
    IconData? icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: Colors.grey[800]),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool success = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: success ? Colors.green[600] : Colors.redAccent,
      ),
    );
  }

  DateTime? _parseDate(String input) {
    final parts = input.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (year < 1900) return null;
    if (month < 1 || month > 12) return null;
    final date = DateTime(year, month, day);
    if (date.day != day || date.month != month || date.year != year)
      return null;
    return date;
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('เพิ่มวัตถุดิบ'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        centerTitle: true,
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'บันทึกวัตถุดิบ',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior
            .deferToChild, // ✅ ให้ลูก (เช่น ปุ่ม) ได้ gesture ก่อน
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            if (widget.scannedBarcode != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueGrey[100]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'บาร์โค้ดที่สแกน: ${widget.scannedBarcode}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            _buildActionBanner(),
            const SizedBox(height: 16),
            _buildSection(
              title: 'ข้อมูลวัตถุดิบ',
              icon: Icons.inventory_2_outlined,
              children: [
                _buildNameField(),
                const SizedBox(height: 16),
                _buildCategoryDropdown(),
                const SizedBox(height: 12),
                _buildSubcategoryDropdown(),
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: 'ปริมาณวัตถุดิบ',
              icon: Icons.scale_outlined,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[300]!, width: 1),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _iconOnlyButton(
                        icon: Icons.remove,
                        onTap: () {
                          if (_quantity <= 1) return;
                          setState(() {
                            _quantity -= 1;
                            _quantityController.text = _quantity.toString();
                          });
                          _showAction('จำนวน: $_quantity');
                        },
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 110, // 👈 ช่องกว้างขึ้น ใส่หลายหลักได้สบาย
                        child: TextField(
                          controller: _quantityController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: _softInput(
                            hint: '1',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          onChanged: (value) {
                            final n = int.tryParse(value);
                            setState(
                              () => _quantity = (n == null || n <= 0) ? 1 : n,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      _iconOnlyButton(
                        icon: Icons.add,
                        onTap: () {
                          setState(() {
                            _quantity += 1;
                            _quantityController.text = _quantity.toString();
                          });
                          _showAction('จำนวน: $_quantity');
                        },
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 120,
                        child: DropdownButtonFormField<String>(
                          value: Units.isValid(_selectedUnit)
                              ? _selectedUnit
                              : Units.all.first,
                          isExpanded: true,
                          decoration: _softInput(), // << กรอบมนอ่อน
                          items: Units.all
                              .map(
                                (u) =>
                                    DropdownMenuItem(value: u, child: Text(u)),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedUnit = Units.safe(value);
                              _unitLocked = true;
                            });
                            _showAction('หน่วย: $_selectedUnit');
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: 'วิธีเก็บรักษา / วันหมดอายุ',
              icon: Icons.ac_unit_outlined,
              children: [
                _buildStorageButtons(),
                if (_fridgeDuration != null || _freezerDuration != null)
                  const SizedBox(height: 12),
                _buildCustomExpiryField(),
              ],
            ),
            const SizedBox(height: 16),
            _buildSection(
              title: 'ราคาและหมายเหตุเพิ่มเติม',
              icon: Icons.note_alt_outlined,
              children: [
                TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _softInput(
                    label: 'ราคา (บาท)',
                    hint: 'เช่น 45.50',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notesController,
                  maxLines: 1,
                  decoration: _softInput(
                    label: 'หมายเหตุ',
                    hint: 'รายละเอียดเพิ่มเติม (ถ้ามี)',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _DdMmYyyyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length > 8) digitsOnly = digitsOnly.substring(0, 8);

    final buffer = StringBuffer();
    for (var i = 0; i < digitsOnly.length; i++) {
      buffer.write(digitsOnly[i]);
      if (i == 1 || i == 3) {
        if (i != digitsOnly.length - 1) buffer.write('/');
      }
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
