// lib/profile/health_info_screen.dart — หน้าข้อมูลสุขภาพ (ดีไซน์ให้สอดคล้องกับ Account Detail)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:my_app/profile/model/my_user.dart';

class HealthInfoScreen extends StatefulWidget {
  const HealthInfoScreen({super.key});

  @override
  State<HealthInfoScreen> createState() => _HealthInfoScreenState();
}

class _HealthInfoScreenState extends State<HealthInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final User? _user = FirebaseAuth.instance.currentUser;

  bool _isLoading = true;
  bool _isEditing = false;
  bool _isSaving = false;

  MyUser? _currentUser;
  Map<String, dynamic>? _additionalHealthData;

  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _allergiesController = TextEditingController();
  final TextEditingController _bloodTypeController = TextEditingController();
  final TextEditingController _medicationsController = TextEditingController();
  final TextEditingController _smokingStatusController =
      TextEditingController();
  final TextEditingController _alcoholConsumptionController =
      TextEditingController();
  final TextEditingController _exerciseFrequencyController =
      TextEditingController();
  final TextEditingController _sleepHoursController = TextEditingController();
  final TextEditingController _waterIntakeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHealthData();
  }

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _allergiesController.dispose();
    _bloodTypeController.dispose();
    _medicationsController.dispose();
    _smokingStatusController.dispose();
    _alcoholConsumptionController.dispose();
    _exerciseFrequencyController.dispose();
    _sleepHoursController.dispose();
    _waterIntakeController.dispose();
    super.dispose();
  }

  Future<void> _loadHealthData() async {
    if (_user == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user.uid)
          .get();

      MyUser? currentUser;
      Map<String, dynamic>? extras;

      if (userDoc.exists) {
        currentUser = MyUser.fromFirestore(userDoc);
        final data = userDoc.data();
        final rawExtras = data?['healthProfile'];
        if (rawExtras is Map<String, dynamic>) {
          extras = Map<String, dynamic>.from(rawExtras);
        }
      }

      if (extras == null || extras.isEmpty) {
        final legacyDoc = await FirebaseFirestore.instance
            .collection('health_profiles')
            .doc(_user.uid)
            .get();
        if (legacyDoc.exists) {
          extras = legacyDoc.data();
        }
      }

      if (!mounted) return;

      setState(() {
        _currentUser = currentUser;
        _additionalHealthData = extras == null || extras.isEmpty
            ? null
            : Map<String, dynamic>.from(extras);
      });
      _populateControllers();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('ไม่สามารถโหลดข้อมูลได้', success: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateControllers() {
    final height = _currentUser?.height ?? 0;
    final weight = _currentUser?.weight ?? 0;
    final allergies = _currentUser?.allergies ?? '';
    final extras = _additionalHealthData ?? const {};

    _heightController.text = height > 0 ? height.toStringAsFixed(0) : '';
    _weightController.text = weight > 0 ? weight.toStringAsFixed(1) : '';
    _allergiesController.text = allergies;

    _bloodTypeController.text = _stringFromExtras(extras, 'bloodType');
    _medicationsController.text = _stringFromExtras(extras, 'medications');
    _smokingStatusController.text = _stringFromExtras(extras, 'smokingStatus');
    _alcoholConsumptionController.text = _stringFromExtras(
      extras,
      'alcoholConsumption',
    );
    _exerciseFrequencyController.text = _stringFromExtras(
      extras,
      'exerciseFrequency',
    );
    _sleepHoursController.text = _stringFromExtras(extras, 'sleepHours');
    _waterIntakeController.text = _stringFromExtras(extras, 'waterIntake');
  }

  void _toggleEditMode() {
    if (_isSaving) return;
    setState(() {
      if (_isEditing) {
        _populateControllers();
      }
      _isEditing = !_isEditing;
    });
  }

  String _stringFromExtras(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return '';
    if (value is String) return value;
    if (value is List) {
      return value.isEmpty ? '' : value.join(', ');
    }
    return value.toString();
  }

  double? _effectiveHeight() {
    final editingValue = double.tryParse(_heightController.text.trim());
    if (_isEditing && editingValue != null && editingValue > 0) {
      return editingValue;
    }
    final dataValue = _currentUser?.height ?? 0;
    return dataValue > 0 ? dataValue : null;
  }

  double? _effectiveWeight() {
    final editingValue = double.tryParse(_weightController.text.trim());
    if (_isEditing && editingValue != null && editingValue > 0) {
      return editingValue;
    }
    final dataValue = _currentUser?.weight ?? 0;
    return dataValue > 0 ? dataValue : null;
  }

  double? _calculateBMI() {
    final height = _effectiveHeight();
    final weight = _effectiveWeight();
    if (height == null || weight == null || height == 0) return null;
    final meters = height / 100;
    return weight / (meters * meters);
  }

  String _bmiCategory(double bmi) {
    if (bmi < 18.5) return 'น้ำหนักน้อย';
    if (bmi < 25) return 'ปกติ';
    if (bmi < 30) return 'น้ำหนักเกิน';
    return 'อ้วน';
  }

  Color _bmiColor(double bmi) {
    if (bmi < 18.5) return Colors.blue;
    if (bmi < 25) return Colors.green;
    if (bmi < 30) return Colors.orange;
    return Colors.red;
  }

  String _additionalValue(String key, {String fallback = 'ไม่ระบุ'}) {
    final value = _stringFromExtras(
      _additionalHealthData ?? const {},
      key,
    ).trim();
    return value.isEmpty ? fallback : value;
  }

  Future<void> _saveHealthData() async {
    final currentUser = _currentUser;
    final user = _user;
    if (currentUser == null || user == null) return;
    if (!_formKey.currentState!.validate()) return;

    final height = double.tryParse(_heightController.text.trim()) ?? 0;
    final weight = double.tryParse(_weightController.text.trim()) ?? 0;
    final allergies = _allergiesController.text.trim();

    setState(() => _isSaving = true);

    try {
      final healthProfile = <String, dynamic>{};

      void capture(String key, TextEditingController controller) {
        final value = controller.text.trim();
        if (value.isNotEmpty) {
          healthProfile[key] = value;
        }
      }

      capture('bloodType', _bloodTypeController);
      capture('medications', _medicationsController);
      capture('smokingStatus', _smokingStatusController);
      capture('alcoholConsumption', _alcoholConsumptionController);
      capture('exerciseFrequency', _exerciseFrequencyController);
      capture('sleepHours', _sleepHoursController);
      capture('waterIntake', _waterIntakeController);

      final updates = <String, dynamic>{
        'height': height,
        'weight': weight,
        'allergies': allergies,
      };
      if (healthProfile.isEmpty) {
        updates['healthProfile'] = FieldValue.delete();
      } else {
        updates['healthProfile'] = healthProfile;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update(updates);

      if (!mounted) return;
      setState(() {
        _currentUser = currentUser.copyWith(
          height: height,
          weight: weight,
          allergies: allergies,
        );
        _additionalHealthData = healthProfile.isEmpty
            ? null
            : Map<String, dynamic>.from(healthProfile);
        _populateControllers();
        _isEditing = false;
      });
      _showSnackBar('บันทึกข้อมูลสำเร็จ');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('เกิดข้อผิดพลาด: $e', success: false);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, {bool success = true}) {
    final color = success ? Colors.green[600] : Colors.red[600];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
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
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaffoldColor = Colors.grey[50];
    final notesValue = _additionalValue('notes', fallback: '');

    return Scaffold(
      backgroundColor: scaffoldColor,
      appBar: AppBar(
        backgroundColor: scaffoldColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'ข้อมูลสุขภาพ',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (!_isLoading)
            TextButton(
              onPressed: _toggleEditMode,
              child: Text(
                _isEditing ? 'ยกเลิก' : 'แก้ไข',
                style: TextStyle(
                  color: _isEditing ? Colors.red[600] : Colors.blue[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
              ),
            )
          : _currentUser == null
          ? const Center(child: Text('ไม่พบข้อมูลผู้ใช้'))
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildBMICard(),
                    const SizedBox(height: 16),
                    _buildSection('ข้อมูลร่างกาย', [
                      _buildEditableItem(
                        icon: Icons.height,
                        label: 'ส่วนสูง (ซม.)',
                        controller: _heightController,
                        keyboardType: TextInputType.number,
                        hintText: 'กรอกส่วนสูง',
                        enabled: _isEditing,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final parsed = double.tryParse(value.trim());
                          if (parsed == null || parsed <= 0) {
                            return 'กรุณากรอกตัวเลขที่ถูกต้อง';
                          }
                          return null;
                        },
                      ),
                      _buildEditableItem(
                        icon: Icons.monitor_weight,
                        label: 'น้ำหนัก (กก.)',
                        controller: _weightController,
                        keyboardType: TextInputType.number,
                        hintText: 'กรอกน้ำหนัก',
                        enabled: _isEditing,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return null;
                          }
                          final parsed = double.tryParse(value.trim());
                          if (parsed == null || parsed <= 0) {
                            return 'กรุณากรอกตัวเลขที่ถูกต้อง';
                          }
                          return null;
                        },
                      ),
                      _buildReadOnlyItem(
                        icon: Icons.monitor_heart,
                        label: 'ค่า BMI',
                        value: (() {
                          final bmi = _calculateBMI();
                          return bmi != null
                              ? bmi.toStringAsFixed(1)
                              : 'ไม่ทราบ';
                        })(),
                      ),
                      _buildReadOnlyItem(
                        icon: Icons.emoji_emotions_outlined,
                        label: 'สถานะน้ำหนัก',
                        value: (() {
                          final bmi = _calculateBMI();
                          return bmi != null ? _bmiCategory(bmi) : 'ไม่ทราบ';
                        })(),
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _buildSection('ข้อมูลสุขภาพทั่วไป', [
                      _buildEditableItem(
                        icon: Icons.warning_amber_outlined,
                        label: 'อาหารที่แพ้',
                        controller: _allergiesController,
                        hintText: 'ไม่มีอาหารที่แพ้',
                        enabled: _isEditing,
                        maxLines: 2,
                      ),
                      _buildEditableItem(
                        icon: Icons.bloodtype,
                        label: 'กรุ๊ปเลือด',
                        controller: _bloodTypeController,
                        hintText: 'กรอกกรุ๊ปเลือด (เช่น A, B, O, AB)',
                        enabled: _isEditing,
                      ),
                      _buildEditableItem(
                        icon: Icons.medication_outlined,
                        label: 'ยาที่ใช้ประจำ',
                        controller: _medicationsController,
                        hintText: 'ไม่มี',
                        enabled: _isEditing,
                        maxLines: 2,
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _buildSection('พฤติกรรมการใช้ชีวิต', [
                      _buildEditableItem(
                        icon: Icons.smoking_rooms,
                        label: 'สถานะการสูบบุหรี่',
                        controller: _smokingStatusController,
                        hintText: 'ไม่สูบ',
                        enabled: _isEditing,
                      ),
                      _buildEditableItem(
                        icon: Icons.wine_bar,
                        label: 'การดื่มแอลกอฮอล์',
                        controller: _alcoholConsumptionController,
                        hintText: 'ไม่ดื่ม',
                        enabled: _isEditing,
                      ),
                      _buildEditableItem(
                        icon: Icons.fitness_center,
                        label: 'ความถี่การออกกำลังกาย',
                        controller: _exerciseFrequencyController,
                        hintText: 'เช่น 3 ครั้ง/สัปดาห์',
                        enabled: _isEditing,
                      ),
                      _buildEditableItem(
                        icon: Icons.bedtime,
                        label: 'ชั่วโมงการนอน',
                        controller: _sleepHoursController,
                        hintText: 'เช่น 7 ชั่วโมง/คืน',
                        enabled: _isEditing,
                      ),
                      _buildEditableItem(
                        icon: Icons.water_drop_outlined,
                        label: 'ปริมาณการดื่มน้ำ',
                        controller: _waterIntakeController,
                        hintText: 'เช่น 8 แก้ว/วัน',
                        enabled: _isEditing,
                      ),
                    ]),
                    const SizedBox(height: 16),
                    if (notesValue.trim().isNotEmpty)
                      _buildSection('บันทึกเพิ่มเติม', [
                        _buildReadOnlyParagraph(
                          icon: Icons.note_alt_outlined,
                          label: 'หมายเหตุ',
                          value: notesValue.trim(),
                        ),
                      ]),
                    if (_isEditing) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isSaving ? null : _saveHealthData,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'บันทึกข้อมูล',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBMICard() {
    final bmi = _calculateBMI();
    final bmiValue = bmi != null ? bmi.toStringAsFixed(1) : 'ไม่ทราบ';
    final category = bmi != null ? _bmiCategory(bmi) : 'ไม่ทราบ';
    final color = bmi != null ? _bmiColor(bmi) : Colors.blueGrey;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withAlpha((255 * 0.08).round()),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha((255 * 0.2).round())),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ดัชนีมวลกาย (BMI)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Icon(Icons.health_and_safety, color: color),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                bmiValue,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withAlpha((255 * 0.15).round()),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  category,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            bmi != null
                ? _getBMIAdvice(bmi)
                : 'กรอกน้ำหนักและส่วนสูงเพื่อคำนวณ BMI',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildEditableItem({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? hintText,
    String? Function(String?)? validator,
    int maxLines = 1,
    bool enabled = false,
  }) {
    final displayText = controller.text.trim();
    final showPlaceholder = displayText.isEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: maxLines > 1 && enabled
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: enabled
                ? TextFormField(
                    controller: controller,
                    keyboardType: keyboardType,
                    maxLines: maxLines,
                    validator: validator,
                    decoration: InputDecoration(
                      hintText: hintText,
                      labelText: label,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        showPlaceholder ? (hintText ?? 'ไม่ระบุ') : displayText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: showPlaceholder
                              ? Colors.grey[500]
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final display = value.trim().isEmpty ? 'ไม่ระบุ' : value;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  display,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyParagraph({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getBMIAdvice(double bmi) {
    if (bmi < 18.5) {
      return 'แนะนำให้เพิ่มน้ำหนักและรับประทานอาหารที่มีประโยชน์';
    } else if (bmi < 25) {
      return 'น้ำหนักของคุณอยู่ในเกณฑ์ปกติ ควรรักษาไว้';
    } else if (bmi < 30) {
      return 'แนะนำให้ลดน้ำหนักและออกกำลังกายสม่ำเสมอ';
    } else {
      return 'ควรปรึกษาแพทย์เพื่อวางแผนลดน้ำหนักอย่างถูกต้อง';
    }
  }
}
