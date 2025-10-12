// lib/profile/health_info_screen.dart — Health Info (Modern UI + Always Editable + BMI no-overflow + Allergy suggestions
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_app/profile/model/my_user.dart';
import 'package:my_app/services/firebase_storage_service.dart';

class HealthInfoScreen extends StatefulWidget {
  const HealthInfoScreen({super.key});

  @override
  State<HealthInfoScreen> createState() => _HealthInfoScreenState();
}

class _HealthInfoScreenState extends State<HealthInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final User? _user = FirebaseAuth.instance.currentUser;

  bool _isLoading = true;
  bool _isSaving = false;

  MyUser? _currentUser;
  Map<String, dynamic>? _additionalHealthData;

  final TextEditingController _displayNameController = TextEditingController();
  File? _selectedProfileImage;
  String? _currentPhotoUrl;
  final ImagePicker _imagePicker = ImagePicker();

  // ---- Base controllers ----
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();

  // allergies moved into diet section
  final TextEditingController _allergiesController = TextEditingController();

  // ---- Diet multi-select + per-meal min/max (g) ----
  static const List<_DietChoice> _dietChoices = [
    _DietChoice(key: 'low_fat', label: 'Low-fat'),
    _DietChoice(key: 'low_carb', label: 'Low-carb'),
    _DietChoice(key: 'high_protein', label: 'High-protein'),
    _DietChoice(key: 'gluten_free', label: 'Gluten-free'),
    _DietChoice(key: 'dairy_free', label: 'Dairy-free'),
    _DietChoice(key: 'ketogenic', label: 'Ketogenic'),
    _DietChoice(key: 'paleo', label: 'Paleo'),
    _DietChoice(key: 'lacto_vegetarian', label: 'Lacto-vegetarian'),
    _DietChoice(key: 'ovo_vegetarian', label: 'Ovo-vegetarian'),
    _DietChoice(key: 'vegan', label: 'Vegan'),
    _DietChoice(key: 'vegetarian', label: 'Vegetarian'),
  ];

  static const Map<String, _NutrientMeta> _dietToNutrient = {
    'low_fat': _NutrientMeta(nutrientKey: 'fat', display: 'ไขมัน', unit: 'g'),
    'low_carb': _NutrientMeta(
      nutrientKey: 'คาร์โบไฮเดรต',
      display: 'คาร์โบไฮเดรต',
      unit: 'g',
    ),
    'high_protein': _NutrientMeta(
      nutrientKey: 'โปรตีน',
      display: 'โปรตีน',
      unit: 'g',
    ),
  };

  final Set<String> _selectedDietKeys = {};
  final Map<String, TextEditingController> _minControllers = {};
  final Map<String, TextEditingController> _maxControllers = {};

  // ---- Allergy suggestion state ----
  // ดิกชันนารี “อาหารที่แพ้” ที่พบบ่อย (เพิ่ม/ลดได้)
  static const List<String> _allergenDict = [
    'กุ้ง',
    'ปู',
    'ปลา',
    'หอย',
    'ปลาหมึก',
    'ไข่ไก่',
    'นมวัว',
    'ถั่วลิสง',
    'ถั่วเหลือง',
    'อัลมอนด์',
    'วอลนัต',
    'เม็ดมะม่วงหิมพานต์',
    'งา',
    'แป้งสาลี',
    'กลูเตน',
    'สตรอว์เบอร์รี',
    'กล้วย',
    'สับปะรด',
    'มะเขือเทศ',
  ];
  List<String> _allergySuggestions = <String>[];
  String? _lastMispelledToken;

  @override
  void initState() {
    super.initState();
    _loadHealthData();
    _allergiesController.addListener(_handleAllergyTyping);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _allergiesController.removeListener(_handleAllergyTyping);
    _allergiesController.dispose();
    for (final c in _minControllers.values) c.dispose();
    for (final c in _maxControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadHealthData() async {
    if (_user == null) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() => _isLoading = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user.uid)
          .get();

      MyUser? currentUser;
      Map<String, dynamic>? extras;

      if (doc.exists) {
        currentUser = MyUser.fromFirestore(doc);
        final data = doc.data();
        final rawExtras = data?['healthProfile'];
        if (rawExtras is Map<String, dynamic>) {
          extras = Map<String, dynamic>.from(rawExtras);
        }
      }

      // legacy collection support
      if (extras == null || extras.isEmpty) {
        final legacyDoc = await FirebaseFirestore.instance
            .collection('health_profiles')
            .doc(_user.uid)
            .get();
        if (legacyDoc.exists) extras = legacyDoc.data();
      }

      if (!mounted) return;

      final authUser = FirebaseAuth.instance.currentUser;
      setState(() {
        _currentUser = currentUser;
        _additionalHealthData = extras == null || extras.isEmpty
            ? null
            : Map<String, dynamic>.from(extras);
        _currentPhotoUrl = authUser?.photoURL;
        final resolvedName =
            currentUser?.displayName ?? authUser?.displayName ?? '';
        _displayNameController.text = resolvedName;
      });

      _populateBase();
      _populateDiet();
    } catch (_) {
      if (!mounted) return;
      _showSnackBar('โหลดข้อมูลไม่สำเร็จ', success: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateBase() {
    final displayName = _currentUser?.displayName ?? (_user?.displayName ?? '');
    if (_displayNameController.text.trim() != displayName.trim()) {
      _displayNameController.text = displayName;
    }

    final h = _currentUser?.height ?? 0;
    final w = _currentUser?.weight ?? 0;
    _heightController.text = h > 0 ? h.toStringAsFixed(0) : '';
    _weightController.text = w > 0 ? w.toStringAsFixed(1) : '';

    final extras = _additionalHealthData ?? const {};
    final allergies = extras['allergies'];
    if (allergies is String) {
      _allergiesController.text = allergies;
    } else if (allergies is List) {
      _allergiesController.text = allergies.whereType<String>().join(', ');
    } else {
      _allergiesController.text = '';
    }
  }

  void _populateDiet() {
    final extras = _additionalHealthData ?? const {};
    final diets = extras['dietPreferences'];
    _selectedDietKeys
      ..clear()
      ..addAll(diets is List ? diets.whereType<String>() : const []);

    // init min/max controllers
    for (final k in _dietToNutrient.keys) {
      _minControllers.putIfAbsent(k, () => TextEditingController());
      _maxControllers.putIfAbsent(k, () => TextEditingController());
      _minControllers[k]!.clear();
      _maxControllers[k]!.clear();
    }

    final perMeal = extras['nutritionTargetsPerMeal'];
    if (perMeal is Map) {
      perMeal.forEach((nutrientKey, val) {
        if (val is Map) {
          final dietKey = _dietToNutrient.entries
              .firstWhere(
                (e) => e.value.nutrientKey == nutrientKey,
                orElse: () => const MapEntry(
                  '',
                  _NutrientMeta(nutrientKey: '', display: '', unit: ''),
                ),
              )
              .key;
          if (dietKey.isNotEmpty) {
            final mn = (val['min'] is num)
                ? (val['min'] as num).toDouble()
                : null;
            final mx = (val['max'] is num)
                ? (val['max'] as num).toDouble()
                : null;
            if (mn != null) _minControllers[dietKey]!.text = _fmt(mn);
            if (mx != null) _maxControllers[dietKey]!.text = _fmt(mx);
          }
        }
      });
    }
  }

  // ------- Computations -------
  double? _bmi() {
    final h = double.tryParse(_heightController.text.trim());
    final w = double.tryParse(_weightController.text.trim());
    if (h == null || w == null || h <= 0) return null;
    final m = h / 100;
    return w / (m * m);
  }

  Color _bmiColor(double bmi) {
    if (bmi < 18.5) return Colors.blue;
    if (bmi < 25) return Colors.green;
    if (bmi < 30) return Colors.orange;
    return Colors.red;
  }

  String _bmiAdvice(double bmi) {
    if (bmi < 18.5) return 'น้ำหนักน้อย: เพิ่มพลังงานและโปรตีนให้เพียงพอ';
    if (bmi < 25) return 'ปกติ: รักษาพฤติกรรมการกินและการออกกำลังกาย';
    if (bmi < 30) return 'น้ำหนักเกิน: คุมแคลอรี ออกกำลังกายสม่ำเสมอ';
    return 'อ้วน: ปรึกษาแพทย์/นักกำหนดอาหารวางแผนที่เหมาะสม';
  }

  // ------- Save -------
  Future<void> _save() async {
    final user = _user;
    final base = _currentUser;
    if (user == null || base == null) return;
    if (!_formKey.currentState!.validate()) return;

    final displayName = _displayNameController.text.trim();
    final nameChanged = displayName != base.displayName;
    final imageChanged = _selectedProfileImage != null;

    final h = double.tryParse(_heightController.text.trim()) ?? 0;
    final w = double.tryParse(_weightController.text.trim()) ?? 0;

    final profile = <String, dynamic>{};

    // allergies
    final allergies = _allergiesController.text.trim();
    if (allergies.isNotEmpty) profile['allergies'] = allergies;

    // dietPreferences
    if (_selectedDietKeys.isNotEmpty) {
      profile['dietPreferences'] = _selectedDietKeys.toList();
    }

    // nutritionTargetsPerMeal (only for special diets that have values)
    final targets = <String, dynamic>{};
    for (final k in _selectedDietKeys.where(_dietToNutrient.containsKey)) {
      final meta = _dietToNutrient[k]!;
      final mnStr = _minControllers[k]!.text.trim();
      final mxStr = _maxControllers[k]!.text.trim();
      final mn = mnStr.isEmpty ? null : double.tryParse(mnStr);
      final mx = mxStr.isEmpty ? null : double.tryParse(mxStr);
      if (mn != null || mx != null) {
        if (mn != null && mx != null && mn > mx) {
          _showSnackBar(
            'ขั้นต่ำของ ${meta.display} ต้องไม่มากกว่าขั้นสูง',
            success: false,
          );
          return;
        }
        targets[meta.nutrientKey] = {
          if (mn != null) 'min': mn,
          if (mx != null) 'max': mx,
          'unit': meta.unit,
        };
      }
    }
    if (targets.isNotEmpty) profile['nutritionTargetsPerMeal'] = targets;

    setState(() => _isSaving = true);
    var updatedModel = base;
    String? nextPhotoUrl = _currentPhotoUrl;
    final shouldUpdateProfileBasics = nameChanged || imageChanged;

    try {
      if (shouldUpdateProfileBasics) {
        try {
          if (imageChanged) {
            await FirebaseStorageService.updateCompleteProfile(
              displayName: displayName,
              imageFile: _selectedProfileImage,
            );
          } else {
            await FirebaseStorageService.updateUserProfile(
              displayName: displayName,
            );
          }
          await FirebaseAuth.instance.currentUser?.reload();
          final refreshedUser = FirebaseAuth.instance.currentUser;
          nextPhotoUrl = refreshedUser?.photoURL;
          updatedModel = updatedModel.copyWith(displayName: displayName);
        } catch (e) {
          if (!mounted) return;
          _showSnackBar('อัปเดตชื่อหรือรูปภาพไม่สำเร็จ: $e', success: false);
          return;
        }
      }

      final updates = <String, dynamic>{'height': h, 'weight': w};
      if (profile.isEmpty) {
        updates['healthProfile'] = FieldValue.delete();
      } else {
        updates['healthProfile'] = profile;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update(updates);

      if (!mounted) return;
      setState(() {
        _currentUser = updatedModel.copyWith(
          height: h,
          weight: w,
          allergies: allergies,
        );
        _additionalHealthData = profile.isEmpty
            ? null
            : Map<String, dynamic>.from(profile);
        _currentPhotoUrl = nextPhotoUrl;
        if (shouldUpdateProfileBasics) {
          _selectedProfileImage = null;
          _displayNameController.text = updatedModel.displayName;
        }
      });
      _showSnackBar('บันทึกข้อมูลสำเร็จ');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('บันทึกล้มเหลว: $e', success: false);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showImagePickerSheet() {
    if (_isSaving) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('ถ่ายรูปใหม่'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _pickProfileImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกรูปจากแกลเลอรี่'),
              onTap: () async {
                Navigator.of(ctx).pop();
                await _pickProfileImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickProfileImage(ImageSource source) async {
    if (_isSaving) return;
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          _selectedProfileImage = File(picked.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('ไม่สามารถเลือกรูปภาพได้: $e', success: false);
    }
  }

  Widget _buildProfileSection() {
    ImageProvider<Object>? imageProvider;
    if (_selectedProfileImage != null) {
      imageProvider = FileImage(_selectedProfileImage!);
    } else if (_currentPhotoUrl != null && _currentPhotoUrl!.isNotEmpty) {
      imageProvider = NetworkImage(_currentPhotoUrl!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: const Color(0xFFE5E6EB),
                  backgroundImage: imageProvider,
                  child: imageProvider == null
                      ? const Icon(Icons.person, size: 42, color: Colors.white)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _isSaving ? null : _showImagePickerSheet,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _isSaving ? Colors.grey[400] : Colors.black87,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.edit,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 18),
            Expanded(
              child: TextFormField(
                controller: _displayNameController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อที่ต้องการแสดง',
                  hintText: 'เช่น Nina',
                ),
                enabled: !_isSaving,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: _displayNameValidator,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                textInputAction: TextInputAction.next,
              ),
            ),
          ],
        ),
        if (_selectedProfileImage != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _isSaving
                  ? null
                  : () {
                      setState(() {
                        _selectedProfileImage = null;
                      });
                    },
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('ยกเลิกรูปภาพที่เลือก'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'ชื่อและรูปภาพของคุณจะแสดงกับสมาชิกครอบครัวและการแนะนำอาหาร',
          style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
        ),
      ],
    );
  }

  // ------- UI -------
  @override
  Widget build(BuildContext context) {
    final bg = const Color(0xFFF7F7F9);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'ข้อมูลสุขภาพ',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _ModernCard(
                    title: 'โปรไฟล์ผู้ใช้',
                    icon: Icons.person_outline,
                    child: _buildProfileSection(),
                  ),
                  const SizedBox(height: 16),
                  _ModernCard(
                    title: 'ดัชนีมวลกาย (BMI)',
                    icon: Icons.health_and_safety,
                    child: _buildBmiContentNoOverflow(),
                    color: Colors.black87,
                  ),
                  const SizedBox(height: 16),
                  _ModernCard(
                    title: 'ข้อมูลร่างกาย',
                    icon: Icons.accessibility_new,
                    child: Column(
                      children: [
                        _filledField(
                          controller: _heightController,
                          label: 'ส่วนสูง (ซม.)',
                          hint: 'เช่น 165',
                          keyboardType: TextInputType.number,
                          validator: _numberOrEmptyValidator,
                        ),
                        const SizedBox(height: 12),
                        _filledField(
                          controller: _weightController,
                          label: 'น้ำหนัก (กก.)',
                          hint: 'เช่น 54.5',
                          keyboardType: TextInputType.number,
                          validator: _numberOrEmptyValidator,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _ModernCard(
                    title: 'ข้อจำกัดด้านอาหาร',
                    icon: Icons.restaurant_menu,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _filledField(
                          controller: _allergiesController,
                          label: 'อาหารที่แพ้',
                          hint: 'เช่น กุ้ง, ถั่วลิสง (คั่นด้วย , )',
                          maxLines: 2,
                        ),
                        // --- แนะนำการสะกดที่น่าจะตั้งใจ ---
                        if (_allergySuggestions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'ตั้งใจพิมพ์แบบนี้หรือไม่?',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _allergySuggestions.map((s) {
                              return ActionChip(
                                label: Text(s),
                                onPressed: () => _applyAllergySuggestion(s),
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'เลือกเงื่อนไข/รูปแบบการกิน',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _dietChoices.map((c) {
                            final selected = _selectedDietKeys.contains(c.key);
                            return FilterChip(
                              label: Text(c.label),
                              selected: selected,
                              onSelected: (v) {
                                setState(() {
                                  if (v) {
                                    _selectedDietKeys.add(c.key);
                                  } else {
                                    _selectedDietKeys.remove(c.key);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        ..._selectedDietKeys
                            .where(_dietToNutrient.containsKey)
                            .map((dietKey) => _perMealGroup(dietKey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: const Text(
                        'บันทึกข้อมูล',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ---------- BMI: no overflow ----------
  Widget _buildBmiContentNoOverflow() {
    final bmi = _bmi();
    final color = bmi == null ? Colors.blueGrey : _bmiColor(bmi);
    final advice = bmi == null ? 'กรอกส่วนสูง/น้ำหนัก' : _bmiAdvice(bmi);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // ค่าตัวเลข BMI ใหญ่ ชัดเจน
            Expanded(
              flex: 4,
              child: Text(
                bmi == null ? '—' : bmi.toStringAsFixed(1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // กล่องคำแนะนำ ให้ยืดหยุ่นและตัดคำ/ตัดบรรทัด
            Flexible(
              flex: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  advice,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'ระบบจะใช้ BMI และข้อจำกัดด้านอาหารเพื่อช่วยกรองเมนู/แผนโภชนาการให้เหมาะสม',
          style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _perMealGroup(String dietKey) {
    final meta = _dietToNutrient[dietKey]!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${meta.display} ต่อมื้อ (${meta.unit})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _filledField(
                  controller: _minControllers[dietKey]!,
                  label: 'ขั้นต่ำ',
                  hint: 'เช่น 0',
                  keyboardType: TextInputType.number,
                  validator: _minMaxAllowEmptyValidator,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _filledField(
                  controller: _maxControllers[dietKey]!,
                  label: 'ขั้นสูง',
                  hint: 'เช่น 25',
                  keyboardType: TextInputType.number,
                  validator: _minMaxAllowEmptyValidator,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- small widgets helpers ----
  Widget _filledField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF1F2F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }

  // ---- validators ----
  String? _displayNameValidator(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'กรุณากรอกชื่อที่ต้องการแสดง';
    if (trimmed.contains(RegExp(r'\s'))) {
      return 'กรุณากรอกชื่อที่ติดกันไม่เว้นวรรค';
    }
    if (trimmed.length < 2) return 'กรุณากรอกชื่ออย่างน้อย 2 ตัวอักษร';
    return null;
  }

  String? _numberOrEmptyValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final d = double.tryParse(value.trim());
    if (d == null || d <= 0) return 'กรุณากรอกตัวเลขที่ถูกต้อง (> 0)';
    return null;
  }

  String? _minMaxAllowEmptyValidator(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final d = double.tryParse(value.trim());
    if (d == null || d < 0) return 'ต้องเป็นตัวเลข ≥ 0';
    return null;
  }

  // ---- Allergy suggestion logic ----
  void _handleAllergyTyping() {
    final text = _allergiesController.text;
    // แยกเป็น token ตามคอมมา/ช่องว่าง
    final tokens = text
        .split(RegExp(r'[,\n]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    if (tokens.isEmpty) {
      if (_allergySuggestions.isNotEmpty || _lastMispelledToken != null) {
        setState(() {
          _allergySuggestions = [];
          _lastMispelledToken = null;
        });
      }
      return;
    }

    // เอา token สุดท้ายมาตรวจสะกด
    final last = tokens.last;
    final suggestions = _closestAllergensFor(last);

    setState(() {
      _allergySuggestions = suggestions;
      _lastMispelledToken = suggestions.isEmpty ? null : last;
    });
  }

  List<String> _closestAllergensFor(String token) {
    if (token.isEmpty) return [];
    // ถ้าตรงเป๊ะ ก็ไม่ต้องแนะนำ
    if (_allergenDict.contains(token)) return [];

    // หา 3 คำที่ใกล้สุดด้วย Levenshtein
    final scored = <MapEntry<String, int>>[];
    for (final cand in _allergenDict) {
      final dist = _levenshtein(token, cand);
      scored.add(MapEntry(cand, dist));
    }
    scored.sort((a, b) => a.value.compareTo(b.value));

    // เกณฑ์แนะนำ: ระยะ ≤ 1 สำหรับคำสั้น (<=3) หรือ ≤ 2 สำหรับคำยาวกว่า
    final maxDist = token.length <= 3 ? 1 : 2;
    final picks = scored
        .where((e) => e.value <= maxDist)
        .take(3)
        .map((e) => e.key)
        .toList();
    return picks;
  }

  int _levenshtein(String s, String t) {
    final m = s.length, n = t.length;
    if (m == 0) return n;
    if (n == 0) return m;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (int i = 0; i <= m; i++) dp[i][0] = i;
    for (int j = 0; j <= n; j++) dp[0][j] = j;
    for (int i = 1; i <= m; i++) {
      for (int j = 1; j <= n; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1, // delete
          dp[i][j - 1] + 1, // insert
          dp[i - 1][j - 1] + cost, // substitute
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return dp[m][n];
  }

  void _applyAllergySuggestion(String suggestion) {
    final text = _allergiesController.text;
    if (_lastMispelledToken == null || text.isEmpty) return;

    // แทนที่ token สุดท้ายที่ตรวจเจอผิด ด้วยคำแนะนำ
    final parts = text.split(RegExp(r'[,\n]'));
    if (parts.isEmpty) return;

    // หาตำแหน่ง token สุดท้ายแบบ trim แล้วเทียบ
    int idxToReplace = -1;
    for (int i = parts.length - 1; i >= 0; i--) {
      if (parts[i].trim() == _lastMispelledToken) {
        idxToReplace = i;
        break;
      }
    }
    if (idxToReplace == -1) return;

    parts[idxToReplace] = ' ${suggestion}'; // คั่นด้วยเว้นวรรคให้สวย
    final newText = parts.join(',');

    setState(() {
      _allergiesController.text = newText.trim();
      _allergiesController.selection = TextSelection.fromPosition(
        TextPosition(offset: _allergiesController.text.length),
      );
      _allergySuggestions = [];
      _lastMispelledToken = null;
    });
  }

  // ---- misc ----
  void _showSnackBar(String message, {bool success = true}) {
    final color = success ? Colors.green[600] : Colors.red[600];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

// ---------- modern card ----------
class _ModernCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color? color;
  const _ModernCard({
    required this.title,
    required this.icon,
    required this.child,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.black87;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: c),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, color: c),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ---------- tiny data classes ----------
class _DietChoice {
  final String key;
  final String label;
  const _DietChoice({required this.key, required this.label});
}

class _NutrientMeta {
  final String
  nutrientKey; // 'fat' | 'คาร์โบไฮเดรต' | 'โปรตีน' (key ใช้แมพกับ targets)
  final String display; // ป้ายแสดงผล (ไทย)
  final String unit; // 'g'
  const _NutrientMeta({
    required this.nutrientKey,
    required this.display,
    required this.unit,
  });
}
