import 'package:flutter/material.dart';
import '../models/recipe/recipe.dart';
import '../providers/enhanced_recommendation_provider.dart';
import '../services/nutrition_estimator.dart';
import 'package:provider/provider.dart';

class AddUserRecipeSheet extends StatefulWidget {
  const AddUserRecipeSheet({super.key});

  @override
  State<AddUserRecipeSheet> createState() => _AddUserRecipeSheetState();
}

class _AddUserRecipeSheetState extends State<AddUserRecipeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _ingredients = TextEditingController();
  final _steps = TextEditingController();
  final _imageUrl = TextEditingController();
  int _servings = 2;
  int _cookMin = 20;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _ingredients.dispose();
    _steps.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 12,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text('เพิ่มเมนูของฉัน',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'ชื่อเมนู (จำเป็น)'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'กรุณากรอกชื่อเมนู'
                    : null,
              ),
              TextFormField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'คำอธิบาย (สั้นๆ)')
              ),
              TextFormField(
                controller: _imageUrl,
                decoration: const InputDecoration(labelText: 'ลิงก์รูปภาพ (ไม่บังคับ)')
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: '2',
                      decoration: const InputDecoration(labelText: 'เสิร์ฟ (ที่)'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _servings = int.tryParse(v) ?? 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: '20',
                      decoration: const InputDecoration(labelText: 'เวลาทำ (นาที)'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _cookMin = int.tryParse(v) ?? 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _ingredients,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'วัตถุดิบ (บรรทัดละ 1 รายการ)',
                  hintText: 'เช่น\nข้าว 1 ถ้วย\nไข่ 2 ฟอง\nหมูสับ 100 กรัม',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _steps,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'วิธีทำ (บรรทัดละ 1 ขั้นตอน)',
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('บันทึก'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final ingredients = _parseIngredients(_ingredients.text);
    final steps = _parseSteps(_steps.text);
    final baseRecipe = RecipeModel(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim(),
      description: _desc.text.trim(),
      matchScore: 90,
      reason: 'เมนูที่ผู้ใช้สร้าง',
      ingredients: ingredients,
      missingIngredients: const [],
      steps: steps,
      cookingTime: _cookMin,
      prepTime: 0,
      difficulty: 'ง่าย',
      servings: _servings,
      category: 'เมนูของฉัน',
      nutrition: NutritionInfo.empty(),
      imageUrl: _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
      tags: const ['user'],
      source: 'ผู้ใช้',
      sourceUrl: null,
    );

    // ประมาณโภชนาการจากวัตถุดิบ
    final estimated = NutritionEstimator.estimateForRecipe(baseRecipe);
    final recipe = baseRecipe.copyWith(nutrition: estimated);

    try {
      await context.read<EnhancedRecommendationProvider>().addUserRecipe(recipe);
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกเมนูของฉันเรียบร้อย')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกล้มเหลว: $e')),
      );
    }
  }

  List<RecipeIngredient> _parseIngredients(String text) {
    final lines = text.split(RegExp(r'\r?\n')).map((e) => e.trim()).where((e) => e.isNotEmpty);
    return lines.map((l) {
      // very simple split: first token as name until two last tokens amount+unit if numeric exists
      final parts = l.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final amount = double.tryParse(parts[parts.length - 2]) ??
            double.tryParse(parts.last) ?? 1;
        final unit = amount == (double.tryParse(parts.last) ?? -1)
            ? ''
            : parts.last;
        final name = parts.sublist(0, parts.length - (unit.isEmpty ? 1 : 2)).join(' ');
        return RecipeIngredient(name: name, amount: amount, unit: unit);
      }
      return RecipeIngredient(name: l, amount: 1, unit: '');
    }).toList();
  }

  List<CookingStep> _parseSteps(String text) {
    final lines = text.split(RegExp(r'\r?\n')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    var i = 1;
    return lines.map((l) => CookingStep(stepNumber: i++, instruction: l)).toList();
  }
}
