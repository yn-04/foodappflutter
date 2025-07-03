import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
  }

  Future<void> _signOut() async {
    try {
      await _auth.signOut();
      Navigator.pushReplacementNamed(context, '/register');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาดในการออกจากระบบ'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text('Kubb App'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'ออกจากระบบ',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[600]!, Colors.blue[50]!],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Welcome Section
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.check_circle, size: 80, color: Colors.green),
                      SizedBox(height: 16),
                      Text(
                        'ยินดีต้อนรับ!',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        _currentUser?.displayName ?? 'ผู้ใช้',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'ลงทะเบียนเสร็จสมบูรณ์แล้ว',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 24),

                // Quick Actions
                Text(
                  'เมนูหลัก',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 16),

                // Menu Grid
                GridView.count(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildMenuCard(
                      icon: Icons.person,
                      title: 'โปรไฟล์',
                      subtitle: 'ดูข้อมูลส่วนตัว',
                      color: Colors.orange,
                      onTap: () {
                        // นำทางไปหน้าโปรไฟล์
                        _showComingSoon();
                      },
                    ),
                    _buildMenuCard(
                      icon: Icons.settings,
                      title: 'ตั้งค่า',
                      subtitle: 'จัดการการตั้งค่า',
                      color: Colors.purple,
                      onTap: () {
                        // นำทางไปหน้าตั้งค่า
                        _showComingSoon();
                      },
                    ),
                    _buildMenuCard(
                      icon: Icons.notifications,
                      title: 'การแจ้งเตือน',
                      subtitle: 'ดูการแจ้งเตือน',
                      color: Colors.red,
                      onTap: () {
                        // นำทางไปหน้าการแจ้งเตือน
                        _showComingSoon();
                      },
                    ),
                    _buildMenuCard(
                      icon: Icons.help_outline,
                      title: 'ช่วยเหลือ',
                      subtitle: 'คำถามที่พบบ่อย',
                      color: Colors.teal,
                      onTap: () {
                        // นำทางไปหน้าช่วยเหลือ
                        _showComingSoon();
                      },
                    ),
                  ],
                ),

                SizedBox(height: 24),

                // Information Card
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue[600],
                            size: 24,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'ข้อมูลบัญชี',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      _buildInfoRow('อีเมล', _currentUser?.email ?? 'ไม่ระบุ'),
                      _buildInfoRow(
                        'สถานะการยืนยัน',
                        _currentUser?.emailVerified == true
                            ? 'ยืนยันแล้ว'
                            : 'ยังไม่ได้ยืนยัน',
                      ),
                      _buildInfoRow(
                        'วันที่สมัครสมาชิก',
                        _currentUser?.metadata.creationTime != null
                            ? '${_currentUser!.metadata.creationTime!.day}/${_currentUser!.metadata.creationTime!.month}/${_currentUser!.metadata.creationTime!.year}'
                            : 'ไม่ทราบ',
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 32),

                // Action Buttons
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // เริ่มใช้งานหลัก
                          _showComingSoon();
                        },
                        icon: Icon(Icons.play_arrow),
                        label: Text(
                          'เริ่มใช้งานแอป',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton.icon(
                        onPressed: _signOut,
                        icon: Icon(Icons.logout),
                        label: Text(
                          'ออกจากระบบ',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ),
          Text(': ', style: TextStyle(color: Colors.grey[600])),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                color: Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showComingSoon() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Coming Soon'),
        content: Text('ฟีเจอร์นี้จะเปิดให้ใช้งานในเร็วๆ นี้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('ตกลง'),
          ),
        ],
      ),
    );
  }
}
