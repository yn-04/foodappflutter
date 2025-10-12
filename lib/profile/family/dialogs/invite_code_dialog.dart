// lib/profile/family/dialogs/invite_code_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dialog ให้ผู้ใช้กรอกรหัสเชิญแล้วคืนค่าเป็น String (cleaned & UPPERCASE)
/// การ join ให้ทำในหน้าที่เรียกใช้ (เช่น FamilyService.joinFamilyByCode)
class InviteCodeDialog {
  static Future<String?> show({
    required BuildContext context,
    String? initialCode,
    String title = 'เข้าร่วมด้วยโค้ด',
    String label = 'โค้ดเชิญ',
    String hint = 'พิมพ์โค้ดที่ได้รับ',
    String confirmText = 'เข้าร่วม',
    String cancelText = 'ยกเลิก',
    int minLength = 6,
    int maxLength = 32,
    bool barrierDismissible = false,
  }) {
    return showDialog<String?>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => _InviteCodeDialogBody(
        title: title,
        label: label,
        hint: hint,
        confirmText: confirmText,
        cancelText: cancelText,
        minLength: minLength,
        maxLength: maxLength,
        initialCode: initialCode,
      ),
    );
  }
}

class _InviteCodeDialogBody extends StatefulWidget {
  const _InviteCodeDialogBody({
    required this.title,
    required this.label,
    required this.hint,
    required this.confirmText,
    required this.cancelText,
    required this.minLength,
    required this.maxLength,
    this.initialCode,
  });

  final String title;
  final String label;
  final String hint;
  final String confirmText;
  final String cancelText;
  final int minLength;
  final int maxLength;
  final String? initialCode;

  @override
  State<_InviteCodeDialogBody> createState() => _InviteCodeDialogBodyState();
}

class _InviteCodeDialogBodyState extends State<_InviteCodeDialogBody> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final init = _clean(widget.initialCode ?? '');
    _codeCtrl.text = init;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  // ตัดช่องว่าง/ขีด และแปลงเป็นตัวใหญ่
  String _clean(String v) {
    final t = v.replaceAll(RegExp(r'[\\s\\-]'), '');
    return t.toUpperCase();
  }

  String? _validate(String? v) {
    final t = _clean(v ?? '');
    if (t.isEmpty) return 'กรุณากรอกโค้ดเชิญ';
    if (t.length < widget.minLength) {
      return 'โค้ดต้องมีอย่างน้อย ${widget.minLength} ตัวอักษร';
    }
    if (t.length > widget.maxLength) {
      return 'โค้ดยาวเกินกำหนด (${widget.maxLength})';
    }
    return null;
  }

  Future<void> _onSubmit() async {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final code = _clean(_codeCtrl.text);
      if (!mounted) return;
      Navigator.of(context).pop(code);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 24.0,
        vertical: 16.0,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440.0),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
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

                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8.0),

                TextFormField(
                  controller: _codeCtrl,
                  textInputAction: TextInputAction.done,
                  autofocus: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  inputFormatters: const [
                    _CodeSanitizerFormatter(), // ลบ space/dash ระหว่างพิมพ์
                    UpperCaseTextFormatter(), // พิมพ์เป็นตัวใหญ่
                  ],
                  maxLength: widget.maxLength,
                  decoration: InputDecoration(
                    hintText: widget.hint,
                    counterText: '', // ไม่แสดงตัวนับ
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'วาง',
                          icon: const Icon(Icons.content_paste_go),
                          onPressed: () async {
                            final data = await Clipboard.getData('text/plain');
                            if (data?.text == null) return;
                            final t = _clean(data!.text!);
                            _codeCtrl.text = t;
                          },
                        ),
                        IconButton(
                          tooltip: 'ล้าง',
                          icon: const Icon(Icons.clear),
                          onPressed: () => _codeCtrl.clear(),
                        ),
                      ],
                    ),
                  ),
                  validator: _validate,
                  onFieldSubmitted: (_) => _onSubmit(),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 8.0),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],

                const SizedBox(height: 12.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text(widget.cancelText),
                    ),
                    const SizedBox(width: 8.0),
                    FilledButton.icon(
                      icon: _submitting
                          ? const SizedBox(
                              width: 16.0,
                              height: 16.0,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                              ),
                            )
                          : const Icon(Icons.login),
                      onPressed: _submitting ? null : _onSubmit,
                      label: Text(widget.confirmText),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ลบช่องว่างและขีดออกระหว่างพิมพ์
class _CodeSanitizerFormatter extends TextInputFormatter {
  const _CodeSanitizerFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = newValue.text.replaceAll(RegExp(r'[\\s\\-]'), '');
    return newValue.copyWith(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
      composing: TextRange.empty,
    );
  }
}

/// Formatter: บังคับเป็นตัวใหญ่
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    return newValue.copyWith(
      text: upper,
      selection: TextSelection.collapsed(offset: upper.length),
      composing: TextRange.empty,
    );
  }
}
