// headeredit.dart (ไฟล์สมบูรณ์เชื่อมต่อ Firebase)
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class HeaderEditDialog {
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
      barrierDismissible: false, // ป้องกันปิดโดยกดข้างนอก
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
                    // Title
                    const Text(
                      'แก้ไขโปรไฟล์',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Profile Picture Section
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
                                      as ImageProvider?,
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
                              child: Icon(
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

                    // Name Field
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: nameController,
                        enabled: !isLoading,
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

                    // Loading Indicator
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

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: isLoading
                                ? null
                                : () {
                                    nameController.dispose();
                                    Navigator.of(context).pop();
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
                                    // Validate input
                                    final trimmedName = nameController.text
                                        .trim();

                                    if (!_isValidDisplayName(trimmedName)) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'ชื่อต้องมีความยาว 2-50 ตัวอักษร และไม่มีอักขระพิเศษ',
                                          ),
                                          backgroundColor: Colors.orange,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      return;
                                    }

                                    if (selectedImage != null &&
                                        !_isValidImageSize(selectedImage!)) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'ขนาดรูปภาพต้องไม่เกิน 5MB',
                                          ),
                                          backgroundColor: Colors.orange,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      return;
                                    }

                                    // Start loading
                                    setDialogState(() {
                                      isLoading = true;
                                    });

                                    try {
                                      await _saveToFirebase(
                                        displayName: trimmedName,
                                        imageFile: selectedImage,
                                        context: context,
                                      );

                                      // Save changes locally
                                      onSave(trimmedName, selectedImage);

                                      nameController.dispose();
                                      Navigator.of(context).pop();

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
                                      setDialogState(() {
                                        isLoading = false;
                                      });

                                      String errorMessage =
                                          'เกิดข้อผิดพลาดไม่ทราบสาเหตุ';

                                      if (e.toString().contains('network')) {
                                        errorMessage =
                                            'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้';
                                      } else if (e.toString().contains(
                                        'permission',
                                      )) {
                                        errorMessage =
                                            'ไม่มีสิทธิ์ในการแก้ไขข้อมูล';
                                      } else if (e.toString().contains(
                                        'storage',
                                      )) {
                                        errorMessage =
                                            'ไม่สามารถอัปโหลดรูปภาพได้';
                                      }

                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(errorMessage),
                                          backgroundColor: Colors.red,
                                          behavior: SnackBarBehavior.floating,
                                          action: SnackBarAction(
                                            label: 'ลองอีกครั้ง',
                                            textColor: Colors.white,
                                            onPressed: () {
                                              // ปิด SnackBar และลองอีกครั้ง
                                            },
                                          ),
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

  // Validation สำหรับชื่อ
  static bool _isValidDisplayName(String name) {
    if (name.trim().isEmpty) return false;
    if (name.trim().length < 2) return false;
    if (name.trim().length > 50) return false;

    // ห้ามมีอักขระพิเศษบางตัว
    final List<String> invalidChars = ['<', '>', '"', "'", '&'];
    for (String char in invalidChars) {
      if (name.contains(char)) {
        return false;
      }
    }
    return true;
  }

  // Validation สำหรับขนาดไฟล์
  static bool _isValidImageSize(File imageFile) {
    final int fileSizeInBytes = imageFile.lengthSync();
    final double fileSizeInMB = fileSizeInBytes / (1024 * 1024);

    return fileSizeInMB <= 5.0; // จำกัดที่ 5MB
  }

  // บันทึกข้อมูลไป Firebase
  static Future<void> _saveToFirebase({
    required String displayName,
    required File? imageFile,
    required BuildContext context,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('ไม่พบผู้ใช้');

    String? downloadURL;

    try {
      // อัปโหลดรูปภาพถ้ามี
      if (imageFile != null) {
        downloadURL = await _uploadImageToStorage(imageFile, user.uid);
      }

      // อัปเดต Firebase Auth Profile
      await user.updateDisplayName(displayName);
      if (downloadURL != null) {
        await user.updatePhotoURL(downloadURL);
      }

      // บันทึกข้อมูลใน Firestore
      await _saveToFirestore(
        uid: user.uid,
        displayName: displayName,
        photoURL: downloadURL,
        email: user.email,
      );

      // Reload user data
      await user.reload();
    } catch (e) {
      print('Error saving to Firebase: $e');
      throw e;
    }
  }

  // อัปโหลดรูปภาพไป Firebase Storage
  static Future<String> _uploadImageToStorage(
    File imageFile,
    String uid,
  ) async {
    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('profile_images')
          .child('$uid.jpg');

      final uploadTask = storageRef.putFile(
        imageFile,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'uploaded_by': uid,
            'uploaded_at': DateTime.now().toIso8601String(),
          },
        ),
      );

      final snapshot = await uploadTask;
      final downloadURL = await snapshot.ref.getDownloadURL();

      return downloadURL;
    } catch (e) {
      print('Error uploading image: $e');
      throw Exception('ไม่สามารถอัปโหลดรูปภาพได้');
    }
  }

  // บันทึกข้อมูลใน Firestore
  static Future<void> _saveToFirestore({
    required String uid,
    required String displayName,
    String? photoURL,
    String? email,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final docRef = firestore.collection('users').doc(uid);

      // ตรวจสอบว่า document มีอยู่หรือไม่
      final docSnapshot = await docRef.get();

      final data = {
        'displayName': displayName,
        'email': email,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
      };

      if (photoURL != null) {
        data['photoURL'] = photoURL;
        data['hasCustomPhoto'] = true;
      }

      if (docSnapshot.exists) {
        // อัปเดตข้อมูลที่มีอยู่
        await docRef.update(data);
      } else {
        // สร้างข้อมูลใหม่
        data['createdAt'] = FieldValue.serverTimestamp();
        data['profileVersion'] = 1;
        await docRef.set(data);
      }
    } catch (e) {
      print('Error saving to Firestore: $e');
      throw Exception('ไม่สามารถบันทึกข้อมูลได้');
    }
  }

  // Dialog เลือกรูปภาพ
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
              // Handle bar
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

              // Options
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

              // Remove photo option
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

  // เลือกรูปภาพ
  static Future<void> _pickImage({
    required BuildContext context,
    required ImageSource source,
    required ImagePicker picker,
    required Function(File?) onImageSelected,
  }) async {
    Navigator.of(context).pop(); // Close bottom sheet

    try {
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        onImageSelected(File(image.path));

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เลือกรูปภาพสำเร็จ'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ลบรูปภาพ
  static void _removePhoto({
    required BuildContext context,
    required Function(File?) onImageSelected,
  }) {
    Navigator.of(context).pop(); // Close bottom sheet
    onImageSelected(null);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ลบรูปภาพแล้ว'),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
