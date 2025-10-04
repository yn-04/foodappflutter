import 'package:flutter/material.dart';

import 'package:my_app/rawmaterial/constants/categories.dart';
import 'package:my_app/rawmaterial/constants/units.dart';

class DuplicateItemData {
  const DuplicateItemData({
    required this.name,
    required this.quantity,
    required this.category,
    required this.unit,
    this.expiry,
  });

  final String name;
  final int quantity;
  final String category;
  final String unit;
  final DateTime? expiry;
}

Future<DuplicateItemData?> showDuplicateItemDialog(
  BuildContext context, {
  required String initialName,
  required int initialQuantity,
  required String initialCategory,
  required String initialUnit,
  DateTime? initialExpiry,
  String? imageUrl,
}) async {
  final nameCtrl = TextEditingController(text: initialName);
  final qtyCtrl = TextEditingController(text: initialQuantity.toString());

  final normalizedCategory = Categories.normalize(initialCategory);
  final categories = <String>[...Categories.list];
  if (normalizedCategory.isNotEmpty &&
      !categories.contains(normalizedCategory)) {
    categories.insert(0, normalizedCategory);
  }

  final normalizedUnit = Units.safe(initialUnit);
  final units = <String>[...Units.all];
  if (!units.contains(normalizedUnit)) {
    units.insert(0, normalizedUnit);
  }

  String selectedCategory = normalizedCategory;
  String selectedUnit = normalizedUnit;
  DateTime? expiry = initialExpiry;
  String? nameError;
  String? qtyError;

  final result = await showDialog<DuplicateItemData>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) {
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> pickDate() async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: dialogCtx,
              initialDate: expiry ?? now,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 5),
              helpText: 'เลือกวันหมดอายุ',
            );
            if (picked != null) {
              setState(() => expiry = picked);
            }
          }

          String formatDate(DateTime d) {
            final day = d.day.toString().padLeft(2, '0');
            final month = d.month.toString().padLeft(2, '0');
            final year = (d.year + 543).toString();
            return '$day/$month/${year.substring(year.length - 2)}';
          }

          void attemptSave() {
            final name = nameCtrl.text.trim();
            final qty = int.tryParse(qtyCtrl.text.trim());
            String? newNameError;
            String? newQtyError;

            if (name.isEmpty) {
              newNameError = 'กรุณากรอกชื่อวัตถุดิบ';
            }
            if (qty == null || qty <= 0) {
              newQtyError = 'กรุณากรอกจำนวนให้ถูกต้อง';
            }

            setState(() {
              nameError = newNameError;
              qtyError = newQtyError;
            });

            if (newNameError != null || newQtyError != null) {
              return;
            }

            Navigator.of(dialogCtx).pop(
              DuplicateItemData(
                name: name,
                quantity: qty!,
                category: selectedCategory,
                unit: selectedUnit,
                expiry: expiry,
              ),
            );
          }

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey[200],
                          backgroundImage:
                              imageUrl != null && imageUrl.isNotEmpty
                              ? NetworkImage(imageUrl)
                              : null,
                          child: (imageUrl == null || imageUrl.isEmpty)
                              ? const Icon(
                                  Icons.fastfood,
                                  color: Colors.black54,
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ทำซ้ำวัตถุดิบ',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'ตรวจสอบและแก้ไขข้อมูลก่อนบันทึก',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'ชื่อวัตถุดิบ',
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        errorText: nameError,
                      ),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'จำนวน',
                              filled: true,
                              fillColor: Colors.grey[50],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              errorText: qtyError,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 150,
                          child: DropdownButtonFormField<String>(
                            value: selectedUnit,
                            decoration: InputDecoration(
                              labelText: 'หน่วย',
                              filled: true,
                              fillColor: Colors.grey[50],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            items: units
                                .map(
                                  (unit) => DropdownMenuItem<String>(
                                    value: unit,
                                    child: Text(unit),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => selectedUnit = Units.safe(value));
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedCategory.isNotEmpty
                          ? selectedCategory
                          : null,
                      decoration: InputDecoration(
                        labelText: 'หมวดหมู่',
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: categories
                          .map(
                            (cat) => DropdownMenuItem<String>(
                              value: cat,
                              child: Text(cat),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(
                          () => selectedCategory = Categories.normalize(value),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey[50],
                      ),
                      child: ListTile(
                        onTap: pickDate,
                        leading: const Icon(Icons.event),
                        title: Text(
                          expiry == null
                              ? 'ไม่ระบุวันหมดอายุ'
                              : 'หมดอายุ: ${formatDate(expiry!)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: expiry == null
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => setState(() => expiry = null),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: const Text('ยกเลิก'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: attemptSave,
                            child: const Text('บันทึก'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );

  nameCtrl.dispose();
  qtyCtrl.dispose();

  return result;
}
