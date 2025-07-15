// screens/family/dialogs/add_member_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddMemberDialog {
  static void show({
    required BuildContext context,
    required Function(Map<String, dynamic>) onAddMember,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddMemberDialogContent(onAddMember: onAddMember),
    );
  }
}

class _AddMemberDialogContent extends StatefulWidget {
  final Function(Map<String, dynamic>) onAddMember;

  const _AddMemberDialogContent({required this.onAddMember});

  @override
  State<_AddMemberDialogContent> createState() =>
      _AddMemberDialogContentState();
}

class _AddMemberDialogContentState extends State<_AddMemberDialogContent> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ageController = TextEditingController();

  String _selectedRelationship = 'สมาชิก';
  String _selectedGender = 'ไม่ระบุ';
  bool _isLoading = false;

  final List<String> _relationships = [
    'สมาชิก',
    'คู่สมรส',
    'บุตร',
    'บุตรี',
    'บิดา',
    'มารดา',
    'พี่ชาย',
    'พี่สาว',
    'น้องชาย',
    'น้องสาว',
    'ปู่',
    'ย่า',
    'ตา',
    'ยาย',
    'ญาติ',
    'เพื่อน',
  ];

  final List<String> _genders = ['ไม่ระบุ', 'ชาย', 'หญิง', 'อื่นๆ'];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.person_add, color: Colors.blue[600], size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'เพิ่มสมาชิกใหม่',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Name field
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อ-นามสกุล *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'กรุณากรอกชื่อ-นามสกุล';
                    }
                    if (value.trim().length < 2) {
                      return 'ชื่อต้องมีอย่างน้อย 2 ตัวอักษร';
                    }
                    return null;
                  },
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),

                // Email field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'อีเมล',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                    hintText: 'example@email.com',
                  ),
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (!RegExp(
                        r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                      ).hasMatch(value)) {
                        return 'รูปแบบอีเมลไม่ถูกต้อง';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Phone field
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[\d\-\(\)\+\s]'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'เบอร์โทรศัพท์',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                    hintText: '08X-XXX-XXXX',
                  ),
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      final cleanPhone = value.replaceAll(
                        RegExp(r'[\s\-\(\)]'),
                        '',
                      );
                      if (cleanPhone.length < 9 || cleanPhone.length > 15) {
                        return 'เบอร์โทรศัพท์ไม่ถูกต้อง';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Age and Gender row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _ageController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'อายุ',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.cake),
                          suffixText: 'ปี',
                        ),
                        validator: (value) {
                          if (value != null && value.isNotEmpty) {
                            final age = int.tryParse(value);
                            if (age == null || age < 1 || age > 150) {
                              return 'อายุไม่ถูกต้อง';
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        value: _selectedGender,
                        decoration: const InputDecoration(
                          labelText: 'เพศ',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.wc),
                        ),
                        items: _genders
                            .map(
                              (gender) => DropdownMenuItem(
                                value: gender,
                                child: Text(gender),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedGender = value!;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Relationship field
                DropdownButtonFormField<String>(
                  value: _selectedRelationship,
                  decoration: const InputDecoration(
                    labelText: 'ความสัมพันธ์ *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.family_restroom),
                  ),
                  items: _relationships
                      .map(
                        (relationship) => DropdownMenuItem(
                          value: relationship,
                          child: Text(relationship),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedRelationship = value!;
                    });
                  },
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'กรุณาเลือกความสัมพันธ์';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Info note
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue[600],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ข้อมูลที่มี * จำเป็นต้องกรอก',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[300],
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('เพิ่มสมาชิก'),
        ),
      ],
    );
  }

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final memberData = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'age': _ageController.text.isNotEmpty
            ? int.parse(_ageController.text)
            : null,
        'gender': _selectedGender,
        'relationship': _selectedRelationship,
      };

      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));

      widget.onAddMember(memberData);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เพิ่มสมาชิก "${memberData['name']}" สำเร็จ'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
