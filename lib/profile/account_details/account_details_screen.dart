// lib/profile/account_details/account_details_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app/profile/account_settings/services/user_service.dart';
import 'package:my_app/profile/my_user.dart';

class ModernAccountDetailsScreen extends StatefulWidget {
  const ModernAccountDetailsScreen({super.key});

  @override
  State<ModernAccountDetailsScreen> createState() =>
      _ModernAccountDetailsScreenState();
}

class _ModernAccountDetailsScreenState
    extends State<ModernAccountDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = true;
  bool _isEditing = false;
  MyUser? _myUser;
  final user = FirebaseAuth.instance.currentUser;
  final UserService _userService = UserService();

  // Controllers สำหรับแก้ไขข้อมูล
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _allergiesController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String _selectedGender = 'ชาย';
  DateTime? _selectedBirthDate;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _allergiesController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);

    try {
      if (user != null) {
        MyUser? userData = await _userService.getUserById(user!.uid);
        if (userData != null) {
          setState(() {
            _myUser = userData;
            _populateControllers();
          });
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
      _showErrorSnackBar('ไม่สามารถโหลดข้อมูลได้');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _populateControllers() {
    if (_myUser != null) {
      _firstNameController.text = _myUser!.firstName;
      _lastNameController.text = _myUser!.lastName;
      _phoneController.text = _myUser!.phoneNumber;
      _heightController.text = _myUser!.height > 0
          ? _myUser!.height.toStringAsFixed(0)
          : '';
      _weightController.text = _myUser!.weight > 0
          ? _myUser!.weight.toStringAsFixed(0)
          : '';
      _allergiesController.text = _myUser!.allergies;
      _selectedGender = _myUser!.gender.isNotEmpty ? _myUser!.gender : 'ชาย';
      _selectedBirthDate = _myUser!.birthDate;
    }
  }

  // ใช้ showDatePicker มาตรฐาน (ค.ศ.)
  Future<void> _selectBirthDate() async {
    try {
      DateTime initialDate =
          _selectedBirthDate ??
          DateTime.now().subtract(const Duration(days: 365 * 25));

      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime(1900),
        lastDate: DateTime.now(),
        helpText: 'เลือกวันเกิด',
        cancelText: 'ยกเลิก',
        confirmText: 'เลือก',
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: Colors.grey[800]!,
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
              ),
            ),
            child: child!,
          );
        },
      );

      if (picked != null && picked != _selectedBirthDate) {
        setState(() {
          _selectedBirthDate = picked;
        });
      }
    } catch (e) {
      print('Error selecting date: $e');
      _showErrorSnackBar('ไม่สามารถเปิดปฏิทินได้ กรุณาลองใหม่');
    }
  }

  Future<void> _saveUserData() async {
    if (_myUser == null || user == null) return;

    if (!_formKey.currentState!.validate()) return;

    if (_selectedBirthDate == null) {
      _showErrorSnackBar('กรุณาเลือกวันเกิด');
      return;
    }

    setState(() => _isLoading = true);

    try {
      MyUser updatedUser = MyUser(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _myUser!.email,
        phoneNumber: _phoneController.text.trim(),
        gender: _selectedGender,
        height: double.tryParse(_heightController.text) ?? 0,
        weight: double.tryParse(_weightController.text) ?? 0,
        allergies: _allergiesController.text.trim(),
        fullName:
            '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
        birthDate: _selectedBirthDate!,
        createdAt: _myUser!.createdAt,
        profileCompleted: true,
      );

      bool success = await _userService.updateUser(user!.uid, updatedUser);

      if (success) {
        await user!.updateDisplayName(updatedUser.fullName);
        setState(() {
          _myUser = updatedUser;
          _isEditing = false;
        });
        _showSuccessSnackBar('อัปเดตข้อมูลสำเร็จ');
      } else {
        _showErrorSnackBar('ไม่สามารถอัปเดตข้อมูลได้');
      }
    } catch (e) {
      print('Error saving user data: $e');
      _showErrorSnackBar('เกิดข้อผิดพลาด: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleEditMode() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        _populateControllers();
      }
    });
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
  }

  String _formatDateFull(DateTime date) {
    const List<String> months = [
      'มกราคม',
      'กุมภาพันธ์',
      'มีนาคม',
      'เมษายน',
      'พฤษภาคม',
      'มิถุนายน',
      'กรกฎาคม',
      'สิงหาคม',
      'กันยายน',
      'ตุลาคม',
      'พฤศจิกายน',
      'ธันวาคม',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _getProviderName(User? user) {
    if (user == null) return 'ไม่ทราบ';

    for (var provider in user.providerData) {
      switch (provider.providerId) {
        case 'google.com':
          return 'Google';
        case 'password':
          return 'อีเมล/รหัสผ่าน';
        case 'facebook.com':
          return 'Facebook';
        case 'apple.com':
          return 'Apple';
        default:
          return provider.providerId;
      }
    }
    return 'ไม่ทราบ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.grey[50],
        elevation: 0,
        title: const Text(
          'บัญชีของฉัน',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
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
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // ข้อมูลส่วนตัว
                    _buildInfoSection('ข้อมูลส่วนตัว', [
                      _buildInfoItem(
                        'ชื่อ',
                        _myUser?.firstName ?? '',
                        _firstNameController,
                        Icons.person_outline,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'กรุณากรอกชื่อ';
                          }
                          return null;
                        },
                      ),
                      _buildInfoItem(
                        'นามสกุล',
                        _myUser?.lastName ?? '',
                        _lastNameController,
                        Icons.person_outline,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'กรุณากรอกนามสกุล';
                          }
                          return null;
                        },
                      ),
                      _buildGenderItem(),
                      _buildBirthDateItem(),
                      _buildReadOnlyItem(
                        'อายุ',
                        _myUser?.age != null ? '${_myUser!.age} ปี' : 'ไม่ระบุ',
                        Icons.cake_outlined,
                      ),
                    ]),

                    const SizedBox(height: 16),

                    // ข้อมูลสุขภาพ
                    _buildInfoSection('ข้อมูลสุขภาพ', [
                      _buildInfoItem(
                        'ส่วนสูง (ซม.)',
                        _myUser?.height != null && _myUser!.height > 0
                            ? _myUser!.height.toStringAsFixed(0)
                            : '',
                        _heightController,
                        Icons.height,
                        keyboardType: TextInputType.number,
                      ),
                      _buildInfoItem(
                        'น้ำหนัก (กก.)',
                        _myUser?.weight != null && _myUser!.weight > 0
                            ? _myUser!.weight.toStringAsFixed(0)
                            : '',
                        _weightController,
                        Icons.monitor_weight_outlined,
                        keyboardType: TextInputType.number,
                      ),
                      _buildReadOnlyItem(
                        'BMI',
                        _myUser?.bmi != null && _myUser!.bmi > 0
                            ? '${_myUser!.bmi.toStringAsFixed(1)} (${_myUser!.bmiCategory})'
                            : 'ไม่ระบุ',
                        Icons.analytics_outlined,
                      ),
                      _buildInfoItem(
                        'ประวัติการแพ้',
                        _myUser?.allergies ?? '',
                        _allergiesController,
                        Icons.medical_services_outlined,
                        maxLines: 2,
                      ),
                    ]),

                    const SizedBox(height: 16),

                    // ข้อมูลติดต่อ
                    _buildInfoSection('ข้อมูลติดต่อ', [
                      _buildReadOnlyItem(
                        'อีเมล',
                        _myUser?.email ?? user?.email ?? 'ไม่ระบุ',
                        Icons.email_outlined,
                      ),
                      _buildInfoItem(
                        'เบอร์โทรศัพท์',
                        _myUser?.phoneNumber ?? '',
                        _phoneController,
                        Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                    ]),

                    const SizedBox(height: 16),

                    // ข้อมูลบัญชี
                    _buildInfoSection('ข้อมูลบัญชี', [
                      _buildReadOnlyItem(
                        'วันที่สมัคร',
                        _myUser?.createdAt != null
                            ? _formatDateFull(_myUser!.createdAt)
                            : 'ไม่ระบุ',
                        Icons.calendar_today_outlined,
                      ),
                      _buildReadOnlyItem(
                        'วิธีการล็อกอิน',
                        _getProviderName(user),
                        Icons.login_outlined,
                      ),
                      _buildReadOnlyItem(
                        'สถานะบัญชี',
                        'ใช้งานได้',
                        Icons.check_circle_outline,
                      ),
                      _buildReadOnlyItem(
                        'การยืนยันตัวตน',
                        user?.emailVerified == true
                            ? 'ยืนยันแล้ว'
                            : 'ยังไม่ยืนยัน',
                        Icons.verified_outlined,
                      ),
                    ]),

                    // ปุ่มบันทึก
                    if (_isEditing) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveUserData,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black87,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
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

  Widget _buildInfoSection(String title, List<Widget> children) {
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

  Widget _buildInfoItem(
    String label,
    String value,
    TextEditingController controller,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _isEditing
                ? TextFormField(
                    controller: controller,
                    keyboardType: keyboardType,
                    maxLines: maxLines,
                    validator: validator,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Colors.black87),
                      ),
                      hintText: keyboardType == TextInputType.phone
                          ? '08X-XXX-XXXX'
                          : null,
                      hintStyle: TextStyle(color: Colors.grey[400]),
                    ),
                  )
                : Text(
                    value.isEmpty ? 'ไม่ระบุ' : value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: value.isEmpty ? Colors.grey[500] : Colors.black87,
                    ),
                    textAlign: TextAlign.right,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyItem(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value.isEmpty ? 'ไม่ระบุ' : value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: value.isEmpty ? Colors.grey[500] : Colors.black87,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderItem() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.wc, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              'เพศ',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _isEditing
                ? DropdownButtonFormField<String>(
                    value: _selectedGender,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    items: ['ชาย', 'หญิง', 'อื่นๆ'].map((gender) {
                      return DropdownMenuItem(
                        value: gender,
                        child: Text(gender),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedGender = value!;
                      });
                    },
                  )
                : Text(
                    _selectedGender.isEmpty ? 'ไม่ระบุ' : _selectedGender,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _selectedGender.isEmpty
                          ? Colors.grey[500]
                          : Colors.black87,
                    ),
                    textAlign: TextAlign.right,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBirthDateItem() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.calendar_today, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              'วันเกิด',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: _isEditing
                ? InkWell(
                    onTap: _selectBirthDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedBirthDate != null
                                ? _formatDate(_selectedBirthDate!)
                                : 'เลือกวันเกิด',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _selectedBirthDate != null
                                  ? Colors.black87
                                  : Colors.grey[500],
                            ),
                          ),
                          Icon(
                            Icons.keyboard_arrow_down,
                            size: 16,
                            color: Colors.grey[600],
                          ),
                        ],
                      ),
                    ),
                  )
                : Text(
                    _selectedBirthDate != null
                        ? _formatDate(_selectedBirthDate!)
                        : 'ไม่ระบุ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _selectedBirthDate != null
                          ? Colors.black87
                          : Colors.grey[500],
                    ),
                    textAlign: TextAlign.right,
                  ),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
