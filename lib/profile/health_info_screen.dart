// screens/health_info_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_app/profile/my_user.dart';

class HealthInfoScreen extends StatefulWidget {
  const HealthInfoScreen({super.key});

  @override
  State<HealthInfoScreen> createState() => _HealthInfoScreenState();
}

class _HealthInfoScreenState extends State<HealthInfoScreen> {
  bool _isLoading = true;
  MyUser? _currentUser;
  Map<String, dynamic>? _additionalHealthData;
  final user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadHealthData();
  }

  Future<void> _loadHealthData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (user != null) {
        // ดึงข้อมูลจาก users collection (MyUser model)
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .get();

        if (userDoc.exists) {
          setState(() {
            _currentUser = MyUser.fromFirestore(userDoc);
          });
        }

        // ดึงข้อมูลสุขภาพเพิ่มเติมจาก health_profiles (ถ้ามี)
        final healthDoc = await FirebaseFirestore.instance
            .collection('health_profiles')
            .doc(user!.uid)
            .get();

        if (healthDoc.exists) {
          setState(() {
            _additionalHealthData = healthDoc.data();
          });
        }
      }
    } catch (e) {
      print('Error loading health data: $e');
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
          'ข้อมูลสุขภาพ',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.black),
            onPressed: () {
              _showEditHealthDialog();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // BMI Card
                  _buildBMICard(),
                  const SizedBox(height: 16),

                  // ข้อมูลร่างกายพื้นฐาน
                  _buildHealthCard('ข้อมูลร่างกายพื้นฐาน', [
                    _buildHealthInfoRow(
                      Icons.height,
                      'ส่วนสูง',
                      _currentUser != null && _currentUser!.height > 0
                          ? '${_currentUser!.height.toStringAsFixed(0)} ซม.'
                          : 'ไม่ระบุ',
                    ),
                    _buildHealthInfoRow(
                      Icons.monitor_weight,
                      'น้ำหนัก',
                      _currentUser != null && _currentUser!.weight > 0
                          ? '${_currentUser!.weight.toStringAsFixed(1)} กก.'
                          : 'ไม่ระบุ',
                    ),
                    _buildHealthInfoRow(
                      Icons.warning_amber,
                      'อาหารที่แพ้',
                      _currentUser?.allergies.isEmpty == true
                          ? 'ไม่มีอาหารที่แพ้'
                          : _currentUser?.allergies ?? 'ไม่ระบุ',
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // ข้อมูลสุขภาพเพิ่มเติม
                  _buildHealthCard('ข้อมูลสุขภาพเพิ่มเติม', [
                    _buildHealthInfoRow(
                      Icons.bloodtype,
                      'กรุ๊ปเลือด',
                      _additionalHealthData?['bloodType'] ?? 'ไม่ระบุ',
                    ),
                    _buildHealthInfoRow(
                      Icons.smoking_rooms,
                      'สถานะการสูบบุหรี่',
                      _additionalHealthData?['smokingStatus'] ?? 'ไม่ระบุ',
                    ),
                    _buildHealthInfoRow(
                      Icons.wine_bar,
                      'การดื่มแอลกอฮอล์',
                      _additionalHealthData?['alcoholConsumption'] ?? 'ไม่ระบุ',
                    ),
                    _buildHealthInfoRow(
                      Icons.medication,
                      'ยาที่ใช้ประจำ',
                      _additionalHealthData?['medications']?.isNotEmpty == true
                          ? _additionalHealthData!['medications']
                          : 'ไม่มี',
                    ),
                  ]),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.withOpacity(0.1), Colors.blue.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.blue.withOpacity(0.2),
            child: Text(
              _currentUser?.firstName.isNotEmpty == true
                  ? _currentUser!.firstName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentUser?.fullName ?? 'ผู้ใช้งาน',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _currentUser != null
                      ? '${_currentUser!.gender} • ${_currentUser!.age} ปี'
                      : 'ไม่มีข้อมูล',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _currentUser?.profileCompleted == true
                        ? Colors.green.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _currentUser?.profileCompleted == true
                        ? 'ข้อมูลครบ'
                        : 'ข้อมูลไม่ครบ',
                    style: TextStyle(
                      fontSize: 10,
                      color: _currentUser?.profileCompleted == true
                          ? Colors.green[700]
                          : Colors.orange[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBMICard() {
    final bmi = _currentUser?.bmi ?? 0;
    final bmiCategory = _currentUser?.bmiCategory ?? 'ไม่ทราบ';

    Color bmiColor = Colors.grey;
    if (bmi > 0) {
      if (bmi < 18.5) {
        bmiColor = Colors.blue;
      } else if (bmi < 25) {
        bmiColor = Colors.green;
      } else if (bmi < 30) {
        bmiColor = Colors.orange;
      } else {
        bmiColor = Colors.red;
      }
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bmiColor.withOpacity(0.1), bmiColor.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bmiColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ดัชนีมวลกาย (BMI)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Icon(Icons.health_and_safety, color: bmiColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                bmi > 0 ? bmi.toStringAsFixed(1) : 'ไม่ทราบ',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: bmiColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: bmiColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  bmiCategory,
                  style: TextStyle(
                    color: bmiColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (bmi > 0) ...[
            const SizedBox(height: 12),
            Text(
              _getBMIAdvice(bmi),
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
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

  Widget _buildHealthCard(String title, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildHealthInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
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

  // Helper method สำหรับ format วันที่
  String _formatDate(DateTime date) {
    const List<String> months = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year + 543}';
  }

  // Helper method สำหรับ format timestamp
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return _formatDate(timestamp.toDate());
    }
    return 'ไม่ทราบ';
  }

  void _showEditHealthDialog() {
    final TextEditingController heightController = TextEditingController(
      text: _currentUser?.height != null && _currentUser!.height > 0
          ? _currentUser!.height.toString()
          : '',
    );
    final TextEditingController weightController = TextEditingController(
      text: _currentUser?.weight != null && _currentUser!.weight > 0
          ? _currentUser!.weight.toString()
          : '',
    );
    final TextEditingController allergiesController = TextEditingController(
      text: _currentUser?.allergies ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('แก้ไขข้อมูลสุขภาพ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: heightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'ส่วนสูง (ซม.)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: weightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'น้ำหนัก (กก.)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: allergiesController,
                decoration: const InputDecoration(
                  labelText: 'อาหารที่แพ้',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final height = double.tryParse(heightController.text) ?? 0;
                final weight = double.tryParse(weightController.text) ?? 0;

                // อัปเดตข้อมูลใน users collection
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user!.uid)
                    .update({
                      'height': height,
                      'weight': weight,
                      'allergies': allergiesController.text,
                    });

                Navigator.pop(context);
                _loadHealthData();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('บันทึกข้อมูลสำเร็จ'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('เกิดข้อผิดพลาด: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}
