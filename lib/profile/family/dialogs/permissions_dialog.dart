// screens/family/dialogs/permissions_dialog.dart
import 'package:flutter/material.dart';

class PermissionsDialog {
  static void show({
    required BuildContext context,
    required Map<String, bool> currentPermissions,
    required Function(Map<String, bool>) onSave,
  }) {
    showDialog(
      context: context,
      builder: (context) => _PermissionsDialogContent(
        currentPermissions: currentPermissions,
        onSave: onSave,
      ),
    );
  }
}

class _PermissionsDialogContent extends StatefulWidget {
  final Map<String, bool> currentPermissions;
  final Function(Map<String, bool>) onSave;

  const _PermissionsDialogContent({
    required this.currentPermissions,
    required this.onSave,
  });

  @override
  State<_PermissionsDialogContent> createState() =>
      _PermissionsDialogContentState();
}

class _PermissionsDialogContentState extends State<_PermissionsDialogContent>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late Map<String, bool> _permissions;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _permissions = Map.from(widget.currentPermissions);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.security,
                      color: Colors.orange[700],
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'สิทธิ์การเข้าถึงข้อมูล',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'กำหนดสิทธิ์เริ่มต้นสำหรับสมาชิกใหม่',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Tab bar
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
              ),
              child: TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'ข้อมูลสุขภาพ'),
                  Tab(text: 'การแจ้งเตือน'),
                  Tab(text: 'ฟีเจอร์พิเศษ'),
                ],
                labelColor: Colors.orange[700],
                unselectedLabelColor: Colors.grey[600],
                indicatorColor: Colors.orange[700],
                labelStyle: const TextStyle(fontSize: 12),
              ),
            ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildHealthPermissionsTab(),
                  _buildNotificationPermissionsTab(),
                  _buildSpecialPermissionsTab(),
                ],
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange[600],
                        foregroundColor: Colors.white,
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('บันทึก'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthPermissionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPermissionSection(
            title: 'ข้อมูลพื้นฐาน',
            icon: Icons.health_and_safety,
            color: Colors.green,
            permissions: [
              PermissionItem(
                key: 'viewGeneralHealth',
                title: 'ดูข้อมูลสุขภาพทั่วไป',
                subtitle: 'สถานะสุขภาพ, การตรวจสุขภาพ',
                value: _permissions['viewGeneralHealth'] ?? false,
                onChanged: (value) =>
                    _updatePermission('viewGeneralHealth', value),
              ),
              PermissionItem(
                key: 'viewBMI',
                title: 'ดูข้อมูล BMI และน้ำหนัก',
                subtitle: 'ค่า BMI, น้ำหนัก, ส่วนสูง',
                value: _permissions['viewBMI'] ?? false,
                onChanged: (value) => _updatePermission('viewBMI', value),
              ),
              PermissionItem(
                key: 'viewAllergies',
                title: 'ดูข้อมูลภูมิแพ้',
                subtitle: 'รายการอาหารและยาที่แพ้',
                value: _permissions['viewAllergies'] ?? false,
                onChanged: (value) => _updatePermission('viewAllergies', value),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildPermissionSection(
            title: 'ข้อมูลละเอียด',
            icon: Icons.medical_information,
            color: Colors.blue,
            permissions: [
              PermissionItem(
                key: 'viewExercise',
                title: 'ดูประวัติการออกกำลังกาย',
                subtitle: 'กิจกรรม, ระยะเวลา, แคลอรี่',
                value: _permissions['viewExercise'] ?? false,
                onChanged: (value) => _updatePermission('viewExercise', value),
              ),
              PermissionItem(
                key: 'viewMedications',
                title: 'ดูข้อมูลยาที่ใช้',
                subtitle: 'ยาที่ทาน, ปริมาณ, เวลา',
                value: _permissions['viewMedications'] ?? false,
                onChanged: (value) =>
                    _updatePermission('viewMedications', value),
              ),
              PermissionItem(
                key: 'viewMedicalHistory',
                title: 'ดูประวัติการรักษา',
                subtitle: 'โรคประจำตัว, การผ่าตัด',
                value: _permissions['viewMedicalHistory'] ?? false,
                onChanged: (value) =>
                    _updatePermission('viewMedicalHistory', value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationPermissionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPermissionSection(
            title: 'การแจ้งเตือนฉุกเฉิน',
            icon: Icons.emergency,
            color: Colors.red,
            permissions: [
              PermissionItem(
                key: 'emergencyNotifications',
                title: 'รับการแจ้งเตือนฉุกเฉิน',
                subtitle: 'เมื่อมีเหตุการณ์ฉุกเฉินเกิดขึ้น',
                value: _permissions['emergencyNotifications'] ?? false,
                onChanged: (value) =>
                    _updatePermission('emergencyNotifications', value),
                isRecommended: true,
              ),
              PermissionItem(
                key: 'criticalHealthAlerts',
                title: 'แจ้งเตือนสุขภาพวิกฤติ',
                subtitle: 'ค่าสุขภาพผิดปกติอย่างรุนแรง',
                value: _permissions['criticalHealthAlerts'] ?? false,
                onChanged: (value) =>
                    _updatePermission('criticalHealthAlerts', value),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildPermissionSection(
            title: 'การแจ้งเตือนทั่วไป',
            icon: Icons.notifications,
            color: Colors.purple,
            permissions: [
              PermissionItem(
                key: 'receiveReminders',
                title: 'รับการแจ้งเตือนดูแลสุขภาพ',
                subtitle: 'เตือนทานยา, ออกกำลังกาย, ตรวจสุขภาพ',
                value: _permissions['receiveReminders'] ?? false,
                onChanged: (value) =>
                    _updatePermission('receiveReminders', value),
              ),
              PermissionItem(
                key: 'weeklyReports',
                title: 'รับรายงานสุขภาพรายสัปดาห์',
                subtitle: 'สรุปสุขภาพของครอบครัว',
                value: _permissions['weeklyReports'] ?? false,
                onChanged: (value) => _updatePermission('weeklyReports', value),
              ),
              PermissionItem(
                key: 'achievementNotifications',
                title: 'แจ้งเตือนความสำเร็จ',
                subtitle: 'เมื่อบรรลุเป้าหมายสุขภาพ',
                value: _permissions['achievementNotifications'] ?? false,
                onChanged: (value) =>
                    _updatePermission('achievementNotifications', value),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialPermissionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPermissionSection(
            title: 'การจัดการข้อมูล',
            icon: Icons.admin_panel_settings,
            color: Colors.teal,
            permissions: [
              PermissionItem(
                key: 'editOwnProfile',
                title: 'แก้ไขข้อมูลส่วนตัว',
                subtitle: 'เปลี่ยนข้อมูลโปรไฟล์ของตนเอง',
                value: _permissions['editOwnProfile'] ?? false,
                onChanged: (value) =>
                    _updatePermission('editOwnProfile', value),
                isRecommended: true,
              ),
              PermissionItem(
                key: 'shareHealthData',
                title: 'แชร์ข้อมูลสุขภาพ',
                subtitle: 'แชร์ข้อมูลกับสมาชิกอื่น',
                value: _permissions['shareHealthData'] ?? false,
                onChanged: (value) =>
                    _updatePermission('shareHealthData', value),
              ),
              PermissionItem(
                key: 'exportData',
                title: 'ส่งออกข้อมูลส่วนตัว',
                subtitle: 'ดาวน์โหลดข้อมูลของตนเอง',
                value: _permissions['exportData'] ?? false,
                onChanged: (value) => _updatePermission('exportData', value),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildPermissionSection(
            title: 'ฟีเจอร์ขั้นสูง',
            icon: Icons.star,
            color: Colors.amber,
            permissions: [
              PermissionItem(
                key: 'aiInsights',
                title: 'ใช้ AI วิเคราะห์สุขภาพ',
                subtitle: 'คำแนะนำจาก AI เพื่อสุขภาพที่ดี',
                value: _permissions['aiInsights'] ?? false,
                onChanged: (value) => _updatePermission('aiInsights', value),
              ),
              PermissionItem(
                key: 'telemedicine',
                title: 'ใช้บริการ Telemedicine',
                subtitle: 'ปรึกษาแพทย์ออนไลน์',
                value: _permissions['telemedicine'] ?? false,
                onChanged: (value) => _updatePermission('telemedicine', value),
              ),
              PermissionItem(
                key: 'researchParticipation',
                title: 'เข้าร่วมการวิจัยสุขภาพ',
                subtitle: 'ใช้ข้อมูลเพื่อการวิจัย (ไม่ระบุตัวตน)',
                value: _permissions['researchParticipation'] ?? false,
                onChanged: (value) =>
                    _updatePermission('researchParticipation', value),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildInfoCard(),
        ],
      ),
    );
  }

  Widget _buildPermissionSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<PermissionItem> permissions,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: color.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          ...permissions.map((permission) => _buildPermissionTile(permission)),
        ],
      ),
    );
  }

  Widget _buildPermissionTile(PermissionItem permission) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        permission.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (permission.isRecommended)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'แนะนำ',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  permission.subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: permission.value,
            onChanged: permission.onChanged,
            activeColor: Colors.orange[600],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        children: [
          Icon(Icons.info_outline, color: Colors.blue[600], size: 24),
          const SizedBox(height: 8),
          Text(
            'ข้อมูลสำคัญ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '• การตั้งค่านี้เป็นค่าเริ่มต้นสำหรับสมาชิกใหม่\n'
            '• สมาชิกสามารถเปลี่ยนการตั้งค่าได้ในภายหลัง\n'
            '• ข้อมูลส่วนตัวจะได้รับการปกป้องตามนীติกรรมคุ้มครองข้อมูล',
            style: TextStyle(fontSize: 12, color: Colors.blue[600]),
          ),
        ],
      ),
    );
  }

  void _updatePermission(String key, bool value) {
    setState(() {
      _permissions[key] = value;
    });
  }

  void _handleSave() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));

      widget.onSave(_permissions);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกการตั้งค่าสิทธิ์สำเร็จ'),
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

class PermissionItem {
  final String key;
  final String title;
  final String subtitle;
  final bool value;
  final Function(bool) onChanged;
  final bool isRecommended;

  PermissionItem({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.isRecommended = false,
  });
}
