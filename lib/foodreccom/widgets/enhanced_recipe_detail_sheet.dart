// lib/widgets/enhanced_recipe_detail_sheet.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; // เพิ่ม dependency นี้ในไฟล์ pubspec.yaml
import '../models/recipe_model.dart';
import '../services/cooking_service.dart';

class EnhancedRecipeDetailSheet extends StatefulWidget {
  final RecipeModel recipe;

  const EnhancedRecipeDetailSheet({super.key, required this.recipe});

  @override
  State<EnhancedRecipeDetailSheet> createState() =>
      _EnhancedRecipeDetailSheetState();
}

class _EnhancedRecipeDetailSheetState extends State<EnhancedRecipeDetailSheet> {
  final CookingService _cookingService = CookingService();
  int _selectedServings = 2;
  bool _isStartingCook = false;

  @override
  void initState() {
    super.initState();
    _selectedServings = widget.recipe.servings;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBasicInfo(),
                  const SizedBox(height: 24),
                  _buildSourceReference(), // เพิ่มส่วนอ้างอิง
                  const SizedBox(height: 24),
                  _buildServingsSelector(),
                  const SizedBox(height: 24),
                  _buildIngredients(),
                  const SizedBox(height: 24),
                  _buildNutritionInfo(),
                  const SizedBox(height: 24),
                  _buildCookingSteps(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
          _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.recipe.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.recipe.description,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                    if (widget.recipe.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: widget.recipe.tags
                            .take(3)
                            .map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: widget.recipe.scoreColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${widget.recipe.matchScore}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.recipe.reason,
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoItem(
                Icons.schedule,
                '${widget.recipe.totalTime} นาที',
                'เวลารวม',
              ),
              _buildInfoItem(
                Icons.restaurant,
                widget.recipe.difficulty,
                'ความยาก',
              ),
              _buildInfoItem(Icons.category, widget.recipe.category, 'ประเภท'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourceReference() {
    if (widget.recipe.source == null && widget.recipe.sourceUrl == null) {
      return const SizedBox();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.book, color: Colors.blue[600], size: 20),
              const SizedBox(width: 8),
              const Text(
                'แหล่งอ้างอิง',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (widget.recipe.source != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.recipe.source!,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ],
          if (widget.recipe.sourceUrl != null) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _launchUrl(widget.recipe.sourceUrl!),
              child: Row(
                children: [
                  Icon(Icons.link, color: Colors.blue[600], size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'ดูสูตรต้นฉบับ',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue[600],
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  Icon(Icons.open_in_new, color: Colors.blue[600], size: 16),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildServingsSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '👥 จำนวนคนที่จะทำ',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('เลือกจำนวนคน:'),
              Row(
                children: [
                  IconButton(
                    onPressed: _selectedServings > 1
                        ? () => setState(() => _selectedServings--)
                        : null,
                    icon: Icon(
                      Icons.remove_circle,
                      color: _selectedServings > 1 ? Colors.red : Colors.grey,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_selectedServings คน',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _selectedServings < 10
                        ? () => setState(() => _selectedServings++)
                        : null,
                    icon: Icon(
                      Icons.add_circle,
                      color: _selectedServings < 10
                          ? Colors.green
                          : Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIngredients() {
    final multiplier = _selectedServings / widget.recipe.servings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🥘 วัตถุดิบ',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...widget.recipe.ingredients.map((ingredient) {
          final adjustedAmount = ingredient.amount * multiplier;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 20, color: Colors.green[600]),
                const SizedBox(width: 12),
                Expanded(child: Text(ingredient.name)),
                Text(
                  '${adjustedAmount.toStringAsFixed(adjustedAmount == adjustedAmount.roundToDouble() ? 0 : 1)} ${ingredient.unit}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (ingredient.isOptional)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'ไม่บังคับ',
                      style: TextStyle(fontSize: 10, color: Colors.orange[700]),
                    ),
                  ),
              ],
            ),
          );
        }),

        if (widget.recipe.missingIngredients.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            '🛒 ต้องซื้อเพิ่ม',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
          const SizedBox(height: 8),
          ...widget.recipe.missingIngredients.map(
            (ingredient) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.shopping_cart,
                    size: 20,
                    color: Colors.orange[600],
                  ),
                  const SizedBox(width: 12),
                  Text(ingredient),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNutritionInfo() {
    final multiplier = _selectedServings / widget.recipe.servings;
    final adjustedNutrition = NutritionInfo(
      calories: widget.recipe.nutrition.calories * multiplier,
      protein: widget.recipe.nutrition.protein * multiplier,
      carbs: widget.recipe.nutrition.carbs * multiplier,
      fat: widget.recipe.nutrition.fat * multiplier,
      fiber: widget.recipe.nutrition.fiber * multiplier,
      sodium: widget.recipe.nutrition.sodium * multiplier,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🥗 ข้อมูลโภชนาการ',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green[50]!, Colors.blue[50]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNutritionItem(
                    '🔥',
                    '${adjustedNutrition.calories.toStringAsFixed(0)}',
                    'แคลอรี',
                    Colors.red,
                  ),
                  _buildNutritionItem(
                    '🥩',
                    '${adjustedNutrition.protein.toStringAsFixed(1)}g',
                    'โปรตีน',
                    Colors.purple,
                  ),
                  _buildNutritionItem(
                    '🍞',
                    '${adjustedNutrition.carbs.toStringAsFixed(1)}g',
                    'คาร์บ',
                    Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNutritionItem(
                    '🧈',
                    '${adjustedNutrition.fat.toStringAsFixed(1)}g',
                    'ไขมัน',
                    Colors.yellow[700]!,
                  ),
                  _buildNutritionItem(
                    '🌾',
                    '${adjustedNutrition.fiber.toStringAsFixed(1)}g',
                    'ไฟเบอร์',
                    Colors.brown,
                  ),
                  _buildNutritionItem(
                    '🧂',
                    '${adjustedNutrition.sodium.toStringAsFixed(0)}mg',
                    'โซเดียม',
                    Colors.grey[700]!,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCookingSteps() {
    if (widget.recipe.steps.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '👩‍🍳 ขั้นตอนการทำ',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...widget.recipe.steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.blue[600],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.instruction,
                        style: const TextStyle(fontSize: 16),
                      ),
                      if (step.timeMinutes > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.timer,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${step.timeMinutes} นาที',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (step.tips.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...step.tips.map(
                          (tip) => Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.yellow[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.yellow[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.lightbulb,
                                  size: 14,
                                  color: Colors.amber[700],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tip,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.amber[700],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // แสดงสรุปต้นทุน
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ต้นทุนโดยประมาณ:'),
                Text(
                  'คำนวณจากสต็อก',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ปุ่มเริ่มทำอาหาร
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isStartingCook ? null : _startCooking,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: _isStartingCook
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('กำลังเตรียม...'),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.play_arrow, size: 24),
                        const SizedBox(width: 8),
                        Text(
                          'เริ่มทำเมนูนี้ ($_selectedServings คน)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.grey[600], size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildNutritionItem(
    String emoji,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
      ],
    );
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ไม่สามารถเปิดลิงก์ได้'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startCooking() async {
    setState(() => _isStartingCook = true);

    try {
      // แสดง dialog ยืนยัน
      final confirmed = await _showConfirmDialog();
      if (!confirmed) {
        setState(() => _isStartingCook = false);
        return;
      }

      // เริ่มกระบวนการทำอาหาร
      final success = await _cookingService.startCooking(
        widget.recipe,
        _selectedServings,
      );

      if (success) {
        // แสดงผลสำเร็จ
        _showSuccessDialog();
      } else {
        // แสดงข้อผิดพลาด
        _showErrorDialog('ไม่สามารถเริ่มทำอาหารได้ กรุณาตรวจสอบวัตถุดิบ');
      }
    } catch (e) {
      _showErrorDialog('เกิดข้อผิดพลาด: ${e.toString()}');
    } finally {
      setState(() => _isStartingCook = false);
    }
  }

  Future<bool> _showConfirmDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ยืนยันการทำอาหาร'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'คุณต้องการทำ "${widget.recipe.name}" สำหรับ $_selectedServings คน?',
                ),
                const SizedBox(height: 16),
                const Text(
                  'การดำเนินการนี้จะ:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('• ลดปริมาณวัตถุดิบในสต็อก'),
                const Text('• บันทึกประวัติการทำอาหาร'),
                const Text('• คำนวณโภชนาการที่ได้รับ'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.amber[700], size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'การกระทำนี้ไม่สามารถยกเลิกได้',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ยกเลิก'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  foregroundColor: Colors.white,
                ),
                child: const Text('ยืนยัน'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[600]),
            const SizedBox(width: 8),
            const Text('สำเร็จ!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('เริ่มทำอาหารเรียบร้อยแล้ว'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                children: [
                  Text('✅ ลดสต็อกวัตถุดิบแล้ว'),
                  Text('✅ บันทึกประวัติแล้ว'),
                  Text('✅ คำนวณโภชนาการแล้ว'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // ปิด dialog
              Navigator.pop(context); // ปิด bottom sheet
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('เสร็จสิ้น'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red[600]),
            const SizedBox(width: 8),
            const Text('เกิดข้อผิดพลาด'),
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
}
