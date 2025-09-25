// lib/rawmaterial/widgets/quick_use_sheet.dart
import 'package:flutter/material.dart';

class QuickUseSheet extends StatefulWidget {
  final String itemName;
  final String unit;
  final int currentQty;
  final Future<void> Function(int useQty, String note) onSave;

  const QuickUseSheet({
    super.key,
    required this.itemName,
    required this.unit,
    required this.currentQty,
    required this.onSave,
  });

  @override
  State<QuickUseSheet> createState() => _QuickUseSheetState();
}

class _QuickUseSheetState extends State<QuickUseSheet> {
  final TextEditingController _qtyCtrl = TextEditingController(text: '1');
  final TextEditingController _noteCtrl = TextEditingController();
  final FocusNode _qtyFocus = FocusNode();

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  int get _qty {
    final v = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    // บังคับช่วง 0..currentQty
    if (v < 0) return 0;
    if (v > widget.currentQty) return widget.currentQty;
    return v;
  }

  void _setQty(int v) {
    if (v < 0) v = 0;
    if (v > widget.currentQty) v = widget.currentQty;
    _qtyCtrl.text = v.toString();
    setState(() {});
  }

  bool get _isMax => _qty >= widget.currentQty;
  bool get _isMin => _qty <= 0;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.decelerate,
      padding: EdgeInsets.only(bottom: keyboard),
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.white, // ทึบ
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.9,
              minHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 42,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.yellow[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.restaurant, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ใช้วัตถุดิบ',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            Text(
                              widget.itemName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Qty card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text(
                              'จำนวนที่ใช้',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            Text(
                              'คงเหลือ: ${widget.currentQty} ${widget.unit}',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _RoundIconBtn(
                              icon: Icons.remove,
                              enabled: !_isMin,
                              onTap: () => _setQty(_qty - 1),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _qtyCtrl,
                                focusNode: _qtyFocus,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.white,
                                  hintText: '0',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey[300]!,
                                    ),
                                  ),
                                ),
                                onChanged: (_) {
                                  // ถ้าพิมพ์เกิน ให้ clamp ทันที
                                  final v =
                                      int.tryParse(_qtyCtrl.text.trim()) ?? 0;
                                  if (v > widget.currentQty) {
                                    _setQty(widget.currentQty);
                                  } else if (v < 0) {
                                    _setQty(0);
                                  } else {
                                    setState(() {});
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            _RoundIconBtn(
                              icon: Icons.add,
                              enabled: !_isMax,
                              onTap: () => _setQty(_qty + 1),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Text(
                                widget.unit,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_isMax && widget.currentQty > 0)
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'ใช้ได้สูงสุดเท่ากับจำนวนคงเหลือ',
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            1,
                            2,
                            3,
                            5,
                            10,
                          ].map((e) => _PresetChip(value: e)).toList(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Note
                  TextField(
                    controller: _noteCtrl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: 'หมายเหตุ (ไม่บังคับ)',
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Save bar with icon
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          label: const Text('ยกเลิก'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_qty > 0 && _qty <= widget.currentQty)
                              ? () async {
                                  await widget.onSave(
                                    _qty,
                                    _noteCtrl.text.trim(),
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('บันทึก'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.yellow[300],
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  const _RoundIconBtn({
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = enabled ? Colors.grey[300]! : Colors.grey[200]!;
    return Material(
      color: enabled ? Colors.white : Colors.grey[100],
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: enabled ? null : Colors.grey),
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final int value;
  const _PresetChip({required this.value});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text('$value'),
      onPressed: () {
        final state = context.findAncestorStateOfType<_QuickUseSheetState>();
        if (state == null) return;
        // ถ้า preset เกินคงเหลือ ให้ปรับเป็นคงเหลือ
        final v = value > state.widget.currentQty
            ? state.widget.currentQty
            : value;
        state._setQty(v);
      },
      shape: StadiumBorder(side: BorderSide(color: Colors.yellow[400]!)),
      backgroundColor: Colors.yellow[100],
    );
  }
}
