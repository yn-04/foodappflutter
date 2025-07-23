// lib/profile/account_details/info_card.dart
import 'package:flutter/material.dart';

class ModernInfoCard extends StatelessWidget {
  final String title;
  final IconData? icon;
  final List<Widget> children;
  final Color? accentColor;

  const ModernInfoCard({
    super.key,
    required this.title,
    required this.children,
    this.icon,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Simple header without gradient
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.grey[700], size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          // Content without extra padding
          Column(children: children),
        ],
      ),
    );
  }
}

class ModernInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Widget? customValue;
  final IconData? icon;
  final VoidCallback? onTap;

  const ModernInfoRow({
    super.key,
    required this.label,
    this.value = '',
    this.customValue,
    this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.grey[600], size: 20),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.grey[700],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child:
                  customValue ??
                  Text(
                    value.isEmpty ? 'ไม่ระบุ' : value,
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: value.isEmpty ? Colors.grey[500] : Colors.black87,
                    ),
                    textAlign: TextAlign.right,
                  ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
            ],
          ],
        ),
      ),
    );
  }
}

class ModernEditableRow extends StatelessWidget {
  final String label;
  final String value;
  final TextEditingController controller;
  final bool isEditing;
  final TextInputType keyboardType;
  final int maxLines;
  final IconData? icon;
  final String? Function(String?)? validator;

  const ModernEditableRow({
    super.key,
    required this.label,
    required this.value,
    required this.controller,
    required this.isEditing,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.icon,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.grey[600], size: 20),
            const SizedBox(width: 12),
          ],
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: isEditing
                ? TextFormField(
                    controller: controller,
                    keyboardType: keyboardType,
                    maxLines: maxLines,
                    validator: validator,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Colors.black87),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: const BorderSide(color: Colors.red),
                      ),
                      hintText: keyboardType == TextInputType.phone
                          ? '08X-XXX-XXXX'
                          : null,
                      hintStyle: TextStyle(color: Colors.grey[400]),
                    ),
                  )
                : Text(
                    value.isEmpty
                        ? 'ไม่ระบุ'
                        : (keyboardType == TextInputType.phone
                              ? _formatPhoneNumber(value)
                              : value),
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      color: value.isEmpty ? Colors.grey[500] : Colors.black87,
                    ),
                    textAlign: TextAlign.right,
                  ),
          ),
        ],
      ),
    );
  }

  String _formatPhoneNumber(String phone) {
    if (phone.isEmpty) return 'ไม่ระบุ';

    String cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');

    if (cleaned.length == 10 && cleaned.startsWith('0')) {
      return '${cleaned.substring(0, 3)}-${cleaned.substring(3, 6)}-${cleaned.substring(6)}';
    } else if (cleaned.length == 9 && !cleaned.startsWith('0')) {
      return '0${cleaned.substring(0, 2)}-${cleaned.substring(2, 5)}-${cleaned.substring(5)}';
    }

    return phone;
  }
}
