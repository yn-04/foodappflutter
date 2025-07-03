// profile_tab.dart (ไฟล์สมบูรณ์)
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'headeredit.dart';

// สร้างหน้า AccountDetailsScreen ในไฟล์เดียวกันก่อน
class AccountDetailsScreen extends StatefulWidget {
  const AccountDetailsScreen({super.key});

  @override
  State<AccountDetailsScreen> createState() => _AccountDetailsScreenState();
}

class _AccountDetailsScreenState extends State<AccountDetailsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  final user = FirebaseAuth.instance.currentUser;

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
      if (user != null) {
        // ดึงข้อมูลจาก Firestore registrations collection
        final doc = await FirebaseFirestore.instance
            .collection('registrations')
            .doc(user!.uid)
            .get();

        if (doc.exists) {
          setState(() {
            _userData = doc.data();
          });
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
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
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.grey[100],
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'บัญชีของฉัน',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Profile Summary
                  const SizedBox(height: 20),

                  // ข้อมูลส่วนตัว
                  _buildInfoCard('ข้อมูลส่วนตัว', [
                    _buildInfoRow('ชื่อ', _userData?['firstName'] ?? 'ไม่ระบุ'),
                    _buildInfoRow(
                      'นามสกุล',
                      _userData?['lastName'] ?? 'ไม่ระบุ',
                    ),
                    _buildInfoRow('เพศ', _userData?['gender'] ?? 'ไม่ระบุ'),
                    _buildInfoRow(
                      'วันเกิด',
                      _formatDate(_userData?['birthDate']),
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // ข้อมูลร่างกาย
                  _buildInfoCard('ข้อมูลร่างกาย', [
                    _buildInfoRow(
                      'ส่วนสูง',
                      _userData?['height'] != null
                          ? '${_userData!['height']} ซม.'
                          : 'ไม่ระบุ',
                    ),
                    _buildInfoRow(
                      'น้ำหนัก',
                      _userData?['weight'] != null
                          ? '${_userData!['weight']} กก.'
                          : 'ไม่ระบุ',
                    ),
                    _buildInfoRow(
                      'ภูมิแพ้',
                      _userData?['allergies']?.isNotEmpty == true
                          ? _userData!['allergies']
                          : 'ไม่มี',
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // ข้อมูลบัญชี
                  _buildInfoCard('ข้อมูลบัญชี', [
                    _buildInfoRow(
                      'User ID',
                      _userData?['userId'] ?? user?.uid ?? 'ไม่ทราบ',
                    ),
                    _buildInfoRow(
                      'วันที่สมัคร',
                      _formatDate(_userData?['registrationDate']),
                    ),
                  ]),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'ไม่ระบุ';

    DateTime? dateTime;
    if (date is Timestamp) {
      dateTime = date.toDate();
    } else if (date is DateTime) {
      dateTime = date;
    } else {
      return 'ไม่ระบุ';
    }

    return '${dateTime.day}/${dateTime.month}/${dateTime.year + 543}';
  }
}

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

  // โหลดข้อมูลผู้ใช้จาก Firebase
  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Reload user data from Firebase Auth
        await user.reload();

        // ดึง updated user instance
        final updatedUser = FirebaseAuth.instance.currentUser;

        // อัปเดต state ด้วยข้อมูลล่าสุด
        setState(() {
          _updatedDisplayName = updatedUser?.displayName;
          // รีเซ็ต selectedImage ถ้ามีการอัปเดตรูปใน Firebase
          if (updatedUser?.photoURL != null) {
            _selectedImage = null; // ให้ใช้รูปจาก Firebase แทน
          }
        });
      }
    } catch (e) {
      print('Error loading user data: $e');

      // แสดง error message
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

                    // Profile Header Card (แก้ไขได้)
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
                            child:
                                _selectedImage == null && user?.photoURL == null
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 30,
                                  )
                                : null,
                            key: ValueKey(
                              '${user?.photoURL ?? ''}_${_selectedImage?.path ?? ''}',
                            ),
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
                                color: Colors.white.withOpacity(0.1),
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

                    // Menu Items
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
                            subtitle: 'ข้อมูลส่วนตัวของคุณ',
                            onTap: () {
                              print(
                                'Navigating to AccountDetailsScreen',
                              ); // Debug
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const AccountDetailsScreen(),
                                ),
                              ).then((_) {
                                print(
                                  'Returned from AccountDetailsScreen',
                                ); // Debug
                              });
                            },
                          ),
                          _buildDivider(),
                          _buildProfileMenuItem(
                            icon: Icons.help_outline,
                            title: 'ข้อมูลการสนับสนุน',
                            subtitle: 'ข้อมูลสำคัญ',
                            onTap: () {},
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
                            title: 'บัญชีการแจ้งเตือน',
                            subtitle: 'ตั้งค่าการแจ้งเตือนต่างๆ',
                            onTap: () {},
                          ),
                          _buildDivider(),
                          _buildProfileMenuItem(
                            icon: Icons.share_outlined,
                            title: 'วงการแชร์',
                            subtitle: 'แชร์แอปกับเพื่อนๆ',
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 30),

                    // More Section
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 4, bottom: 12),
                            child: Text(
                              'More',
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

                    const SizedBox(height: 100), // Space for bottom navigation
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
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
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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

  String _formatDate(DateTime? date) {
    if (date == null) return 'ไม่ทราบ';

    final months = [
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

    return '${date.day} ${months[date.month - 1]} ${date.year + 543}';
  }

  // ใช้ HeaderEditDialog แทน dialog เดิม
  void _showEditProfileDialog() {
    HeaderEditDialog.show(
      context: context,
      currentDisplayName: _updatedDisplayName,
      currentImage: _selectedImage,
      onSave: (String? newName, File? newImage) async {
        // อัปเดต state ทันที
        setState(() {
          if (newName != null && newName.isNotEmpty) {
            _updatedDisplayName = newName;
          }
          _selectedImage = newImage;
        });

        // รีโหลดข้อมูลจาก Firebase เพื่อให้แน่ใจว่าข้อมูลล่าสุด
        await Future.delayed(const Duration(milliseconds: 500));
        await _loadUserData();

        // แสดงข้อมูลที่อัปเดตแล้ว
        setState(() {
          // Force rebuild with new data
        });
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
                  await FirebaseAuth.instance.signOut();
                  Navigator.of(context).pop();

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ออกจากระบบสำเร็จ'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('เกิดข้อผิดพลาด: $e'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
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
