//lib/foodreccom/widgets/recipe_detail/dialogs.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/recipe/recipe_model.dart';
import '../../services/cooking_service.dart';
import '../../providers/enhanced_recommendation_provider.dart';
import '../../utils/purchase_item_utils.dart';

class _IngredientDialogEntry {
  final String id;
  final String name;
  final bool optional;
  final String originalUnit;
  final String displayUnit;
  final double displayDefault;
  final double? canonicalPerOriginal;
  final double? canonicalPerDisplay;
  final String? canonicalUnitOriginal;
  final String? canonicalUnitDisplay;
  final bool isCustom;

  const _IngredientDialogEntry({
    required this.id,
    required this.name,
    required this.optional,
    required this.originalUnit,
    required this.displayUnit,
    required this.displayDefault,
    required this.canonicalPerOriginal,
    required this.canonicalPerDisplay,
    required this.canonicalUnitOriginal,
    required this.canonicalUnitDisplay,
    this.isCustom = false,
  });

  double displayToOriginal(double value) {
    if (isCustom) return value;
    final canonical = _safeCanonicalQuantity(value, displayUnit, name);
    if (canonical == null) return value;
    final origFactor = canonicalPerOriginal;
    if (origFactor == null || origFactor.abs() < 1e-9) return value;
    final unitMatch =
        canonicalUnitOriginal == null ||
        canonical.unit == canonicalUnitOriginal ||
        canonicalUnitDisplay == canonicalUnitOriginal;
    if (!unitMatch) return value;
    return canonical.amount / origFactor;
  }

  double originalToDisplay(double value) {
    if (isCustom) return value;
    final canonical = _safeCanonicalQuantity(value, originalUnit, name);
    if (canonical == null) return value;
    final displayFactor = canonicalPerDisplay;
    if (displayFactor == null || displayFactor.abs() < 1e-9) return value;
    final unitMatch =
        canonicalUnitDisplay == null ||
        canonical.unit == canonicalUnitDisplay ||
        canonicalUnitOriginal == canonicalUnitDisplay;
    if (!unitMatch) return value;
    return canonical.amount / displayFactor;
  }
}

Future<ManualIngredientSelection?> showIngredientConfirmationDialog(
  BuildContext context, {
  required RecipeModel recipe,
  required int servings,
  Map<String, double>? initialRequiredAmounts,
  List<ManualCustomIngredient>? initialCustomIngredients,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  final displayName = (user?.displayName?.trim().isNotEmpty ?? false)
      ? user!.displayName!.trim()
      : 'ผู้ใช้';
  final baseServings = recipe.servings <= 0 ? 1 : recipe.servings;
  final multiplier = servings / (baseServings == 0 ? 1 : baseServings);

  final entries = recipe.ingredients
      .where((ingredient) => ingredient.name.trim().isNotEmpty)
      .toList(growable: false);

  if (entries.isEmpty) {
    final overrides = initialRequiredAmounts == null
        ? <String, double>{}
        : Map<String, double>.from(initialRequiredAmounts);
    final additions = (initialCustomIngredients ?? const [])
        .map((item) => item.sanitize())
        .where((item) => item.isValid)
        .toList(growable: false);
    return ManualIngredientSelection(
      overrides: overrides,
      additions: additions,
    );
  }

  final baseStatuses = analyzeIngredientStatus(
    recipe,
    const [],
    servings: servings,
  );

  final entryData = <_IngredientDialogEntry>[];
  final defaults = <String, double>{};
  final working = <String, double>{};
  final removedEntries = <String>{};
  final customNames = <String, String>{};
  final customUnits = <String, String>{};
  int nextCustomIndex = 0;

  for (var i = 0; i < entries.length; i++) {
    final ingredient = entries[i];
    final key = ingredient.name.trim();
    if (key.isEmpty) continue;

    final status = i < baseStatuses.length ? baseStatuses[i] : null;
    String displayUnit = status?.unit.trim() ?? ingredient.unit.trim();
    if (displayUnit.isEmpty) {
      displayUnit = ingredient.unit.trim();
    }

    double displayDefault =
        status?.requiredAmount ?? (ingredient.numericAmount * multiplier);
    if (!displayDefault.isFinite || displayDefault < 0) {
      displayDefault = 0;
    }
    final normalizedDefault = _normalizeAmount(displayDefault);

    final originalCanonical = _safeCanonicalQuantity(
      1,
      ingredient.unit.trim(),
      key,
    );
    final displayCanonical = _safeCanonicalQuantity(1, displayUnit, key);

    final entry = _IngredientDialogEntry(
      id: 'recipe-$i',
      name: key,
      optional: ingredient.isOptional,
      originalUnit: ingredient.unit.trim(),
      displayUnit: displayUnit,
      displayDefault: normalizedDefault,
      canonicalPerOriginal: originalCanonical?.amount,
      canonicalPerDisplay: displayCanonical?.amount,
      canonicalUnitOriginal: originalCanonical?.unit ?? status?.canonicalUnit,
      canonicalUnitDisplay: displayCanonical?.unit,
    );
    entryData.add(entry);

    defaults[entry.id] = normalizedDefault;

    final initialOriginal = initialRequiredAmounts?[key];
    double initialDisplay;
    if (initialOriginal != null) {
      initialDisplay = entry.originalToDisplay(initialOriginal);
    } else {
      initialDisplay = normalizedDefault;
    }

    if (!initialDisplay.isFinite) {
      initialDisplay = normalizedDefault;
    }
    if (initialDisplay < 0) initialDisplay = 0;

    working[entry.id] = _normalizeAmount(initialDisplay);
  }

  if (initialCustomIngredients != null && initialCustomIngredients.isNotEmpty) {
    for (final custom in initialCustomIngredients) {
      final sanitized = custom.sanitize();
      if (!sanitized.isValid) continue;
      final id = 'custom-init-${nextCustomIndex++}';
      final normalizedDefault = _normalizeAmount(sanitized.amount);
      final entry = _IngredientDialogEntry(
        id: id,
        name: sanitized.name,
        optional: false,
        originalUnit: '',
        displayUnit: sanitized.unit,
        displayDefault: normalizedDefault,
        canonicalPerOriginal: null,
        canonicalPerDisplay: null,
        canonicalUnitOriginal: null,
        canonicalUnitDisplay: null,
        isCustom: true,
      );
      entryData.add(entry);
      defaults[id] = normalizedDefault;
      working[id] = normalizedDefault;
      customNames[id] = sanitized.name;
      customUnits[id] = sanitized.unit;
    }
  }

  if (entryData.isEmpty) {
    final overrides = initialRequiredAmounts == null
        ? <String, double>{}
        : Map<String, double>.from(initialRequiredAmounts);
    return ManualIngredientSelection(overrides: overrides);
  }

  final amountControllers = <String, TextEditingController>{};
  final nameControllers = <String, TextEditingController>{};
  final unitControllers = <String, TextEditingController>{};

  final dialogResult = await showDialog<ManualIngredientSelection>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          ManualIngredientSelection normalizeOutput() {
            final overrides = <String, double>{};
            final additions = <ManualCustomIngredient>[];
            for (final entry in entryData) {
              final id = entry.id;
              final defaultValue = defaults[id] ?? entry.displayDefault;
              final bool removed = removedEntries.contains(id);
              final double displayValue = removed
                  ? 0.0
                  : (working[id] ?? defaultValue);
              final double sanitizedDisplay = displayValue.isFinite
                  ? displayValue
                  : defaultValue;
              double clampedDisplay = sanitizedDisplay < 0
                  ? 0.0
                  : sanitizedDisplay;
              if (clampedDisplay > 99999.0) clampedDisplay = 99999.0;
              if (entry.isCustom) {
                final customName = customNames[id]?.trim() ?? '';
                if (customName.isEmpty || removed) {
                  continue;
                }
                final customUnit = customUnits[id]?.trim() ?? '';
                if (clampedDisplay <= 0) continue;
                additions.add(
                  ManualCustomIngredient(
                    name: customName,
                    amount: _normalizeAmount(clampedDisplay),
                    unit: customUnit,
                  ),
                );
                continue;
              }
              final originalAmount = entry.displayToOriginal(clampedDisplay);
              final normalizedOriginal = originalAmount.isFinite
                  ? _normalizeAmount(originalAmount < 0 ? 0 : originalAmount)
                  : _normalizeAmount(0);
              overrides[entry.name] = normalizedOriginal;
            }
            return ManualIngredientSelection(
              overrides: overrides,
              additions: additions,
            );
          }

          return AlertDialog(
            title: const Text('ยืนยันปริมาณวัตถุดิบ'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'คุณ $displayName ยืนยันการใช้ปริมาณเหล่านี้หรือปรับก่อนเริ่มทำเมนู',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'ระบบจะคำนวณสต็อกและรายการซื้อของตามปริมาณที่ระบุไว้',
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    ...entryData.where((entry) => !removedEntries.contains(entry.id)).map((
                      entry,
                    ) {
                      final id = entry.id;
                      final isCustom = entry.isCustom;
                      final defaultValue = defaults[id] ?? entry.displayDefault;
                      final value = working[id] ?? defaultValue;
                      final optional = entry.optional;
                      const double step = 1.0;
                      final displayUnit = isCustom
                          ? (customUnits[id]?.trim() ?? '')
                          : entry.displayUnit.trim();
                      final controller = amountControllers.putIfAbsent(
                        id,
                        () => TextEditingController(),
                      );
                      final currentName = isCustom
                          ? (customNames[id] ?? '')
                          : entry.name;
                      final labelNameForFormat = currentName.isEmpty
                          ? entry.name
                          : currentName;
                      final displayString = _formatAmount(
                        value,
                        unit: displayUnit,
                        ingredientName: labelNameForFormat,
                      );
                      if (controller.text != displayString) {
                        controller.value = controller.value.copyWith(
                          text: displayString,
                          selection: TextSelection.collapsed(
                            offset: displayString.length,
                          ),
                        );
                      }
                      TextEditingController? nameController;
                      TextEditingController? unitController;
                      if (isCustom) {
                        final desiredName = customNames[id] ?? '';
                        nameController = nameControllers.putIfAbsent(
                          id,
                          () => TextEditingController(text: desiredName),
                        );
                        if (nameController.text != desiredName) {
                          nameController.value = nameController.value.copyWith(
                            text: desiredName,
                            selection: TextSelection.collapsed(
                              offset: desiredName.length,
                            ),
                          );
                        }
                        final desiredUnit = customUnits[id] ?? '';
                        unitController = unitControllers.putIfAbsent(
                          id,
                          () => TextEditingController(text: desiredUnit),
                        );
                        if (unitController.text != desiredUnit) {
                          unitController.value = unitController.value.copyWith(
                            text: desiredUnit,
                            selection: TextSelection.collapsed(
                              offset: desiredUnit.length,
                            ),
                          );
                        }
                      }
                      final unitLabel = displayUnit.isEmpty
                          ? ''
                          : ' $displayUnit';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: isCustom
                                      ? TextField(
                                          controller: nameController,
                                          decoration: const InputDecoration(
                                            hintText: 'ชื่อวัตถุดิบ',
                                            border: InputBorder.none,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                          onChanged: (text) {
                                            setState(() {
                                              customNames[id] = text;
                                            });
                                          },
                                        )
                                      : Text(
                                          entry.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                ),
                                if (optional && !isCustom)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[50],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'ตัวเลือก',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'ลบวัตถุดิบ',
                                  onPressed: () {
                                    setState(() {
                                      if (isCustom) {
                                        entryData.removeWhere(
                                          (element) => element.id == id,
                                        );
                                        defaults.remove(id);
                                        working.remove(id);
                                        final amountController =
                                            amountControllers.remove(id);
                                        amountController?.dispose();
                                        final nameController = nameControllers
                                            .remove(id);
                                        nameController?.dispose();
                                        final unitController = unitControllers
                                            .remove(id);
                                        unitController?.dispose();
                                        customNames.remove(id);
                                        customUnits.remove(id);
                                      } else {
                                        removedEntries.add(id);
                                        working[id] = 0;
                                        final amountController =
                                            amountControllers[id];
                                        if (amountController != null) {
                                          amountController.value =
                                              amountController.value.copyWith(
                                                text: '0',
                                                selection:
                                                    const TextSelection.collapsed(
                                                      offset: 1,
                                                    ),
                                              );
                                        }
                                      }
                                    });
                                  },
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: Colors.red[400],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _QuantityButton(
                                        icon: Icons.remove,
                                        onTap: () {
                                          double next = value - step;
                                          if (next < 0) next = 0;
                                          final normalized = _normalizeAmount(
                                            next,
                                          );
                                          setState(() {
                                            working[id] = normalized;
                                          });
                                          final updated = _formatAmount(
                                            normalized,
                                            unit: displayUnit,
                                            ingredientName: labelNameForFormat,
                                          );
                                          if (controller.text != updated) {
                                            controller.value = controller.value
                                                .copyWith(
                                                  text: updated,
                                                  selection:
                                                      TextSelection.collapsed(
                                                        offset: updated.length,
                                                      ),
                                                );
                                          }
                                        },
                                      ),
                                      SizedBox(
                                        width: 70,
                                        child: TextField(
                                          controller: controller,
                                          textAlign: TextAlign.center,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter.allow(
                                              RegExp(r'^\d*\.?\d{0,2}$'),
                                            ),
                                          ],
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            border: InputBorder.none,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                  vertical: 4,
                                                ),
                                          ),
                                          onTap: () {
                                            controller.selection =
                                                TextSelection(
                                                  baseOffset: 0,
                                                  extentOffset:
                                                      controller.text.length,
                                                );
                                          },
                                          onChanged: (text) {
                                            final parsed = double.tryParse(
                                              text,
                                            );
                                            final normalized = _normalizeAmount(
                                              parsed ?? 0,
                                            );
                                            setState(() {
                                              working[id] = normalized;
                                            });
                                            final updated = _formatAmount(
                                              normalized,
                                              unit: displayUnit,
                                              ingredientName:
                                                  labelNameForFormat,
                                            );
                                            if (controller.text != updated) {
                                              controller.value = controller
                                                  .value
                                                  .copyWith(
                                                    text: updated,
                                                    selection:
                                                        TextSelection.collapsed(
                                                          offset:
                                                              updated.length,
                                                        ),
                                                  );
                                            }
                                          },
                                        ),
                                      ),
                                      _QuantityButton(
                                        icon: Icons.add,
                                        onTap: () {
                                          double next = value + step;
                                          if (next > 99999) next = 99999;
                                          final normalized = _normalizeAmount(
                                            next,
                                          );
                                          setState(() {
                                            working[id] = normalized;
                                          });
                                          final updated = _formatAmount(
                                            normalized,
                                            unit: displayUnit,
                                            ingredientName: labelNameForFormat,
                                          );
                                          if (controller.text != updated) {
                                            controller.value = controller.value
                                                .copyWith(
                                                  text: updated,
                                                  selection:
                                                      TextSelection.collapsed(
                                                        offset: updated.length,
                                                      ),
                                                );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                if (isCustom) ...[
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 80,
                                    child: TextField(
                                      controller: unitController,
                                      textAlign: TextAlign.center,
                                      decoration: const InputDecoration(
                                        hintText: 'หน่วย',
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (text) {
                                        setState(() {
                                          customUnits[id] = text;
                                        });
                                      },
                                    ),
                                  ),
                                ] else if (unitLabel.trim().isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    unitLabel.trim(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (!isCustom) ...[
                              const SizedBox(height: 4),
                              Text(
                                'สูตรแนะนำ: ${_formatAmount(defaultValue, unit: displayUnit, ingredientName: entry.name)}${unitLabel.trim().isEmpty ? '' : unitLabel.trim()}',
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    final normalized = _normalizeAmount(
                                      defaultValue,
                                    );
                                    setState(() {
                                      working[id] = normalized;
                                    });
                                    final updated = _formatAmount(
                                      normalized,
                                      unit: displayUnit,
                                      ingredientName: entry.name,
                                    );
                                    if (controller.text != updated) {
                                      controller.value = controller.value
                                          .copyWith(
                                            text: updated,
                                            selection: TextSelection.collapsed(
                                              offset: updated.length,
                                            ),
                                          );
                                    }
                                  },
                                  child: const Text('รีเซ็ตตามสูตร'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          final id = 'custom-${nextCustomIndex++}';
                          final entry = _IngredientDialogEntry(
                            id: id,
                            name: 'วัตถุดิบใหม่',
                            optional: false,
                            originalUnit: '',
                            displayUnit: '',
                            displayDefault: 0,
                            canonicalPerOriginal: null,
                            canonicalPerDisplay: null,
                            canonicalUnitOriginal: null,
                            canonicalUnitDisplay: null,
                            isCustom: true,
                          );
                          entryData.add(entry);
                          defaults[id] = 0;
                          working[id] = 0;
                          customNames[id] = '';
                          customUnits[id] = '';
                        });
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('เพิ่มวัตถุดิบ'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, normalizeOutput()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                ),
                child: const Text('ยืนยันปริมาณ'),
              ),
            ],
          );
        },
      );
    },
  );

  return dialogResult;
}

void showSuccessDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('สำเร็จ!'),
        ],
      ),
      content: const Text('เริ่มทำอาหารเรียบร้อยแล้ว ✅'),
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green[600]),
          child: const Text('เสร็จสิ้น'),
        ),
      ],
    ),
  );
}

void showErrorDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.error, color: Colors.red),
          SizedBox(width: 8),
          Text('เกิดข้อผิดพลาด'),
        ],
      ),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ตกลง'),
        ),
      ],
    ),
  );
}

Future<bool> showShortageDialog(
  BuildContext context, {
  required RecipeModel recipe,
  required int servings,
  required List<IngredientShortage> shortages,
  Map<String, double>? manualRequiredAmounts,
  List<ManualCustomIngredient>? manualCustomIngredients,
}) async {
  final provider = context.read<EnhancedRecommendationProvider>();
  final purchaseItems = computePurchaseItems(
    recipe,
    provider.ingredients,
    servings: servings,
    manualRequiredAmounts: manualRequiredAmounts,
    manualCustomIngredients: manualCustomIngredients,
  );

  final displayItems = purchaseItems
      .where((item) => item.missingAmount > 0.01)
      .toList(growable: false);

  return await showDialog<bool>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('วัตถุดิบไม่เพียงพอ'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'วัตถุดิบต่อไปนี้มีไม่พอกับจำนวนเสิร์ฟ (อิงจากหน้ารายละเอียดเมนูตามจำนวนคนที่เลือก) จะให้ระบบใช้เท่าที่มีและบันทึกสต็อกหรือไม่?',
                  ),
                  const SizedBox(height: 12),
                  if (displayItems.isNotEmpty)
                    ...displayItems.map((item) {
                      final unit = item.unit.trim();
                      final qtyValue = formatQuantityNumber(
                        item.quantity,
                        unit: item.unit,
                        ingredientName: item.name,
                      );
                      final qtyText = unit.isEmpty
                          ? qtyValue
                          : '$qtyValue $unit';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.shopping_cart_outlined,
                              size: 16,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.name,
                                style: const TextStyle(color: Colors.black87),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              qtyText,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      );
                    })
                  else
                    ...shortages.map((item) {
                      final missing = item.missingAmount;
                      final trimmedUnit = item.unit.trim();
                      final unitLabel = trimmedUnit.isEmpty
                          ? ''
                          : ' $trimmedUnit';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${item.name} • ขาด ${_formatAmount(missing, unit: trimmedUnit, ingredientName: item.name)}$unitLabel',
                        ),
                      );
                    }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange[700],
                ),
                child: const Text('ใช้เท่าที่มี'),
              ),
            ],
          );
        },
      ) ??
      false;
}

Future<void> showPartialSuccessDialog(
  BuildContext context,
  List<IngredientShortage> shortages,
) async {
  return showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.check_circle, color: Colors.green),
          SizedBox(width: 8),
          Text('เริ่มทำแล้ว (วัตถุดิบบางส่วน)'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ใช้วัตถุดิบที่มีอยู่แล้ว ระบบบันทึกวัตถุดิบที่ยังขาดไว้นี้:',
          ),
          const SizedBox(height: 12),
          ...shortages
              .where((item) => item.missingAmount > 0)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '- ${item.name}: ต้องการ ${_formatAmount(item.requiredAmount, unit: item.unit, ingredientName: item.name)}${item.unit.trim().isEmpty ? '' : ' ${item.unit.trim()}'} ขาด ${_formatAmount(item.missingAmount, unit: item.unit, ingredientName: item.name)}',
                  ),
                ),
              ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green[600]),
          child: const Text('ตกลง'),
        ),
      ],
    ),
  );
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20, color: Colors.grey[800]),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      splashRadius: 18,
    );
  }
}

String _formatAmount(
  double value, {
  String unit = '',
  String ingredientName = '',
}) => formatQuantityNumber(value, unit: unit, ingredientName: ingredientName);

double _normalizeAmount(double value) {
  if (!value.isFinite || value <= 0) return 0;
  final normalized = double.parse(value.toStringAsFixed(2));
  return normalized > 99999 ? 99999 : normalized;
}

CanonicalQuantity? _safeCanonicalQuantity(
  double amount,
  String unit,
  String ingredientName,
) {
  if (!amount.isFinite) return null;
  try {
    final result = toCanonicalQuantity(amount, unit, ingredientName);
    if (!result.amount.isFinite) return null;
    return result;
  } catch (_) {
    return null;
  }
}
