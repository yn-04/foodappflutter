// profile_tab.dart (Main Profile Tab)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:my_app/profile/account_details/account_details_screen.dart';
import 'package:my_app/profile/account_settings/account_settings_screen.dart';
import 'package:my_app/profile/family/family_account_screen.dart';
import 'package:my_app/profile/health_info_screen.dart';
import 'dart:io';
import 'headeredit.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  File? _selectedImage;
  String? _updatedDisplayName;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.reload();
        final updatedUser = FirebaseAuth.instance.currentUser;

        String? displayFromFs;
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(updatedUser!.uid)
              .get();

          if (doc.exists) {
            final data = doc.data();
            // ✅ ใช้ username เป็นหลัก
            displayFromFs = (data?['username'] as String?)?.trim();

            // fallback เผื่อยังไม่มี username
            displayFromFs ??= (data?['firstName'] as String?)?.trim();
            displayFromFs ??= (data?['fullName'] as String?)?.trim();
          }
        } catch (_) {
          // เงียบไว้ไม่ให้ล่มหาก Firestore ยังไม่พร้อม
        }

        setState(() {
          _updatedDisplayName = (displayFromFs?.isNotEmpty == true)
              ? displayFromFs
              : (updatedUser?.displayName?.trim().isNotEmpty == true
                    ? updatedUser!.displayName
                    : (updatedUser?.email?.split('@').first ?? 'ผู้ใช้'));

          if (updatedUser?.photoURL != null) {
            _selectedImage = null;
          }
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถโหลดข้อมูลได้: ${e.toString()}'),
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.grey[100],
        elevation: 0,
        title: const Text(
          'โปรไฟล์',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: _loadUserData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : RefreshIndicator(
              onRefresh: _loadUserData,
              color: Colors.black,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 10),

                    // Profile Header Card
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            backgroundColor: Colors.red,
                            backgroundImage: _selectedImage != null
                                ? FileImage(_selectedImage!)
                                : (user?.photoURL != null
                                          ? NetworkImage(user!.photoURL!)
                                          : null)
                                      as ImageProvider?,
                            key: ValueKey(
                              '${user?.photoURL ?? ''}_${_selectedImage?.path ?? ''}',
                            ),
                            child:
                                _selectedImage == null && user?.photoURL == null
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 30,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _updatedDisplayName ??
                                      user?.displayName ??
                                      'ผู้ใช้',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user?.email ?? '',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _showEditProfileDialog(),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.edit,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // ข้อมูลส่วนตัว Section
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _buildProfileMenuItem(
                            icon: Icons.person_outline,
                            title: 'บัญชีของฉัน',
                            subtitle: 'ข้อมูลส่วนตัวและการติดต่อ',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const ModernAccountDetailsScreen(),
                                ),
                              );
                            },
                          ),
                          _buildDivider(),
                          _buildProfileMenuItem(
                            icon: Icons.health_and_safety_outlined,
                            title: 'ข้อมูลสุขภาพ',
                            subtitle: 'BMI, เป้าหมาย, ภูมิแพ้',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const HealthInfoScreen(),
                                ),
                              );
                            },
                          ),
                          _buildDivider(),
                          _buildProfileMenuItem(
                            icon: Icons.family_restroom_outlined,
                            title: 'บัญชีครอบครัว',
                            subtitle: 'จัดการสมาชิกในครอบครัว',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const FamilyAccountScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // การตั้งค่า Section
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 4, bottom: 12),
                            child: Text(
                              'การตั้งค่า',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                _buildProfileMenuItem(
                                  icon: Icons.settings_outlined,
                                  title: 'การตั้งค่าบัญชี',
                                  subtitle: 'ความปลอดภัย, การแจ้งเตือน',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const AccountSettingsScreen(),
                                      ),
                                    );
                                  },
                                ),
                                _buildDivider(),
                                _buildProfileMenuItem(
                                  icon: Icons.fingerprint,
                                  title: 'Face ID / Touch ID',
                                  subtitle: 'ความปลอดภัยชีวมิติ',
                                  onTap: () {},
                                  hasSwitch: true,
                                ),
                                _buildDivider(),
                                _buildProfileMenuItem(
                                  icon: Icons.notifications_outlined,
                                  title: 'การแจ้งเตือน',
                                  subtitle: 'ตั้งค่าการแจ้งเตือนต่างๆ',
                                  onTap: () {},
                                ),
                                _buildDivider(),
                                _buildProfileMenuItem(
                                  icon: Icons.share_outlined,
                                  title: 'แชร์แอป',
                                  subtitle: 'แชร์แอปกับเพื่อนๆ',
                                  onTap: () {},
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // เพิ่มเติม Section
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 4, bottom: 12),
                            child: Text(
                              'เพิ่มเติม',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                _buildProfileMenuItem(
                                  icon: Icons.help_outline,
                                  title: 'ข้อมูลการสนับสนุน',
                                  onTap: () {},
                                ),
                                _buildDivider(),
                                _buildProfileMenuItem(
                                  icon: Icons.info_outline,
                                  title: 'ข้อมูลพื้นฐาน',
                                  onTap: () {},
                                ),
                                _buildDivider(),
                                _buildProfileMenuItem(
                                  icon: Icons.favorite_outline,
                                  title: 'เกี่ยวกับแอปพลิเคชัน',
                                  onTap: () {},
                                ),
                                _buildDivider(),
                                _buildProfileMenuItem(
                                  icon: Icons.logout,
                                  title: 'ออกจากระบบ',
                                  onTap: () => _showLogoutDialog(context),
                                  isDestructive: true,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
    );
  }

  void _showEditProfileDialog() {
    HeaderEditDialog.show(
      context: context,
      currentDisplayName: _updatedDisplayName,
      currentImage: _selectedImage,
      onSave: (String? newName, File? newImage) async {
        setState(() {
          if (newName != null && newName.isNotEmpty) {
            _updatedDisplayName = newName;
          }
          _selectedImage = newImage;
        });

        await Future.delayed(const Duration(milliseconds: 500));
        await _loadUserData();

        setState(() {});
      },
    );
  }

  Widget _buildProfileMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool hasSwitch = false,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isDestructive ? Colors.red : Colors.grey[600],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDestructive ? Colors.red : Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
            if (hasSwitch)
              Switch(
                value: false,
                onChanged: (value) {},
                activeColor: Colors.black,
              )
            else
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 1,
      color: Colors.grey[200],
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'ออกจากระบบ',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
          content: const Text(
            'คุณต้องการออกจากระบบหรือไม่?',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'ยกเลิก',
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ),
            ),
            TextButton(
              onPressed: () async {
                try {
                  // Close dialog first
                  Navigator.of(context).pop();

                  // Sign out from Firebase
                  await FirebaseAuth.instance.signOut();

                  // Navigate to login screen and clear all previous routes
                  if (context.mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/login', // หรือ route name ของหน้า login ที่คุณใช้
                      (Route<dynamic> route) => false,
                    );
                  }

                  // Optional: Show success message
                  // ScaffoldMessenger.of(context).showSnackBar(
                  //   const SnackBar(
                  //     content: Text('ออกจากระบบสำเร็จ'),
                  //     backgroundColor: Colors.green,
                  //     behavior: SnackBarBehavior.floating,
                  //   ),
                  // );
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
              },
              child: const Text(
                'ออกจากระบบ',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
