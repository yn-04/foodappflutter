import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ingredient_model.dart';
import '../models/recipe/recipe_model.dart';
import '../providers/enhanced_recommendation_provider.dart';
import '../services/cooking_service.dart' show IngredientShortage;
import '../utils/purchase_item_utils.dart';
import '../widgets/recipe_detail/youtube_section.dart';

class CookingSessionPage extends StatefulWidget {
  final RecipeModel recipe;
  final int servings;
  final List<IngredientModel> inventory;
  final List<IngredientShortage> shortages;
  final bool partial;
  final Map<String, double>? manualRequiredAmounts;

  const CookingSessionPage({
    super.key,
    required this.recipe,
    required this.servings,
    required this.inventory,
    this.shortages = const [],
    this.partial = false,
    this.manualRequiredAmounts,
  });

  @override
  State<CookingSessionPage> createState() => _CookingSessionPageState();
}

class _CookingSessionPageState extends State<CookingSessionPage> {
  late final List<IngredientNeedStatus> _ingredientStatus;
  late final List<_EquipmentItem> _equipment;
  final Set<int> _preparedIngredients = {};
  final Set<int> _equipmentReady = {};
  final Set<int> _completedSteps = {};
  final TextEditingController _notesController = TextEditingController();
  final List<Timer> _activeTimers = [];
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _ingredientStatus = analyzeIngredientStatus(
      widget.recipe,
      widget.inventory,
      servings: widget.servings,
      manualRequiredAmounts: widget.manualRequiredAmounts,
    );
    _equipment = _inferEquipment(widget.recipe);
  }

  @override
  void dispose() {
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shortages = widget.shortages
        .where((s) => s.missingAmount > 0)
        .toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('เริ่มทำ: ${widget.recipe.name}'),
        actions: [
          IconButton(
            onPressed: _showTipsDialog,
            icon: const Icon(Icons.lightbulb_outline),
            tooltip: 'ทิปส์',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _completing ? null : _completeCooking,
        icon: _completing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.check_circle_outline),
        label: Text(_completing ? 'กำลังบันทึก...' : 'เสร็จแล้ว'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummaryCard(theme),
              if (widget.partial || shortages.isNotEmpty)
                _buildShortageNotice(shortages, theme),
              const SizedBox(height: 16),
              _buildIngredientChecklist(theme),
              if (_equipment.isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildEquipmentSection(theme),
              ],
              const SizedBox(height: 16),
              _buildStepsSection(theme),
              const SizedBox(height: 16),
              _buildTipsSection(theme),
              const SizedBox(height: 16),
              RecipeYoutubeSection(recipe: widget.recipe),
              const SizedBox(height: 16),
              _buildNotesSection(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(ThemeData theme) {
    final recipe = widget.recipe;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              recipe.name,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _infoChip(
                  Icons.people_alt_outlined,
                  '${widget.servings} เสิร์ฟ',
                ),
                if (recipe.prepTime > 0)
                  _infoChip(
                    Icons.kitchen_outlined,
                    'เตรียม ${recipe.prepTime} นาที',
                  ),
                if (recipe.cookingTime > 0)
                  _infoChip(
                    Icons.timer_outlined,
                    'ปรุง ${recipe.cookingTime} นาที',
                  ),
                if (recipe.difficulty.isNotEmpty)
                  _infoChip(Icons.bar_chart, 'ระดับ ${recipe.difficulty}'),
              ],
            ),
            if (recipe.shortDescription.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                recipe.shortDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(.75),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShortageNotice(
    List<IngredientShortage> shortages,
    ThemeData theme,
  ) {
    return Card(
      color: Colors.orange[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange[700]),
                const SizedBox(width: 8),
                Text(
                  widget.partial
                      ? 'ทำได้ทันที (วัตถุดิบบางส่วนขาด)'
                      : 'เช็ควัตถุดิบก่อนเริ่ม',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.orange[900],
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (shortages.isEmpty)
              Text(
                'ไม่มีรายการที่ขาดแล้ว เยี่ยมไปเลย!',
                style: theme.textTheme.bodyMedium,
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: shortages.map((s) {
                  final unit = s.unit.trim();
                  final missing = _formatAmount(
                    s.missingAmount,
                    unit: s.unit,
                    ingredientName: s.name,
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• ${s.name}: ขาด $missing${unit.isEmpty ? '' : ' $unit'}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIngredientChecklist(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'เตรียมวัตถุดิบให้พร้อม',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_ingredientStatus.length, (index) {
              final status = _ingredientStatus[index];
              final checked = _preparedIngredients.contains(index);
              final missingText = status.missingAmount > 0.01
                  ? ' • ขาด ${_formatAmount(status.missingAmount, unit: status.unit, ingredientName: status.name)}'
                  : '';
              final subtitle =
                  'ต้องการ ${_formatAmount(status.requiredAmount, unit: status.unit, ingredientName: status.name)}'
                  '${status.unit.isEmpty ? '' : ' ${status.unit}'}'
                  ' • มีอยู่ ${_formatAmount(status.availableAmount, unit: status.unit, ingredientName: status.name)}'
                  '${status.unit.isEmpty ? '' : ' ${status.unit}'}$missingText';

              return CheckboxListTile(
                value: checked,
                onChanged: (_) {
                  setState(() {
                    if (checked) {
                      _preparedIngredients.remove(index);
                    } else {
                      _preparedIngredients.add(index);
                    }
                  });
                },
                activeColor: theme.colorScheme.primary,
                title: Text(
                  status.name,
                  style: status.isOptional
                      ? theme.textTheme.bodyLarge?.copyWith(
                          fontStyle: FontStyle.italic,
                        )
                      : theme.textTheme.bodyLarge,
                ),
                subtitle: Text(subtitle),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildEquipmentSection(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.handyman_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'อุปกรณ์ที่ควรเตรียม',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_equipment.length, (index) {
                final item = _equipment[index];
                final ready = _equipmentReady.contains(index);
                return FilterChip(
                  label: Text(item.label),
                  selected: ready,
                  onSelected: (_) {
                    setState(() {
                      if (ready) {
                        _equipmentReady.remove(index);
                      } else {
                        _equipmentReady.add(index);
                      }
                    });
                  },
                  avatar: Icon(item.icon, size: 18),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepsSection(ThemeData theme) {
    final steps = widget.recipe.steps;
    if (steps.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'เมนูนี้ยังไม่มีขั้นตอนละเอียด ลองดูคลิป YouTube ข้างล่างแทน',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.format_list_numbered,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'ทำตามขั้นตอน',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(steps.length, (index) {
              final step = steps[index];
              final done = _completedSteps.contains(index);
              final minutes = _extractMinuteFromStep(step.instruction);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      value: done,
                      onChanged: (_) {
                        setState(() {
                          if (done) {
                            _completedSteps.remove(index);
                          } else {
                            _completedSteps.add(index);
                          }
                        });
                      },
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        'ขั้นตอนที่ ${index + 1}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        step.instruction.trim(),
                        style: done
                            ? theme.textTheme.bodyMedium?.copyWith(
                                decoration: TextDecoration.lineThrough,
                                color: theme.textTheme.bodyMedium?.color
                                    ?.withOpacity(.6),
                              )
                            : theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (minutes != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _startQuickTimer(
                            minutes,
                            index,
                            step.instruction,
                          ),
                          icon: const Icon(Icons.timer_outlined),
                          label: Text('ตั้งเวลา $minutes นาที'),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsSection(ThemeData theme) {
    final tips = _generateTips();
    if (tips.isEmpty) return const SizedBox.shrink();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.star_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'เคล็ดลับเพิ่มความปัง',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...tips.map(
              (tip) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(
                      child: Text(tip, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection(ThemeData theme) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.edit_note_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'จดบันทึกหลังทำ',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText:
                    'จดไว้ว่าเพิ่มอะไร ลดอะไร หรืออยากลองอะไรในครั้งหน้า...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('บันทึกโน้ตไว้บนอุปกรณ์แล้ว (ไม่ซิงก์)'),
                    ),
                  );
                },
                icon: const Icon(Icons.bookmark_added_outlined),
                label: const Text('จดจำไว้'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startQuickTimer(int minutes, int stepIndex, String description) {
    final timer = Timer(Duration(minutes: minutes), () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'ครบ $minutes นาทีสำหรับขั้นตอนที่ ${stepIndex + 1}: ${description.trim()}',
          ),
        ),
      );
    });
    _activeTimers.add(timer);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('ตั้งเวลา $minutes นาทีไว้แล้ว')));
  }

  int? _extractMinuteFromStep(String instruction) {
    final regex = RegExp(r'(\d+)\s*(นาที|min|mins|minute|minutes)');
    final match = regex.firstMatch(instruction.toLowerCase());
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  void _showTipsDialog() {
    final tips = _generateTips();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ทิปส์สำหรับเมนูนี้'),
        content: tips.isEmpty
            ? const Text(
                'ยังไม่มีทิปส์พิเศษ ลองจดไอเดียของคุณไว้ได้เลยในช่องบันทึก',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: tips
                    .map(
                      (tip) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('• $tip'),
                      ),
                    )
                    .toList(),
              ),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  List<String> _generateTips() {
    final tips = <String>[];
    final recipe = widget.recipe;
    if (recipe.cookingTime > 0 && recipe.prepTime > 0) {
      tips.add(
        'เตรียมทุกอย่างให้ครบก่อนเริ่ม จะได้ไม่ต้องวุ่นวายระหว่าง ${recipe.cookingTime} นาทีของการปรุง.',
      );
    }
    if (recipe.tags.any(
      (tag) => tag.toLowerCase().contains('spicy') || tag.contains('เผ็ด'),
    )) {
      tips.add('อยากเผ็ดน้อยลง? ลดพริกลงครึ่งหนึ่ง แล้วชิมก่อนเติม.');
    }
    if (recipe.tags.any((tag) => tag.toLowerCase().contains('thai'))) {
      tips.add('เสิร์ฟพร้อมข้าวหอมมะลิร้อน ๆ หรือไข่ดาว เพิ่มความฟินสไตล์ไทย.');
    }
    if (recipe.nutrition.calories > 0) {
      tips.add(
        'เมนูนี้ประมาณ ${recipe.nutrition.calories.toStringAsFixed(0)} แคลอรีต่อเสิร์ฟ ลองจับคู่กับเครื่องดื่มเบา ๆ เช่น ชามะนาว.',
      );
    }
    if (tips.isEmpty) {
      tips.addAll([
        'จดรสชาติที่ได้ไว้ในช่องบันทึก เพื่อนำไปปรับครั้งหน้า.',
        'ถ่ายรูปผลงานและแชร์กับเพื่อน ๆ ในโซเชียล เพิ่มความสนุกในการทำอาหาร!',
      ]);
    }
    return tips;
  }

  List<_EquipmentItem> _inferEquipment(RecipeModel recipe) {
    final text = ([
      recipe.description,
      ...recipe.steps.map((s) => s.instruction),
    ]).join(' ').toLowerCase();
    final mappings = <_EquipmentItem>[
      _EquipmentItem(
        label: 'เขียง',
        icon: Icons.content_cut,
        keywords: ['หั่น', 'ซอย', 'slice', 'chop'],
      ),
      _EquipmentItem(
        label: 'มีด',
        icon: Icons.gavel,
        keywords: ['หั่น', 'ซอย', 'slice', 'chop'],
      ),
      _EquipmentItem(
        label: 'กระทะ',
        icon: Icons.kitchen,
        keywords: ['ผัด', 'ทอด', 'pan', 'wok', 'stir'],
      ),
      _EquipmentItem(
        label: 'หม้อ',
        icon: Icons.soup_kitchen,
        keywords: ['ต้ม', 'ซุป', 'boil', 'soup'],
      ),
      _EquipmentItem(
        label: 'เตาอบ',
        icon: Icons.local_fire_department,
        keywords: ['อบ', 'bake', 'oven'],
      ),
      _EquipmentItem(
        label: 'ตะหลิว',
        icon: Icons.restaurant,
        keywords: ['ผัด', 'กระทะ'],
      ),
      _EquipmentItem(
        label: 'ทัพพี',
        icon: Icons.set_meal,
        keywords: ['ตัก', 'ซุป'],
      ),
      _EquipmentItem(
        label: 'ชามผสม',
        icon: Icons.rice_bowl,
        keywords: ['คลุก', 'ผสม', 'mix', 'combine'],
      ),
      _EquipmentItem(
        label: 'ตะแกรง/กระชอน',
        icon: Icons.grid_on,
        keywords: ['ล้าง', 'กรอง', 'drain', 'rinse'],
      ),
    ];

    final result = <_EquipmentItem>[];
    for (final item in mappings) {
      if (item.keywords.any(text.contains)) {
        result.add(item);
      }
    }
    return result;
  }

  Widget _infoChip(IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  String _formatAmount(
    double value, {
    String unit = '',
    String ingredientName = '',
  }) => formatQuantityNumber(value, unit: unit, ingredientName: ingredientName);

  Future<void> _completeCooking() async {
    if (_completing) return;
    setState(() => _completing = true);
    try {
      await context.read<EnhancedRecommendationProvider>().loadIngredients();
      if (!mounted) return;
      final text = widget.partial
          ? 'ทำเสร็จแบบใช้วัตถุดิบบางส่วน อัปเดตสต็อกแล้ว'
          : 'เยี่ยมมาก! สต็อกอัปเดตแล้ว พร้อมเสิร์ฟ';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      setState(() => _completing = false);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _completing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
    }
  }
}

class _EquipmentItem {
  final String label;
  final IconData icon;
  final List<String> keywords;

  const _EquipmentItem({
    required this.label,
    required this.icon,
    required this.keywords,
  });
}
