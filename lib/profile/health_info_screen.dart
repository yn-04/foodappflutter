// lib/profile/health_info_screen.dart — Health Info (Modern UI + Always Editable + BMI no-overflow + Allergy suggestions
import 'dart:io';
// ADD
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:my_app/profile/model/my_user.dart';
import 'package:my_app/services/firebase_storage_service.dart';

enum _EditableField { height, weight, allergies }

class HealthInfoScreen extends StatefulWidget {
  const HealthInfoScreen({super.key});

  @override
  State<HealthInfoScreen> createState() => _HealthInfoScreenState();
}

class _DriTargets {
  final double energyKcal;
  final double carbMinG, carbMaxG;
  final double fatMinG, fatMaxG;
  final double proteinG;
  final double sodiumMaxMg;
  _DriTargets({
    required this.energyKcal,
    required this.carbMinG,
    required this.carbMaxG,
    required this.fatMinG,
    required this.fatMaxG,
    required this.proteinG,
    required this.sodiumMaxMg,
  });
}

class _HealthInfoScreenState extends State<HealthInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final User? _user = FirebaseAuth.instance.currentUser;
  // edit state flags
  bool _editHeight = false, _editWeight = false, _editAllergies = false;

  // focus node ต่อช่อง
  final FocusNode _fnHeight = FocusNode();
  final FocusNode _fnWeight = FocusNode();
  final FocusNode _fnAllergies = FocusNode();

  bool _isLoading = true;
  bool _isSaving = false;

  MyUser? _currentUser;
  Map<String, dynamic>? _additionalHealthData;

  final TextEditingController _displayNameController = TextEditingController();
  File? _selectedProfileImage;
  String? _currentPhotoUrl;

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
  // ตารางที่ 1: kcal/protein ต่อวัน (DRI ไทย 2563) สำหรับอายุเป็น "ปี" และเพศชาย/หญิง
  static const List<Map<String, dynamic>> _kDriTable1 = [
    // เด็ก
    {'min': 1, 'max': 3, 'sex': 'male', 'kcal': 1050, 'protein': 16},
    {'min': 4, 'max': 5, 'sex': 'male', 'kcal': 1290, 'protein': 19},
    {'min': 6, 'max': 8, 'sex': 'male', 'kcal': 1440, 'protein': 24},
    {'min': 1, 'max': 3, 'sex': 'female', 'kcal': 980, 'protein': 15},
    {'min': 4, 'max': 5, 'sex': 'female', 'kcal': 1200, 'protein': 19},
    {'min': 6, 'max': 8, 'sex': 'female', 'kcal': 1320, 'protein': 24},
    // วัยรุ่น
    {'min': 9, 'max': 12, 'sex': 'male', 'kcal': 1800, 'protein': 39},
    {'min': 13, 'max': 15, 'sex': 'male', 'kcal': 2200, 'protein': 55},
    {'min': 16, 'max': 18, 'sex': 'male', 'kcal': 2370, 'protein': 61},
    {'min': 9, 'max': 12, 'sex': 'female', 'kcal': 1650, 'protein': 40},
    {'min': 13, 'max': 15, 'sex': 'female', 'kcal': 1860, 'protein': 51},
    {'min': 16, 'max': 18, 'sex': 'female', 'kcal': 1890, 'protein': 51},
    // ผู้ใหญ่ชาย
    {'min': 19, 'max': 30, 'sex': 'male', 'kcal': 2260, 'protein': 61},
    {'min': 31, 'max': 50, 'sex': 'male', 'kcal': 2190, 'protein': 60},
    {'min': 51, 'max': 60, 'sex': 'male', 'kcal': 2180, 'protein': 60},
    {'min': 61, 'max': 70, 'sex': 'male', 'kcal': 1790, 'protein': 59},
    {'min': 71, 'max': 150, 'sex': 'male', 'kcal': 1740, 'protein': 56},
    // ผู้ใหญ่หญิง
    {'min': 19, 'max': 30, 'sex': 'female', 'kcal': 1780, 'protein': 53},
    {'min': 31, 'max': 50, 'sex': 'female', 'kcal': 1780, 'protein': 52},
    {'min': 51, 'max': 60, 'sex': 'female', 'kcal': 1770, 'protein': 52},
    {'min': 61, 'max': 70, 'sex': 'female', 'kcal': 1560, 'protein': 50},
    {'min': 71, 'max': 150, 'sex': 'female', 'kcal': 1540, 'protein': 49},
  ];

  // หา kcal/protein จากตารางที่ 1
  Map<String, double>? _table1EnergyProtein({
    required int ageYears,
    required String sexKey,
  }) {
    for (final r in _kDriTable1) {
      if (r['sex'] == sexKey &&
          ageYears >= (r['min'] as int) &&
          ageYears <= (r['max'] as int)) {
        return {
          'kcal': (r['kcal'] as num).toDouble(),
          'protein': (r['protein'] as num).toDouble(),
        };
      }
    }
    return null;
  }

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
  // ADD: DRI dataset (Thai DRI 2563)
  static const Map<String, dynamic> kDriThai2020 = {
    'carb_pct_min': 45.0,
    'carb_pct_max': 65.0,
    'fat_pct_min': 25.0,
    'fat_pct_max': 35.0,
    'protein_g_per_kg': 1.0,
    'sodium_mg_max': 2000.0,
  };

  // ADD: controller/flags สำหรับ DRI
  final TextEditingController _driEnergyController = TextEditingController(
    text: '2000',
  );
  _DriTargets? _driPreview;

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

  int? get _ageYears {
    final dynamic birthDate =
        _currentUser?.birthDate ?? (_additionalHealthData?['birthDate']);
    if (birthDate == null) return null;
    final age = _ageYearsFromBirthDate(birthDate);
    if (age <= 0) return null;
    return age;
  }

  Widget? get suffixIcon => null;

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
    _driEnergyController.dispose();

    _fnHeight.dispose();
    _fnWeight.dispose();
    _fnAllergies.dispose();
    super.dispose();
  }

  void _startEdit(_EditableField f) {
    setState(() {
      switch (f) {
        case _EditableField.height:
          _editHeight = true;
          FocusScope.of(context).requestFocus(_fnHeight);
          break;
        case _EditableField.weight:
          _editWeight = true;
          FocusScope.of(context).requestFocus(_fnWeight);
          break;
        case _EditableField.allergies:
          _editAllergies = true;
          FocusScope.of(context).requestFocus(_fnAllergies);
          break;
      }
    });
  }

  void _commitField(_EditableField f) {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      switch (f) {
        case _EditableField.height:
          _editHeight = false;
          break;
        case _EditableField.weight:
          _editWeight = false;
          break;
        case _EditableField.allergies:
          _editAllergies = false;
          break;
      }
    });
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
      _updateDriPreviewFromControllers();
      // ⬇️ เรียกคำนวณ DRI จากตารางที่ 1 แล้วบันทึก
      await _recomputeDriFromProfileAndSave();
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
    final diets = _additionalHealthData?['dietPreferences'];
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

    final perMeal = _additionalHealthData?['nutritionTargetsPerMeal'];
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
    // ADD (ท้าย _populateDiet)
    final extras = _additionalHealthData ?? const {};
    final dri = extras['dri'];
    if (dri is Map && dri['energy_kcal'] is num) {
      _driEnergyController.text = (dri['energy_kcal'] as num).toStringAsFixed(
        0,
      );
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

  // ------- Computations -------
  // (มี _bmi(), _bmiColor(), _bmiAdvice() ของรินอยู่ก่อนหน้า)
  // เพศภาษาไทย -> key 'male' | 'female'
  String _sexKeyFromGender(String? gender) {
    final g = (gender ?? '').trim();
    if (g == 'ชาย' || g.toLowerCase() == 'male' || g == 'M') return 'male';
    if (g == 'หญิง' || g.toLowerCase() == 'female' || g == 'F') return 'female';
    return '';
  }

  // คำนวณอายุจาก birthDate (รองรับ Timestamp / DateTime / String ISO)
  int _ageYearsFromBirthDate(dynamic birthDate) {
    DateTime? dob;
    if (birthDate is Timestamp)
      dob = birthDate.toDate();
    else if (birthDate is DateTime)
      dob = birthDate;
    else if (birthDate is String) {
      try {
        dob = DateTime.parse(birthDate);
      } catch (_) {}
    }
    if (dob == null) return 0;

    final now = DateTime.now();
    var years = now.year - dob.year;
    final hasHadBirthday =
        (now.month > dob.month) ||
        (now.month == dob.month && now.day >= dob.day);
    if (!hasHadBirthday) years--;
    return years;
  }

  // % คาร์บ/ไขมันตามวัย

  _MacroPct _macroPctForAgeYears(int ageYears) {
    if (ageYears >= 1 && ageYears <= 2) return const _MacroPct(45, 65, 35, 40);
    if (ageYears >= 2 && ageYears <= 8) return const _MacroPct(45, 65, 25, 35);
    if (ageYears >= 9 && ageYears <= 18) return const _MacroPct(45, 65, 25, 35);
    // ผู้ใหญ่และผู้สูงอายุ
    return const _MacroPct(45, 65, 20, 35);
  }

  double _parsePosDouble(String? s, {double? fallback}) {
    final v = double.tryParse((s ?? '').trim());
    if (v == null || v <= 0) return fallback ?? 0;
    return v;
  }

  _DriTargets _computeDriTargets({
    required double energyKcal,
    required double? weightKg,
    int? ageYears, // ⬅️ เพิ่ม
  }) {
    final _MacroPct p = _macroPctForAgeYears(
      ageYears ?? 19,
    ); // ถ้าไม่ทราบอายุ ให้ fallback ผู้ใหญ่

    final carbMinG = (energyKcal * (p.carbMin / 100.0)) / 4.0;
    final carbMaxG = (energyKcal * (p.carbMax / 100.0)) / 4.0;
    final fatMinG = (energyKcal * (p.fatMin / 100.0)) / 9.0;
    final fatMaxG = (energyKcal * (p.fatMax / 100.0)) / 9.0;

    final proteinPerKg = (kDriThai2020['protein_g_per_kg'] as num).toDouble();
    final proteinG = (weightKg != null && weightKg > 0)
        ? (weightKg * proteinPerKg)
        : 50.0;

    final sodiumMaxMg = (kDriThai2020['sodium_mg_max'] as num).toDouble();

    return _DriTargets(
      energyKcal: energyKcal,
      carbMinG: carbMinG,
      carbMaxG: carbMaxG,
      fatMinG: fatMinG,
      fatMaxG: fatMaxG,
      proteinG: proteinG,
      sodiumMaxMg: sodiumMaxMg,
    );
  }

  Map<String, dynamic> _buildDriPayload(
    _DriTargets targets, {
    required String source,
    Map<String, dynamic>? extra,
  }) {
    return {
      'source': source,
      'energy_kcal': targets.energyKcal,
      'carb_min_g': targets.carbMinG,
      'carb_max_g': targets.carbMaxG,
      'fat_min_g': targets.fatMinG,
      'fat_max_g': targets.fatMaxG,
      'protein_g': targets.proteinG,
      'sodium_max_mg': targets.sodiumMaxMg,
      if (extra != null) ...extra,
    };
  }

  bool _deepEquals(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key)) return false;
        if (!_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is num && b is num) {
      return (a - b).abs() < 0.0001;
    }
    return a == b;
  }

  void _updateDriPreviewFromControllers({bool shouldSetState = true}) {
    final energy = _parsePosDouble(_driEnergyController.text, fallback: 2000);
    final weight = double.tryParse(_weightController.text.trim());
    final targets = _computeDriTargets(
      energyKcal: energy,
      weightKg: weight,
      ageYears: _ageYears,
    );
    if (shouldSetState) {
      if (!mounted) return;
      setState(() => _driPreview = targets);
    } else {
      _driPreview = targets;
    }
  }

  // เรียกเมื่อพิมพ์ส่วนสูง/น้ำหนัก
  void _onAnthroChanged() => _updateDriPreviewFromControllers();

  // ------- Save -------
  Future<void> _recomputeDriFromProfileAndSave() async {
    // gender / birthDate จาก currentUser หรือ healthProfile
    final genderStr =
        _currentUser?.gender ?? (_additionalHealthData?['gender'] as String?);
    final sexKey = _sexKeyFromGender(genderStr);
    final birthDate =
        _currentUser?.birthDate ?? (_additionalHealthData?['birthDate']);
    final ageY = (birthDate != null) ? _ageYearsFromBirthDate(birthDate) : 0;

    if (sexKey.isEmpty || ageY <= 0) return;

    final t1 = _table1EnergyProtein(ageYears: ageY, sexKey: sexKey);
    if (t1 == null) return;

    final kcal = (t1['kcal'] as num).toDouble();
    final protein = (t1['protein'] as num).toDouble();

    final pct = _macroPctForAgeYears(ageY);
    final carbMinG = (kcal * (pct.carbMin / 100)) / 4.0;
    final carbMaxG = (kcal * (pct.carbMax / 100)) / 4.0;
    final fatMinG = (kcal * (pct.fatMin / 100)) / 9.0;
    final fatMaxG = (kcal * (pct.fatMax / 100)) / 9.0;

    // ซิงก์กล่องพลังงานบน UI
    _driEnergyController.text = kcal.round().toString();

    final targets = _DriTargets(
      energyKcal: kcal,
      carbMinG: carbMinG,
      carbMaxG: carbMaxG,
      fatMinG: fatMinG,
      fatMaxG: fatMaxG,
      proteinG: protein,
      sodiumMaxMg: 2000,
    );
    final basePayload = _buildDriPayload(
      targets,
      source: 'Thai DRI 2020 (Table1 + Age-based %)',
      extra: {
        'macros_pct_age_based': {
          'carb_min': pct.carbMin,
          'carb_max': pct.carbMax,
          'fat_min': pct.fatMin,
          'fat_max': pct.fatMax,
        },
        'inputs': {
          'gender': genderStr,
          'sexKey': sexKey,
          'age_years': ageY,
          'weight_kg': double.tryParse(_weightController.text.trim()),
          'height_cm': double.tryParse(_heightController.text.trim()),
        },
      },
    );

    final existing = _additionalHealthData?['dri'];
    if (existing is Map<String, dynamic>) {
      final comparableExisting = Map<String, dynamic>.from(existing)
        ..remove('updated_at');
      if (_deepEquals(comparableExisting, basePayload)) {
        if (mounted) {
          setState(() {
            _additionalHealthData!['dri'] = basePayload;
            _driPreview = targets;
          });
        }
        return;
      }
    }

    // เขียนลง Firestore
    final user = _user;
    if (user == null) return;

    try {
      final payloadForFirestore = {
        ...basePayload,
        'updated_at': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'healthProfile.dri': payloadForFirestore},
      );

      // sync state หน้าแอป
      _additionalHealthData ??= {};
      _additionalHealthData!['dri'] = basePayload;
      if (mounted) {
        setState(() {
          _driPreview = targets;
        });
      }
    } catch (_) {
      /* ไม่เด้ง error ระหว่าง sync อัตโนมัติ */
    }
  }

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
      // ADD in _save() before Firestore update
      final energyKcal = _parsePosDouble(
        _driEnergyController.text,
        fallback: 2000,
      );
      final weightKg = double.tryParse(_weightController.text.trim());
      final driTargets = _computeDriTargets(
        energyKcal: energyKcal,
        weightKg: weightKg,
      );
      final driBasePayload = _buildDriPayload(
        driTargets,
        source: 'Thai DRI 2020',
      );
      final driFirestorePayload = {
        ...driBasePayload,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (updates['healthProfile'] is FieldValue) {
        // skip
      } else {
        final hp = (updates['healthProfile'] as Map<String, dynamic>?) ?? {};
        hp['dri'] = driFirestorePayload;
        updates['healthProfile'] = hp;
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
        // ADD in setState of _save()
        if (_additionalHealthData != null) {
          _additionalHealthData!['dri'] = driBasePayload;
        }
        _driPreview = driTargets;
      });
      _showSnackBar('บันทึกข้อมูลสำเร็จ');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('บันทึกล้มเหลว: $e', success: false);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ------- UI -------
  Widget _editLockSuffix({
    required bool editing,
    required bool isBusy,
    required VoidCallback onStartEdit,
    required VoidCallback onSaveAndLock,
  }) {
    return IconButton(
      tooltip: editing ? 'ล็อกค่า' : 'แก้ไข',
      onPressed: isBusy ? null : (editing ? onSaveAndLock : onStartEdit),
      icon: Icon(editing ? Icons.lock_open : Icons.edit),
    );
  }

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
                    title: 'ดัชนีมวลกาย (BMI)',
                    icon: Icons.health_and_safety,
                    child: _buildBmiContentNoOverflow(),
                    color: Colors.black87,
                  ),
                  const SizedBox(height: 16),
                  // ADD (หลัง BMI card + SizedBox 16)
                  _ModernCard(
                    title: 'สารอาหารที่ควรได้รับต่อวัน',
                    icon: Icons.restaurant,
                    child: _buildDailyDriCard(),
                  ),
                  const SizedBox(height: 16),

                  // การ์ด: ข้อมูลร่างกาย
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
                          readOnly: !_editHeight,
                          focusNode: _fnHeight,
                          onChanged: (_) => _onAnthroChanged(),
                          suffix: _editLockSuffix(
                            editing: _editHeight,
                            isBusy: _isSaving,
                            onStartEdit: () =>
                                _startEdit(_EditableField.height),
                            onSaveAndLock: () =>
                                _commitField(_EditableField.height),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _filledField(
                          controller: _weightController,
                          label: 'น้ำหนัก (กก.)',
                          hint: 'เช่น 54.5',
                          keyboardType: TextInputType.number,
                          validator: _numberOrEmptyValidator,
                          readOnly: !_editWeight,
                          focusNode: _fnWeight,
                          onChanged: (_) => _onAnthroChanged(),
                          suffix: _editLockSuffix(
                            editing: _editWeight,
                            isBusy: _isSaving,
                            onStartEdit: () =>
                                _startEdit(_EditableField.weight),
                            onSaveAndLock: () =>
                                _commitField(_EditableField.weight),
                          ),
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
                        // การ์ด: ข้อจำกัดด้านอาหาร → ช่อง "อาหารที่แพ้"
                        _filledField(
                          controller: _allergiesController,
                          label: 'อาหารที่แพ้',
                          hint: 'เช่น กุ้ง, ถั่วลิสง (คั่นด้วย , )',
                          maxLines: 2,
                          readOnly: !_editAllergies,
                          focusNode: _fnAllergies,
                          suffix: _editLockSuffix(
                            editing: _editAllergies,
                            isBusy: _isSaving,
                            onStartEdit: () =>
                                _startEdit(_EditableField.allergies),
                            onSaveAndLock: () =>
                                _commitField(_EditableField.allergies),
                          ),
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
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.black,
                                ),
                              ),
                            )
                          : const Icon(Icons.save_rounded, color: Colors.black),
                      label: const Text(
                        'บันทึกข้อมูล',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color.fromARGB(255, 255, 255, 255), // ฟอนต์ดำ
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color.fromARGB(
                          255,
                          0,
                          0,
                          0,
                        ), // เหลือง
                        foregroundColor: Colors.black, // ไอคอน + ข้อความเป็นดำ
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

  // ADD: การ์ด DRI
  Widget _buildDailyDriCard() {
    final preview =
        _driPreview ??
        _computeDriTargets(
          energyKcal: _parsePosDouble(
            _driEnergyController.text,
            fallback: 2000,
          ),
          weightKg: double.tryParse(_weightController.text.trim()),
          ageYears: _ageYears,
        );

    String _g(double v) =>
        v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    String _mg(double v) => v.toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'พลังงาน (kcal/วัน)',
            isDense: true,
            filled: true,
            fillColor: const Color.fromARGB(255, 246, 241, 243),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
          ),
          child: Text(
            preview.energyKcal.round().toString(),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 12),
        _kvRow(
          'คาร์โบไฮเดรต',
          '${_g(preview.carbMinG)}–${_g(preview.carbMaxG)} g/วัน',
        ),
        const SizedBox(height: 12),
        _kvRow('ไขมัน', '${_g(preview.fatMinG)}–${_g(preview.fatMaxG)} g/วัน'),
        const SizedBox(height: 12),
        _kvRow('โปรตีน', '${_g(preview.proteinG)} g/วัน'),
        const SizedBox(height: 12),
        _kvRow('โซเดียม (สูงสุด)', '≤ ${_mg(preview.sodiumMaxMg)} mg/วัน'),
        const SizedBox(height: 12),
        Text(
          'อ้างอิง: Thai DRI 2020 ',
          style: TextStyle(fontSize: 11.5, color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _kvRow(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Text(
            k,
            style: const TextStyle(fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 7,
          child: Text(
            v,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
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
                  color: color.withValues(alpha: .12),
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
    // ⬇️ เพิ่มพารามิเตอร์ที่เราจะใช้ “เพียงครั้งเดียว” ที่นี่
    bool readOnly = false,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
    Widget? suffix, // ใช้เป็น decoration.suffixIcon
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: maxLines,
      readOnly: readOnly,
      focusNode: focusNode,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: const Color.fromARGB(255, 246, 241, 243),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        suffixIcon: suffix, // ⬅️ ใช้ตรงนี้เท่านั้น
      ),
    );
  }

  // ---- validators ----

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

class _MacroPct {
  final double carbMin, carbMax, fatMin, fatMax;
  const _MacroPct(this.carbMin, this.carbMax, this.fatMin, this.fatMax);
}
