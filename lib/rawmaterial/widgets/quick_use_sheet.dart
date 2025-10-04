// lib/rawmaterial/widgets/quick_use_sheet.dart
import 'package:flutter/material.dart';

import 'package:my_app/rawmaterial/constants/units.dart';
import 'package:my_app/rawmaterial/utils/unit_converter.dart';

class QuickUseSheet extends StatefulWidget {
  final String itemName;
  final String unit;
  final int currentQty;
  final Future<void> Function(int useQty, String unit, String note) onSave;

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

  bool _saving = false;
  bool _hasChanges = true;
  bool _initializing = true;
  late String _baseUnit;
  late String _selectedUnit;

  List<String> get _unitOptions {
    final options = UnitConverter.fallbackOptions(_baseUnit);
    if (!options.contains(_baseUnit)) {
      options.insert(0, _baseUnit);
    }
    return options;
  }

  int _availableQtyForUnit(String unit) {
    if (unit == _baseUnit) return widget.currentQty;
    return UnitConverter.convertQuantity(
      quantity: widget.currentQty,
      from: _baseUnit,
      to: unit,
    );
  }

  int get _currentQtyInSelectedUnit => _availableQtyForUnit(_selectedUnit);
  int get _maxQty => _currentQtyInSelectedUnit;

  @override
  void initState() {
    super.initState();
    _baseUnit = Units.safe(widget.unit);
    _selectedUnit = _baseUnit;
    _noteCtrl.addListener(_handleNoteChanged);
    _qtyFocus.addListener(_handleQtyFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializing = false;
    });
  }

  @override
  void dispose() {
    _noteCtrl.removeListener(_handleNoteChanged);
    _qtyFocus.removeListener(_handleQtyFocusChange);
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  void _handleNoteChanged() {
    if (_initializing) return;
    _markDirty();
  }

  void _handleQtyFocusChange() {
    if (_qtyFocus.hasFocus || _saving) return;
    _markDirty();
  }

  void _markDirty() {
    if (!_hasChanges) {
      _hasChanges = true;
    }
  }

  int get _qty {
    final v = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (v < 0) return 0;
    if (v > _maxQty) return _maxQty;
    return v;
  }

  void _setQty(int v) {
    final max = _maxQty;
    if (v < 0) v = 0;
    if (v > max) v = max;
    _qtyCtrl.text = v.toString();
    _markDirty();
    setState(() {});
  }

  bool get _isMax => _qty >= _maxQty;
  bool get _isMin => _qty <= 0;
  bool get _hasValidQty => _qty > 0 && _qty <= _maxQty;
  bool get _canSave => !_saving && _hasValidQty;

  Future<bool> _saveChanges() async {
    if (_saving) return false;
    final qty = _qty;
    if (qty <= 0 || qty > _maxQty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('จำนวนที่ใช้ไม่ถูกต้อง')));
      }
      return false;
    }

    if (!_hasChanges) {
      return true;
    }

    setState(() => _saving = true);
    try {
      await widget.onSave(qty, _selectedUnit, _noteCtrl.text.trim());
      _hasChanges = false;
      return true;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (_saving) return false;
    return true;
  }

  Future<void> _handleSaveButton() async {
    final saved = await _saveChanges();
    if (!mounted || !saved) return;
    Navigator.of(context).pop(true);
  }

  void _handleDiscardButton() {
    if (_saving) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    final topPadding = keyboard > 0 ? 16.0 : 48.0;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.fromLTRB(16, topPadding, 16, keyboard + 16),
        child: Center(
          child: FractionallySizedBox(
            heightFactor: 0.75,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Material(
                color: Colors.white,
                elevation: 12,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                      child: Row(
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
                                  'บันทึกการใช้วัตถุดิบ',
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check),
                                color: Colors.green[600],
                                tooltip: 'บันทึก',
                                onPressed: _canSave ? _handleSaveButton : null,
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: 'ไม่บันทึก',
                                onPressed: _saving
                                    ? null
                                    : _handleDiscardButton,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_saving)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    Expanded(
                      child: AbsorbPointer(
                        absorbing: _saving,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // แถบคงเหลือ
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.yellow[100],
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'คงเหลือ: $_currentQtyInSelectedUnit $_selectedUnit',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // จำนวนที่ใช้
                              const Text(
                                'จำนวนที่ใช้',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),

                              // แก้ overflow: จำกัดความกว้าง dropdown และไม่ใช้ Expanded ซ้อนเกิน
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  return Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      _RoundIconBtn(
                                        icon: Icons.remove,
                                        enabled: !_isMin,
                                        onTap: () => _setQty(_qty - 1),
                                      ),
                                      const SizedBox(width: 10),
                                      // ช่องจำนวน: ใช้ Flexible เพื่อยืดหยุ่น
                                      Flexible(
                                        flex: 1,
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
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                color: Colors.grey[300]!,
                                              ),
                                            ),
                                          ),
                                          onChanged: (_) {
                                            final v =
                                                int.tryParse(
                                                  _qtyCtrl.text.trim(),
                                                ) ??
                                                0;
                                            if (v > _maxQty) {
                                              _setQty(_maxQty);
                                            } else if (v < 0) {
                                              _setQty(0);
                                            } else {
                                              _markDirty();
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
                                      const SizedBox(width: 12),
                                      // หน่วย: กำหนดความกว้างแน่นอน เพื่อลดความเสี่ยง overflow
                                      SizedBox(
                                        width: 140, // ปรับได้ตามดีไซน์
                                        child: DropdownButtonFormField<String>(
                                          value: _selectedUnit,
                                          items: _unitOptions
                                              .map(
                                                (u) => DropdownMenuItem<String>(
                                                  value: u,
                                                  child: Text(u),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (value) {
                                            if (value == null) return;
                                            final newUnit = Units.safe(value);
                                            if (newUnit == _selectedUnit)
                                              return;
                                            final currentValue =
                                                int.tryParse(
                                                  _qtyCtrl.text.trim(),
                                                ) ??
                                                0;
                                            final converted =
                                                UnitConverter.convertQuantity(
                                                  quantity: currentValue,
                                                  from: _selectedUnit,
                                                  to: newUnit,
                                                );
                                            final max = _availableQtyForUnit(
                                              newUnit,
                                            );
                                            var clamped = converted;
                                            if (clamped < 0) clamped = 0;
                                            if (clamped > max) clamped = max;
                                            setState(() {
                                              _selectedUnit = newUnit;
                                              _qtyCtrl.text = clamped
                                                  .toString();
                                            });
                                            _markDirty();
                                          },
                                          decoration: InputDecoration(
                                            isDense: true,
                                            filled: true,
                                            fillColor: Colors.white,
                                            labelText: 'หน่วย',
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide(
                                                color: Colors.grey[300]!,
                                              ),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),

                              const SizedBox(height: 10),
                              if (_isMax && _maxQty > 0)
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

                              const SizedBox(height: 20),

                              // หมายเหตุ
                              const Text(
                                'หมายเหตุ (ถ้ามี)',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              TextField(
                                controller: _noteCtrl,
                                minLines: 1,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.grey[50],
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey[300]!,
                                    ),
                                  ),
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
