// lib/profile/family/join_family_scan_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/family_service.dart';

class JoinFamilyScanScreen extends StatefulWidget {
  const JoinFamilyScanScreen({super.key});

  @override
  State<JoinFamilyScanScreen> createState() => _JoinFamilyScanScreenState();
}

class _JoinFamilyScanScreenState extends State<JoinFamilyScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;
  bool _processing = false;
  String _status = 'เล็งกล้องไปที่ QR เพื่อสแกน';
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_handled || _processing) return;

    final String? code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((s) => s != null && s.isNotEmpty, orElse: () => null);

    if (code == null) return;

    _handled = true;
    setState(() {
      _processing = true;
      _status = 'กำลังเข้าร่วมครอบครัว...';
    });

    // หยุดกล้องชั่วคราวกันยิงซ้ำ
    try {
      await _controller.stop();
    } catch (_) {}

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw 'กรุณาเข้าสู่ระบบก่อน';
      await FamilyService(
        '_placeholder_',
      ).joinFamilyByQrPayload(code, userId: uid);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      // ให้ลองสแกนใหม่ได้
      if (mounted) {
        setState(() {
          _handled = false;
          _status = 'สแกนไม่สำเร็จ: $e';
        });
      }
      _showError('เข้าร่วมไม่สำเร็จ: $e');

      try {
        await _controller.start();
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สแกน QR เข้าร่วมครอบครัว'),
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.maybePop(context),
        ),
      ),
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            // กล้องสแกน
            Positioned.fill(
              child: MobileScanner(
                controller: _controller,
                onDetect: _handleDetection,
              ),
            ),

            // กรอบช่วยเล็ง (overlay)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withOpacity(0.08), // ← เปลี่ยน
                          Colors.white.withOpacity(0.02), // ← เปลี่ยน
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // แถบสถานะด้านล่าง
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _status,
                    key: ValueKey(_status),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),

            // ปุ่มไฟฉาย
            Positioned(
              right: 16,
              bottom: 72,
              child: FloatingActionButton.small(
                onPressed: () async {
                  try {
                    await _controller.toggleTorch();
                    setState(() => _torchOn = !_torchOn);
                  } catch (_) {
                    _showError('อุปกรณ์ไม่รองรับไฟฉาย');
                  }
                },
                backgroundColor: _torchOn
                    ? Colors.amberAccent.shade200
                    : Colors.black87,
                child: Icon(
                  _torchOn ? Icons.flashlight_off : Icons.flashlight_on,
                  color: _torchOn ? Colors.black : Colors.white,
                ),
              ),
            ),

            // ปุ่มยกเลิก (มุมซ้ายล่าง)
            Positioned(
              left: 16,
              bottom: 72,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.12), // ← เปลี่ยน
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.close),
                label: const Text('ยกเลิก'),
              ),
            ),

            if (_processing)
              Positioned.fill(
                child: Container(
                  color: Colors.black87.withOpacity(0.7), // ← เปลี่ยน
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 12),
                        Text(
                          'กำลังเข้าร่วมครอบครัว...',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showError(String m) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(m), backgroundColor: Colors.red));
  }
}
