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
  final String name;
  final bool optional;
  final String originalUnit;
  final String displayUnit;
  final double displayDefault;
  final double? canonicalPerOriginal;
  final double? canonicalPerDisplay;
  final String? canonicalUnitOriginal;
  final String? canonicalUnitDisplay;

  const _IngredientDialogEntry({
    required this.name,
    required this.optional,
    required this.originalUnit,
    required this.displayUnit,
    required this.displayDefault,
    required this.canonicalPerOriginal,
    required this.canonicalPerDisplay,
    required this.canonicalUnitOriginal,
    required this.canonicalUnitDisplay,
  });

  double displayToOriginal(double value) {
    final canonical = _safeCanonicalQuantity(value, displayUnit, name);
    if (canonical == null) return value;
    final origFactor = canonicalPerOriginal;
    if (origFactor == null || origFactor.abs() < 1e-9) return value;
    final unitMatch = canonicalUnitOriginal == null ||
        canonical.unit == canonicalUnitOriginal ||
        canonicalUnitDisplay == canonicalUnitOriginal;
    if (!unitMatch) return value;
    return canonical.amount / origFactor;
  }

  double originalToDisplay(double value) {
    final canonical = _safeCanonicalQuantity(value, originalUnit, name);
    if (canonical == null) return value;
    final displayFactor = canonicalPerDisplay;
    if (displayFactor == null || displayFactor.abs() < 1e-9) return value;
    final unitMatch = canonicalUnitDisplay == null ||
        canonical.unit == canonicalUnitDisplay ||
        canonicalUnitOriginal == canonicalUnitDisplay;
    if (!unitMatch) return value;
    return canonical.amount / displayFactor;
  }
}

Future<Map<String, double>?> showIngredientConfirmationDialog(
  BuildContext context, {
  required RecipeModel recipe,
  required int servings,
  Map<String, double>? initialRequiredAmounts,
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
    return initialRequiredAmounts == null
        ? <String, double>{}
        : Map<String, double>.from(initialRequiredAmounts);
  }

  final baseStatuses = analyzeIngredientStatus(
    recipe,
    const [],
    servings: servings,
  );

  final entryData = <_IngredientDialogEntry>[];
  final defaults = <String, double>{};
  final working = <String, double>{};

  for (var i = 0; i < entries.length; i++) {
    final ingredient = entries[i];
    final key = ingredient.name.trim();
    if (key.isEmpty) continue;

    final status = i < baseStatuses.length ? baseStatuses[i] : null;
    String displayUnit = status?.unit.trim() ?? ingredient.unit.trim();
    if (displayUnit.isEmpty) {
      displayUnit = ingredient.unit.trim();
    }

    double displayDefault = status?.requiredAmount ??
        (ingredient.numericAmount * multiplier);
    if (!displayDefault.isFinite || displayDefault < 0) {
      displayDefault = 0;
    }
    final normalizedDefault = _normalizeAmount(displayDefault);

    final originalCanonical = _safeCanonicalQuantity(
      1,
      ingredient.unit.trim(),
      key,
    );
    final displayCanonical = _safeCanonicalQuantity(
      1,
      displayUnit,
      key,
    );

    final entry = _IngredientDialogEntry(
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

    defaults[key] = normalizedDefault;

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

    working[key] = _normalizeAmount(initialDisplay);
  }

  if (entryData.isEmpty) {
    return initialRequiredAmounts == null
        ? <String, double>{}
        : Map<String, double>.from(initialRequiredAmounts);
  }

  final controllers = <String, TextEditingController>{};

  final dialogResult = await showDialog<Map<String, double>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          Map<String, double> normalizeOutput() {
            final result = <String, double>{};
            for (final entry in entryData) {
              final key = entry.name;
              final defaultValue = defaults[key] ?? entry.displayDefault;
              final displayValue = working[key] ?? defaultValue;
              final sanitizedDisplay =
                  displayValue.isFinite ? displayValue : defaultValue;
              double clampedDisplay =
                  sanitizedDisplay < 0 ? 0 : sanitizedDisplay;
              if (clampedDisplay > 99999.0) clampedDisplay = 99999.0;
              final originalAmount = entry.displayToOriginal(clampedDisplay);
              final normalizedOriginal = originalAmount.isFinite
                  ? _normalizeAmount(originalAmount < 0 ? 0 : originalAmount)
                  : _normalizeAmount(0);
              result[key] = normalizedOriginal;
            }
            return result;
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
                    ...entryData.map((entry) {
                      final key = entry.name;
                      final displayUnit = entry.displayUnit.trim();
                      final defaultValue = defaults[key] ?? entry.displayDefault;
                      final value = working[key] ?? defaultValue;
                      final optional = entry.optional;
                      const double step = 1.0;
                      final unitLabel = displayUnit.isEmpty ? '' : ' $displayUnit';
                      final controller = controllers.putIfAbsent(
                        key,
                        () => TextEditingController(),
                      );
                      final displayString = _formatAmount(
                        value,
                        unit: displayUnit,
                        ingredientName: entry.name,
                      );
                      if (controller.text != displayString) {
                        controller.value = controller.value.copyWith(
                          text: displayString,
                          selection: TextSelection.collapsed(
                            offset: displayString.length,
                          ),
                        );
                      }
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
                                  child: Text(
                                    entry.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                                if (optional)
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
                                    border: Border.all(color: Colors.grey[300]!),
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
                                          final normalized = _normalizeAmount(next);
                                          setState(() {
                                            working[key] = normalized;
                                          });
                                          final updated = _formatAmount(
                                            normalized,
                                            unit: displayUnit,
                                            ingredientName: entry.name,
                                          );
                                          if (controller.text != updated) {
                                            controller.value = controller.value.copyWith(
                                              text: updated,
                                              selection: TextSelection.collapsed(
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
                                            contentPadding: EdgeInsets.symmetric(vertical: 4),
                                          ),
                                          onTap: () {
                                            controller.selection = TextSelection(
                                              baseOffset: 0,
                                              extentOffset: controller.text.length,
                                            );
                                          },
                                          onChanged: (text) {
                                            final parsed = double.tryParse(text);
                                            final normalized = _normalizeAmount(parsed ?? 0);
                                            setState(() {
                                              working[key] = normalized;
                                            });
                                            final updated = _formatAmount(
                                              normalized,
                                              unit: displayUnit,
                                              ingredientName: entry.name,
                                            );
                                            if (controller.text != updated) {
                                              controller.value = controller.value.copyWith(
                                                text: updated,
                                                selection: TextSelection.collapsed(
                                                  offset: updated.length,
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
                                          final normalized = _normalizeAmount(next);
                                          setState(() {
                                            working[key] = normalized;
                                          });
                                          final updated = _formatAmount(
                                            normalized,
                                            unit: displayUnit,
                                            ingredientName: entry.name,
                                          );
                                          if (controller.text != updated) {
                                            controller.value = controller.value.copyWith(
                                              text: updated,
                                              selection: TextSelection.collapsed(
                                                offset: updated.length,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                if (unitLabel.trim().isNotEmpty) ...[
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
                            const SizedBox(height: 4),
                            Text(
                              'สูตรแนะนำ: ${_formatAmount(
                                    defaultValue,
                                    unit: displayUnit,
                                    ingredientName: entry.name,
                                  )}${unitLabel.trim().isEmpty ? '' : unitLabel.trim()}',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {
                                  final normalized = _normalizeAmount(defaultValue);
                                  setState(() {
                                    working[key] = normalized;
                                  });
                                  final updated = _formatAmount(
                                    normalized,
                                    unit: displayUnit,
                                    ingredientName: entry.name,
                                  );
                                  if (controller.text != updated) {
                                    controller.value = controller.value.copyWith(
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
                        ),
                      );
                    }),
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
}) async {
  final provider = context.read<EnhancedRecommendationProvider>();
  final purchaseItems = computePurchaseItems(
    recipe,
    provider.ingredients,
    servings: servings,
    manualRequiredAmounts: manualRequiredAmounts,
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
                  const Text('วัตถุดิบต่อไปนี้มีไม่พอกับจำนวนเสิร์ฟ (อิงจากหน้ารายละเอียดเมนูตามจำนวนคนที่เลือก) จะให้ระบบใช้เท่าที่มีและบันทึกสต็อกหรือไม่?'),
                  const SizedBox(height: 12),
                  if (displayItems.isNotEmpty)
                    ...displayItems.map(
                      (item) {
                        final unit = item.unit.trim();
                        final qtyValue = formatQuantityNumber(
                          item.quantity,
                          unit: item.unit,
                          ingredientName: item.name,
                        );
                        final qtyText = unit.isEmpty ? qtyValue : '$qtyValue $unit';
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
                      },
                    )
                  else
                    ...shortages.map((item) {
                      final missing = item.missingAmount;
                      final trimmedUnit = item.unit.trim();
                      final unitLabel = trimmedUnit.isEmpty ? '' : ' $trimmedUnit';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${item.name} • ขาด ${_formatAmount(
                                missing,
                                unit: trimmedUnit,
                                ingredientName: item.name,
                              )}$unitLabel',
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
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700]),
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
          const Text('ใช้วัตถุดิบที่มีอยู่แล้ว ระบบบันทึกวัตถุดิบที่ยังขาดไว้นี้:'),
          const SizedBox(height: 12),
          ...shortages
              .where((item) => item.missingAmount > 0)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '- ${item.name}: ต้องการ ${_formatAmount(
                          item.requiredAmount,
                          unit: item.unit,
                          ingredientName: item.name,
                        )}${item.unit.trim().isEmpty ? '' : ' ${item.unit.trim()}'} ขาด ${_formatAmount(
                          item.missingAmount,
                          unit: item.unit,
                          ingredientName: item.name,
                        )}',
                  ),
                ),
              )
              .toList(),
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
  const _QuantityButton({
    required this.icon,
    required this.onTap,
  });

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
}) =>
    formatQuantityNumber(
      value,
      unit: unit,
      ingredientName: ingredientName,
    );

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
