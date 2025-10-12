// lib/profile/family/dialogs/qr_code_dialog.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Dialog แสดง QR สำหรับเชิญเข้าครอบครัว (แนวทาง A: ชื่อเรียลไทม์อ่านจาก users/{uid})
///
/// การใช้งานแบบเดิม (Backward-compatible):
/// ```dart
/// await QRCodeDialog.show(
///   context: context,
///   payload: yourEncodedString,
///   inviteCode: 'ABC123',
/// );
/// ```
///
/// การใช้งานแบบ enriched อัตโนมัติ:
/// ```dart
/// await QRCodeDialog.show(
///   context: context,
///   payload: '',                 // ถ้าไม่อยากสร้างเอง
///   familyId: fid,               // ใส่ familyId
///   enrichWithInviter: true,     // (ค่าเริ่มต้น true) จะดึง inviterUid/displayName ให้อัตโนมัติ
///   inviteCode: 'ABC123',
/// );
/// ```
class QRCodeDialog extends StatelessWidget {
  const QRCodeDialog._({
    super.key,
    required this.title,
    required this.payload,
    this.inviteCode,
    this.subtitle,
    required this.qrSize,
  });

  /// เปิด Dialog
  static Future<void> show({
    required BuildContext context,
    required String payload,
    String? inviteCode,
    String title = 'สแกนเพื่อเข้าร่วมครอบครัว',
    String? subtitle,
    double qrSize = 220,
    // เพิ่มความสามารถใหม่ (ไม่บังคับใช้): ให้ตัว Dialog ช่วย "เติมข้อมูลผู้เชิญ" ลง payload ให้เอง
    String? familyId,
    bool enrichWithInviter = true,
  }) async {
    // ถ้าขอให้ enrich และมี familyId ให้สร้าง payload ใหม่แบบ JSON ใส่ inviter
    if (enrichWithInviter && (familyId != null && familyId.isNotEmpty)) {
      final enriched = await _buildEnrichedPayload(familyId);
      if (enriched != null) {
        payload = enriched;
      }
    }

    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => QRCodeDialog._(
        title: title,
        payload: payload,
        inviteCode: inviteCode,
        subtitle: subtitle,
        qrSize: qrSize,
      ),
    );
  }

  final String title;
  final String payload;
  final String? inviteCode;
  final String? subtitle;
  final double qrSize;

  static Future<String?> _buildEnrichedPayload(String familyId) async {
    try {
      final auth = FirebaseAuth.instance;
      final uid = auth.currentUser?.uid;
      if (uid == null) return null;

      // อ่าน displayName สด ๆ จาก users/{uid}
      final uSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final inviterDisplayName =
          (uSnap.data() ?? const {})['displayName'] as String? ?? '';

      // โครง payload เป็น JSON string (อ่านง่ายและขยายในอนาคต)
      final data = <String, dynamic>{
        'familyId': familyId,
        'inviterUid': uid,
        'inviterDisplayName': inviterDisplayName,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'v': 2, // เวอร์ชัน schema
      };
      return jsonEncode(data);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = (inviteCode ?? '').trim();
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 24.0,
        vertical: 16.0,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              subtitle!,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'ปิด',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12.0),

              // QR Box
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: QrImageView(
                  data: payload,
                  version: QrVersions.auto,
                  size: qrSize,
                  gapless: true,
                ),
              ),
              const SizedBox(height: 12.0),

              // Invite code (ถ้ามี)
              if (code.isNotEmpty) ...[
                SelectableText(
                  code,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                    letterSpacing: 1.0,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('คัดลอก'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('คัดลอกโค้ดแล้ว')),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 8.0),
                    TextButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text('แชร์โค้ด'),
                      onPressed: () async {
                        await Share.share(code);
                      },
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12.0),
              // Actions (Save / Share QR)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('บันทึกภาพ QR'),
                    onPressed: () async {
                      try {
                        final file = await _saveQrToFile(
                          payload,
                          size: (qrSize + 24.0),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('บันทึกแล้ว: ${file.path}')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
                          );
                        }
                      }
                    },
                  ),
                  const SizedBox(width: 12.0),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.ios_share),
                    label: const Text('แชร์รูป QR'),
                    onPressed: () async {
                      try {
                        final file = await _saveQrToFile(
                          payload,
                          size: (qrSize + 24.0),
                        );
                        await Share.shareXFiles([XFile(file.path)]);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('แชร์ไม่สำเร็จ: $e')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// เรนเดอร์ QR เป็น PNG แล้วบันทึกลง temp directory
  static Future<File> _saveQrToFile(String data, {num size = 256}) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
    );

    final uiImage = await painter.toImage(size.toDouble());
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('สร้างภาพ QR ไม่สำเร็จ');
    }

    final bytes = Uint8List.view(byteData.buffer);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/family_invite_qr_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
