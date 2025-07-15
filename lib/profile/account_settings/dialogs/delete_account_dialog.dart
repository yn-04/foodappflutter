// dialogs/delete_account_dialog.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _confirmDelete = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red[600], size: 28),
          const SizedBox(width: 12),
          const Text(
            'ลบบัญชีถาวร',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⚠️ คำเตือนสำคัญ',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.red[800],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'การลบบัญชีจะทำให้ข้อมูลต่อไปนี้หายไปถาวร:',
                      style: TextStyle(color: Colors.red[700], fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• ข้อมูลส่วนตัวทั้งหมด\n'
                      '• ข้อมูลสุขภาพและอาหารที่แพ้\n'
                      '• ประวัติการใช้งาน\n'
                      '• ข้อมูลครอบครัว\n'
                      '• การตั้งค่าทั้งหมด',
                      style: TextStyle(color: Colors.red[700], fontSize: 13),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Text(
                'กรุณายืนยันรหัสผ่านเพื่อดำเนินการ:',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[800],
                ),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'รหัสผ่านปัจจุบัน',
                  hintText: 'กรอกรหัสผ่านของคุณ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอกรหัสผ่าน';
                  }
                  if (value.length < 6) {
                    return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _confirmController,
                decoration: InputDecoration(
                  labelText: 'พิมพ์ "ลบบัญชี" เพื่อยืนยัน',
                  hintText: 'ลบบัญชี',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.edit_outlined),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณาพิมพ์ "ลบบัญชี" เพื่อยืนยัน';
                  }
                  if (value.trim() != 'ลบบัญชี') {
                    return 'กรุณาพิมพ์ "ลบบัญชี" ให้ถูกต้อง';
                  }
                  return null;
                },
                onChanged: (value) {
                  setState(() {
                    _confirmDelete = value.trim() == 'ลบบัญชี';
                  });
                },
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Checkbox(
                    value: _confirmDelete,
                    onChanged: (value) {
                      setState(() => _confirmDelete = value ?? false);
                    },
                    activeColor: Colors.red,
                  ),
                  Expanded(
                    child: Text(
                      'ฉันเข้าใจและยอมรับว่าการดำเนินการนี้ไม่สามารถย้อนกลับได้',
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('ยกเลิก', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: (_isLoading || !_confirmDelete) ? null : _deleteAccount,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
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
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('ลบบัญชีถาวร'),
        ),
      ],
    );
  }

  Future<void> _deleteAccount() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_confirmDelete) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('ไม่พบข้อมูลผู้ใช้');
      }

      // Step 1: Re-authenticate user
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _passwordController.text,
      );

      await user.reauthenticateWithCredential(credential);

      // Step 2: Delete user data from Firestore
      await _deleteUserData(user.uid);

      // Step 3: Delete Firebase Auth account
      await user.delete();

      if (mounted) {
        Navigator.pop(context); // Close dialog

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ลบบัญชีสำเร็จ ขอบคุณที่ใช้บริการของเรา'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // Navigate to login/welcome screen
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/login', // หรือ route ที่คุณใช้สำหรับหน้า login
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'wrong-password':
          errorMessage = 'รหัสผ่านไม่ถูกต้อง';
          break;
        case 'user-not-found':
          errorMessage = 'ไม่พบบัญชีผู้ใช้';
          break;
        case 'requires-recent-login':
          errorMessage = 'กรุณาออกจากระบบและเข้าสู่ระบบใหม่ก่อนลบบัญชี';
          break;
        case 'network-request-failed':
          errorMessage = 'ไม่สามารถเชื่อมต่อเครือข่ายได้';
          break;
        default:
          errorMessage = 'เกิดข้อผิดพลาด: ${e.message}';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการลบบัญชี: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteUserData(String userId) async {
    final firestore = FirebaseFirestore.instance;

    try {
      // Delete from multiple collections
      final collections = [
        'users',
        'user_settings',
        'user_health_data',
        'user_allergies',
        'user_family',
        'user_activities',
        'user_notifications',
      ];

      // Delete documents in parallel for better performance
      final deleteFutures = collections.map((collection) async {
        try {
          await firestore.collection(collection).doc(userId).delete();
        } catch (e) {
          print('Warning: Could not delete from $collection: $e');
          // Continue with other deletions even if one fails
        }
      });

      await Future.wait(deleteFutures);

      // Also delete any subcollections if they exist
      await _deleteSubcollections(userId);
    } catch (e) {
      print('Error deleting user data: $e');
      // Don't throw here as we still want to try deleting the auth account
    }
  }

  Future<void> _deleteSubcollections(String userId) async {
    final firestore = FirebaseFirestore.instance;

    try {
      // Example: Delete user's health records subcollection
      final healthRecords = await firestore
          .collection('users')
          .doc(userId)
          .collection('health_records')
          .get();

      for (final doc in healthRecords.docs) {
        await doc.reference.delete();
      }

      // Add other subcollections as needed
    } catch (e) {
      print('Warning: Could not delete subcollections: $e');
    }
  }
}
