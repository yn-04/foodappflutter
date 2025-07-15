// screens/family/dialogs/qr_code_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class QRCodeDialog {
  static void show({required BuildContext context, required String familyId}) {
    showDialog(
      context: context,
      builder: (context) => _QRCodeDialogContent(familyId: familyId),
    );
  }
}

class _QRCodeDialogContent extends StatefulWidget {
  final String familyId;

  const _QRCodeDialogContent({required this.familyId});

  @override
  State<_QRCodeDialogContent> createState() => _QRCodeDialogContentState();
}

class _QRCodeDialogContentState extends State<_QRCodeDialogContent>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late String _inviteCode;
  late String _inviteLink;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _inviteCode = 'FAMILY_${widget.familyId.substring(0, 8).toUpperCase()}';
    _inviteLink = 'https://yourapp.com/join/$_inviteCode';
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
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.qr_code,
                      color: Colors.blue[700],
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'เชิญสมาชิกเข้าร่วม',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
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
                  Tab(text: 'QR Code'),
                  Tab(text: 'รหัสเชิญ'),
                ],
                labelColor: Colors.blue[700],
                unselectedLabelColor: Colors.grey[600],
                indicatorColor: Colors.blue[700],
              ),
            ),

            // Tab content
            SizedBox(
              height: 400,
              child: TabBarView(
                controller: _tabController,
                children: [_buildQRCodeTab(), _buildInviteCodeTab()],
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
                    child: OutlinedButton.icon(
                      onPressed: _copyToClipboard,
                      icon: const Icon(Icons.copy),
                      label: const Text('คัดลอก'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _shareInvite,
                      icon: const Icon(Icons.share),
                      label: const Text('แชร์'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                      ),
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

  Widget _buildQRCodeTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text(
            'ให้สมาชิกใหม่สแกน QR Code นี้',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // QR Code
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: QrImageView(
              data: _inviteLink,
              version: QrVersions.auto,
              size: 200.0,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
          ),

          const SizedBox(height: 20),

          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Column(
              children: [
                Icon(Icons.smartphone, color: Colors.green[600], size: 32),
                const SizedBox(height: 8),
                Text(
                  'วิธีใช้งาน',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.green[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '1. เปิดแอปในมือถือของสมาชิก\n'
                  '2. เลือก "เข้าร่วมครอบครัว"\n'
                  '3. สแกน QR Code นี้',
                  style: TextStyle(fontSize: 12, color: Colors.green[600]),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteCodeTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text(
            'แชร์รหัสเชิญหรือลิงก์นี้',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Invite Code
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              children: [
                Text(
                  'รหัสเชิญ',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _inviteCode,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _copyText(_inviteCode),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('คัดลอกรหัส'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Invite Link
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                Text(
                  'ลิงก์เชิญ',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _inviteLink,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _copyText(_inviteLink),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('คัดลอกลิงก์'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Expiry info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, color: Colors.orange[600], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'รหัสเชิญนี้ใช้ได้ถาวร แต่คุณสามารถเปลี่ยนใหม่ได้ตลอดเวลา',
                    style: TextStyle(fontSize: 12, color: Colors.orange[700]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard() {
    final currentTab = _tabController.index;
    final textToCopy = currentTab == 0 ? _inviteLink : _inviteCode;
    _copyText(textToCopy);
  }

  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('คัดลอก${text.contains('http') ? 'ลิงก์' : 'รหัส'}แล้ว'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareInvite() async {
    try {
      final message =
          '''
🏥 เชิญเข้าร่วมครอบครัวใน Health App

👨‍👩‍👧‍👦 ครอบครัวของเราต้องการให้คุณเข้าร่วม!

📱 วิธีเข้าร่วม:
1. ดาวน์โหลดแอป Health App
2. เลือก "เข้าร่วมครอบครัว"
3. ใช้รหัสเชิญ: $_inviteCode
หรือคลิกลิงก์: $_inviteLink

💚 มาดูแลสุขภาพไปด้วยกัน!
      ''';

      await Share.share(message, subject: 'เชิญเข้าร่วมครอบครัวใน Health App');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ไม่สามารถแชร์ได้: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
