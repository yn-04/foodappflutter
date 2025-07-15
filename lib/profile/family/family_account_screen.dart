// screens/family/family_account_screen.dart (Main Screen)
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'widgets/family_overview_card.dart';
import 'widgets/quick_actions_row.dart';
import 'widgets/family_members_list.dart';
import 'widgets/health_summary_card.dart';
import 'widgets/family_settings_card.dart';
import 'widgets/emergency_contacts_card.dart';
import 'dialogs/family_options_dialog.dart';
import 'dialogs/add_member_options_dialog.dart';
import 'services/family_service.dart';

class FamilyAccountScreen extends StatefulWidget {
  const FamilyAccountScreen({super.key});

  @override
  State<FamilyAccountScreen> createState() => _FamilyAccountScreenState();
}

class _FamilyAccountScreenState extends State<FamilyAccountScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _familyMembers = [];
  Map<String, dynamic>? _familyStats;
  final user = FirebaseAuth.instance.currentUser;
  late final FamilyService _familyService;

  @override
  void initState() {
    super.initState();
    _familyService = FamilyService(user!.uid);
    _loadFamilyData();
  }

  Future<void> _loadFamilyData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final data = await _familyService.loadFamilyData();
      setState(() {
        _familyMembers = data['members'];
        _familyStats = data['stats'];
      });
    } catch (e) {
      print('Error loading family data: $e');
      _showErrorSnackBar('ไม่สามารถโหลดข้อมูลครอบครัวได้');
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
          'บัญชีครอบครัว',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black),
            onPressed: () => _showAddMemberOptions(),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.black),
            onPressed: () => _showFamilyOptions(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : RefreshIndicator(
              onRefresh: _loadFamilyData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Family Overview Card
                    FamilyOverviewCard(
                      totalMembers: _familyMembers.length + 1,
                      familyStats: _familyStats,
                      familyMembers: _familyMembers,
                    ),
                    const SizedBox(height: 20),

                    // Quick Actions
                    QuickActionsRow(
                      onInvite: () => _showAddMemberOptions(),
                      onHealthCheck: () => _showHealthCheckDialog(),
                    ),
                    const SizedBox(height: 20),

                    // Family Members List
                    FamilyMembersList(
                      familyMembers: _familyMembers,
                      currentUser: user,
                      onAddMember: () => _showAddMemberOptions(),
                      onEditMember: _editMember,
                      onRemoveMember: _removeMember,
                      onViewHealth: _viewMemberHealth,
                    ),
                    const SizedBox(height: 20),

                    // Family Health Summary
                    if (_familyMembers.isNotEmpty) ...[
                      HealthSummaryCard(familyStats: _familyStats),
                      const SizedBox(height: 20),
                    ],

                    // Family Settings
                    FamilySettingsCard(
                      onQRCode: _showQRCodeDialog,
                      onPermissions: _showPermissionsDialog,
                      onNotifications: _showFamilyNotificationSettings,
                      onBackup: _showBackupOptions,
                    ),
                    const SizedBox(height: 20),

                    // Emergency Contacts
                    EmergencyContactsCard(
                      onAddContact: _showAddEmergencyContactDialog,
                      onCallContact: _callEmergencyContact,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // Dialog Methods
  void _showAddMemberOptions() {
    AddMemberOptionsDialog.show(
      context: context,
      onAddManually: _showAddMemberDialog,
      onScanQR: _showQRScannerDialog,
      onShareLink: _shareInviteLink,
    );
  }

  void _showFamilyOptions() {
    FamilyOptionsDialog.show(
      context: context,
      onRefresh: _refreshFamilyData,
      onExport: _exportFamilyData,
      onDisband: _showDisbandFamilyDialog,
    );
  }

  // Member Management
  void _editMember(Map<String, dynamic> member) {
    // Navigate to edit member screen or show dialog
    // Implementation will be in separate dialog file
  }

  void _removeMember(String memberId, String memberName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ลบสมาชิก'),
        content: Text('คุณต้องการลบ "$memberName" ออกจากครอบครัวหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _familyService.deleteFamilyMember(memberId);
              Navigator.pop(context);
              await _loadFamilyData();
              _showSuccessSnackBar('ลบสมาชิกสำเร็จ');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบสมาชิก'),
          ),
        ],
      ),
    );
  }

  void _viewMemberHealth(Map<String, dynamic> member) {
    // Show member health details
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ข้อมูลสุขภาพ - ${member['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHealthInfoRow(
              'สถานะสุขภาพ',
              member['healthStatus'] ?? 'ไม่ทราบ',
            ),
            _buildHealthInfoRow('BMI', member['bmi']?.toString() ?? 'ไม่ทราบ'),
            _buildHealthInfoRow('ภูมิแพ้', member['allergies'] ?? 'ไม่มี'),
            _buildHealthInfoRow('ยาที่ใช้', member['medications'] ?? 'ไม่มี'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to detailed health screen
            },
            child: const Text('ดูรายละเอียด'),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // Placeholder methods for dialogs that will be implemented in separate files
  void _showAddMemberDialog() {
    // Will be implemented in dialogs/add_member_dialog.dart
    _showSuccessSnackBar('เพิ่มสมาชิกสำเร็จ (จำลอง)');
  }

  void _showQRScannerDialog() {
    // Will be implemented in dialogs/qr_scanner_dialog.dart
    _showSuccessSnackBar('สแกน QR Code สำเร็จ (จำลอง)');
  }

  void _showQRCodeDialog() {
    // Will be implemented in dialogs/qr_code_dialog.dart
    _showSuccessSnackBar('แสดง QR Code (จำลอง)');
  }

  void _showPermissionsDialog() {
    // Will be implemented in dialogs/permissions_dialog.dart
    _showSuccessSnackBar('บันทึกสิทธิ์สำเร็จ (จำลอง)');
  }

  void _showFamilyNotificationSettings() {
    _showSuccessSnackBar('บันทึกการตั้งค่าการแจ้งเตือนสำเร็จ (จำลอง)');
  }

  void _showBackupOptions() {
    _showSuccessSnackBar('สำรองข้อมูลสำเร็จ (จำลอง)');
  }

  void _showAddEmergencyContactDialog() {
    _showSuccessSnackBar('เพิ่มผู้ติดต่อฉุกเฉินสำเร็จ (จำลอง)');
  }

  void _showHealthCheckDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ตรวจสอบสุขภาพครอบครัว'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHealthCheckItem(
              'สมาชิกที่ต้องตรวจสุขภาพ',
              '2 คน',
              Colors.orange,
            ),
            _buildHealthCheckItem(
              'สมาชิกที่พลาดการออกกำลังกาย',
              '1 คน',
              Colors.red,
            ),
            _buildHealthCheckItem(
              'สมาชิกที่ดูแลสุขภาพดี',
              '3 คน',
              Colors.green,
            ),
            const SizedBox(height: 16),
            const Text(
              'คุณต้องการส่งการแจ้งเตือนให้สมาชิกหรือไม่?',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccessSnackBar('ส่งการแจ้งเตือนสุขภาพให้สมาชิกแล้ว');
            },
            child: const Text('ส่งการแจ้งเตือน'),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthCheckItem(String title, String count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
          Text(
            count,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  void _showDisbandFamilyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยุบครอบครัว'),
        content: const Text(
          'การยุบครอบครัวจะลบสมาชิกทั้งหมดและข้อมูลที่เกี่ยวข้อง การดำเนินการนี้ไม่สามารถย้อนกลับได้',
          style: TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _familyService.disbandFamily(_familyMembers);
              Navigator.pop(context);
              Navigator.pop(context);
              _showSuccessSnackBar('ยุบครอบครัวสำเร็จ');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ยุบครอบครัว'),
          ),
        ],
      ),
    );
  }

  // Action Methods
  void _shareInviteLink() async {
    await _familyService.shareInviteLink();
    _showSuccessSnackBar('แชร์ลิงก์เชิญสำเร็จ');
  }

  void _callEmergencyContact(String phoneNumber) {
    _showSuccessSnackBar('กำลังโทรหา $phoneNumber');
  }

  void _refreshFamilyData() async {
    await _loadFamilyData();
    _showSuccessSnackBar('อัปเดตข้อมูลครอบครัวสำเร็จ');
  }

  void _exportFamilyData() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('กำลังส่งออกข้อมูล...'),
          ],
        ),
      ),
    );

    Future.delayed(const Duration(seconds: 3), () {
      Navigator.pop(context);
      _showSuccessSnackBar('ส่งออกข้อมูลครอบครัวสำเร็จ');
    });
  }

  // Utility Methods
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'ปิด',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'ปิด',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}
