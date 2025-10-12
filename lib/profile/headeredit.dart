// headeredit.dart - บันทึกชื่อได้เลย (Auth + Firestore)
// หมายเหตุ: ส่วนอัปโหลดรูป/อัปเดต photoURL ถูกคอมเมนต์ไว้แล้ว (TODO เปิดใช้เมื่อเปิด Storage)

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:my_app/services/firebase_storage_service.dart';

class HeaderEditDialog {
  /// แสดง Dialog สำหรับแก้ไขโปรไฟล์ผู้ใช้
  static void show({
    required BuildContext context,
    required Function(String?, File?) onSave,
    String? currentDisplayName,
    File? currentImage,
  }) {
    final TextEditingController nameController = TextEditingController();
    final user = FirebaseAuth.instance.currentUser;
    File? selectedImage = currentImage;
    final ImagePicker picker = ImagePicker();
    bool isLoading = false;

    nameController.text = currentDisplayName ?? user?.displayName ?? 'ผู้ใช้';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'แก้ไขโปรไฟล์',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Avatar + edit button
                    Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.grey[300]!,
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.red,
                            backgroundImage: selectedImage != null
                                ? FileImage(selectedImage!)
                                : (user?.photoURL != null
                                          ? NetworkImage(user!.photoURL!)
                                          : null)
                                      as ImageProvider<Object>?,
                            child:
                                selectedImage == null && user?.photoURL == null
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 50,
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: isLoading
                                ? null
                                : () => _showImagePickerDialog(
                                    context: context,
                                    picker: picker,
                                    onImageSelected: (File? image) {
                                      setDialogState(() {
                                        selectedImage = image;
                                      });
                                    },
                                    currentImage: selectedImage,
                                  ),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: isLoading ? Colors.grey : Colors.black,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Name field
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: nameController,
                        enabled: !isLoading,
                        inputFormatters: [
                          FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        ],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'ชื่อที่แสดง',
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (isLoading) ...[
                      const CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'กำลังบันทึกข้อมูล...',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                      const SizedBox(height: 24),
                    ],

                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: isLoading
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    Future.microtask(nameController.dispose);
                                  },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(color: Colors.grey[300]!),
                              ),
                            ),
                            child: Text(
                              'ยกเลิก',
                              style: TextStyle(
                                color: isLoading
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isLoading
                                ? null
                                : () async {
                                    final trimmedName = nameController.text
                                        .trim();

                                    // validate
                                    if (!_isValidDisplayName(trimmedName)) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'ชื่อต้องมีความยาว 2-50 ตัวอักษร และห้ามมีช่องว่างหรืออักขระพิเศษ',
                                            ),
                                            backgroundColor: Colors.orange,
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                      return;
                                    }

                                    // (ถ้ามีรูป ให้เช็กขนาดไว้เฉย ๆ แต่ยังไม่อัปโหลด)
                                    if (selectedImage != null) {
                                      final bytes = await selectedImage!
                                          .length();
                                      if (bytes > 5 * 1024 * 1024) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'รูปภาพขนาดเกิน 5MB',
                                              ),
                                              backgroundColor: Colors.orange,
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                        return;
                                      }
                                    }

                                    setDialogState(() => isLoading = true);

                                    try {
                                      final auth = FirebaseAuth.instance;
                                      final user = auth.currentUser!;

                                      if (selectedImage != null) {
                                        await FirebaseStorageService.updateCompleteProfile(
                                          displayName: trimmedName,
                                          imageFile: selectedImage,
                                        );
                                      } else {
                                        await FirebaseStorageService.updateUserProfile(
                                          displayName: trimmedName,
                                        );
                                      }

                                      await user.reload();
                                      final refreshed =
                                          FirebaseAuth.instance.currentUser;

                                      if (!context.mounted) return;

                                      onSave(
                                        refreshed?.displayName ?? trimmedName,
                                        selectedImage,
                                      );

                                      Navigator.of(context).pop();
                                      Future.microtask(nameController.dispose);

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('อัปเดตโปรไฟล์สำเร็จ'),
                                          backgroundColor: Colors.green,
                                          behavior: SnackBarBehavior.floating,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      setDialogState(() => isLoading = false);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('เกิดข้อผิดพลาด: $e'),
                                          backgroundColor: Colors.red,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isLoading
                                  ? Colors.grey
                                  : Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'บันทึก',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static bool _isValidDisplayName(String name) {
    if (name.trim().isEmpty) return false;
    if (name.trim().length < 2) return false;
    if (name.trim().length > 50) return false;
    if (name.contains(RegExp(r'\s'))) return false;
    final List<String> invalidChars = ['<', '>', '"', "'", '&'];
    for (final ch in invalidChars) {
      if (name.contains(ch)) return false;
    }
    return true;
  }

  static void _showImagePickerDialog({
    required BuildContext context,
    required ImagePicker picker,
    required Function(File?) onImageSelected,
    File? currentImage,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'เลือกรูปภาพ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickImage(
                        context: context,
                        source: ImageSource.camera,
                        picker: picker,
                        onImageSelected: onImageSelected,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.camera_alt,
                              size: 32,
                              color: Colors.black,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'กล้อง',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickImage(
                        context: context,
                        source: ImageSource.gallery,
                        picker: picker,
                        onImageSelected: onImageSelected,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Icons.photo_library,
                              size: 32,
                              color: Colors.black,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'แกลเลอรี่',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              if (currentImage != null ||
                  FirebaseAuth.instance.currentUser?.photoURL != null)
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => _removePhoto(
                      context: context,
                      onImageSelected: onImageSelected,
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'ลบรูปภาพ',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _pickImage({
    required BuildContext context,
    required ImageSource source,
    required ImagePicker picker,
    required Function(File?) onImageSelected,
  }) async {
    Navigator.of(context).pop();
    try {
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        onImageSelected(File(image.path));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('เลือกรูปภาพสำเร็จ'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static void _removePhoto({
    required BuildContext context,
    required Function(File?) onImageSelected,
  }) {
    Navigator.of(context).pop();
    onImageSelected(null);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ลบรูปภาพแล้ว'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
