// screens/modern_account_details_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app/profile/account_details/info_card.dart';
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
                primary: Colors.blue[600]!,
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
      body: CustomScrollView(
        slivers: [
          // Modern App Bar
          SliverAppBar(
            expandedHeight: 120,
            floating: false,
            pinned: true,
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'บัญชีของฉัน',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
              background: Container(color: Colors.black),
            ),
            actions: [
              if (!_isLoading)
                Container(
                  margin: const EdgeInsets.only(right: 16),
                  child: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _isEditing ? Icons.close : Icons.edit,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    onPressed: _toggleEditMode,
                  ),
                ),
            ],
          ),

          // Content
          SliverToBoxAdapter(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : Form(
                    key: _formKey,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          // Profile Header
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  offset: const Offset(0, 4),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 30,
                                  backgroundColor: Colors.blue[100],
                                  child: Text(
                                    _myUser?.firstName.isNotEmpty == true
                                        ? _myUser!.firstName[0].toUpperCase()
                                        : 'U',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[800],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _myUser?.fullName ?? 'ไม่ระบุชื่อ',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _myUser?.email ??
                                            user?.email ??
                                            'ไม่ระบุอีเมล',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // ข้อมูลส่วนตัว
                          ModernInfoCard(
                            title: 'ข้อมูลส่วนตัว',
                            children: [
                              ModernEditableRow(
                                label: 'ชื่อ',
                                value: _myUser?.firstName ?? '',
                                controller: _firstNameController,
                                isEditing: _isEditing,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'กรุณากรอกชื่อ';
                                  }
                                  return null;
                                },
                              ),
                              ModernEditableRow(
                                label: 'นามสกุล',
                                value: _myUser?.lastName ?? '',
                                controller: _lastNameController,
                                isEditing: _isEditing,
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'กรุณากรอกนามสกุล';
                                  }
                                  return null;
                                },
                              ),
                              _buildGenderSelector(),
                              _buildBirthDateSelector(),
                              ModernInfoRow(
                                label: 'อายุ',
                                value: _myUser?.age != null
                                    ? '${_myUser!.age} ปี'
                                    : 'ไม่ระบุ',
                              ),
                            ],
                          ),

                          // ข้อมูลสุขภาพ
                          ModernInfoCard(
                            title: 'ข้อมูลสุขภาพ',
                            children: [
                              ModernEditableRow(
                                label: 'ส่วนสูง (ซม.)',
                                value:
                                    _myUser?.height != null &&
                                        _myUser!.height > 0
                                    ? _myUser!.height.toStringAsFixed(0)
                                    : '',
                                controller: _heightController,
                                isEditing: _isEditing,
                                keyboardType: TextInputType.number,
                              ),
                              ModernEditableRow(
                                label: 'น้ำหนัก (กก.)',
                                value:
                                    _myUser?.weight != null &&
                                        _myUser!.weight > 0
                                    ? _myUser!.weight.toStringAsFixed(0)
                                    : '',
                                controller: _weightController,
                                isEditing: _isEditing,
                                keyboardType: TextInputType.number,
                              ),
                              ModernInfoRow(
                                label: 'BMI',
                                value: _myUser?.bmi != null && _myUser!.bmi > 0
                                    ? '${_myUser!.bmi.toStringAsFixed(1)} (${_myUser!.bmiCategory})'
                                    : 'ไม่ระบุ',
                              ),
                              ModernEditableRow(
                                label: 'ประวัติการแพ้',
                                value: _myUser?.allergies ?? '',
                                controller: _allergiesController,
                                isEditing: _isEditing,
                                maxLines: 2,
                              ),
                            ],
                          ),

                          // ข้อมูลติดต่อ
                          ModernInfoCard(
                            title: 'ข้อมูลติดต่อ',
                            children: [
                              ModernInfoRow(
                                label: 'อีเมล',
                                value:
                                    _myUser?.email ?? user?.email ?? 'ไม่ระบุ',
                              ),
                              ModernEditableRow(
                                label: 'เบอร์โทรศัพท์',
                                value: _myUser?.phoneNumber ?? '',
                                controller: _phoneController,
                                isEditing: _isEditing,
                                keyboardType: TextInputType.phone,
                              ),
                            ],
                          ),

                          // ข้อมูลบัญชี
                          ModernInfoCard(
                            title: 'ข้อมูลบัญชี',
                            children: [
                              ModernInfoRow(
                                label: 'วันที่สมัคร',
                                value: _myUser?.createdAt != null
                                    ? _formatDateFull(_myUser!.createdAt)
                                    : 'ไม่ระบุ',
                              ),
                              ModernInfoRow(
                                label: 'วิธีการล็อกอิน',
                                value: _getProviderName(user),
                              ),
                              ModernInfoRow(
                                label: 'สถานะบัญชี',
                                value: 'ใช้งานได้',
                              ),
                              ModernInfoRow(
                                label: 'การยืนยันตัวตน',
                                value: user?.emailVerified == true
                                    ? 'ยืนยันแล้ว'
                                    : 'ยังไม่ยืนยัน',
                              ),
                            ],
                          ),

                          // ปุ่มบันทึก
                          if (_isEditing) ...[
                            const SizedBox(height: 24),
                            Container(
                              width: double.infinity,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.2),
                                    offset: const Offset(0, 4),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _saveUserData,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: Colors.white,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.save, size: 20),
                                          SizedBox(width: 8),
                                          Text(
                                            'บันทึกข้อมูล',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],

                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.wc, color: Colors.blue[600], size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                'เพศ',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isEditing)
            DropdownButtonFormField<String>(
              value: _selectedGender,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue[600]!, width: 2),
                ),
              ),
              items: ['ชาย', 'หญิง', 'อื่นๆ'].map((gender) {
                return DropdownMenuItem(value: gender, child: Text(gender));
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedGender = value!;
                });
              },
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Text(
                _selectedGender.isEmpty ? 'ไม่ระบุ' : _selectedGender,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBirthDateSelector() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.calendar_today,
                  color: Colors.blue[600],
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'วันเกิด',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _isEditing ? _selectBirthDate : null,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _isEditing ? Colors.white : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _selectedBirthDate != null
                        ? _formatDate(_selectedBirthDate!) // ใช้ ค.ศ.
                        : (_isEditing ? 'เลือกวันเกิด' : 'ไม่ระบุ'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: _selectedBirthDate != null
                          ? Colors.black87
                          : Colors.grey[500],
                    ),
                  ),
                  if (_isEditing)
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                ],
              ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
