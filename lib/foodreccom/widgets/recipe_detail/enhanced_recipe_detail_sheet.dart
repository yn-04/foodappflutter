//lib/foodreccom/widgets/recipe_detail/enhanced_recipe_detail_sheet.dart
import 'package:flutter/material.dart';
import '../../models/recipe/recipe_model.dart';
import '../../services/cooking_service.dart';
import '../../extensions/ui_extensions.dart';
import 'header.dart';
import 'basic_info.dart';
import 'source_reference.dart';
import 'servings_selector.dart';
import 'ingredients_list.dart';
import 'nutrition_info.dart';
import 'cooking_steps.dart';
import 'bottom_actions.dart';
import 'dialogs.dart';

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
      height: context.screenSize.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          RecipeHeader(recipe: widget.recipe),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RecipeBasicInfo(recipe: widget.recipe),
                  const SizedBox(height: 24),
                  RecipeSourceReference(recipe: widget.recipe),
                  const SizedBox(height: 24),
                  ServingsSelector(
                    selected: _selectedServings,
                    max: 10,
                    onChanged: (value) =>
                        setState(() => _selectedServings = value),
                  ),
                  const SizedBox(height: 24),
                  IngredientsList(
                    recipe: widget.recipe,
                    servings: _selectedServings,
                  ),
                  const SizedBox(height: 24),
                  NutritionInfoSection(
                    recipe: widget.recipe,
                    servings: _selectedServings,
                  ),
                  const SizedBox(height: 24),
                  CookingStepsSection(steps: widget.recipe.steps),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
          BottomActions(
            recipe: widget.recipe,
            servings: _selectedServings,
            isStarting: _isStartingCook,
            onStartCooking: _startCooking,
          ),
        ],
      ),
    );
  }

  Future<void> _startCooking() async {
    setState(() => _isStartingCook = true);
    try {
      final confirmed = await showConfirmDialog(
        context,
        recipeName: widget.recipe.name,
        servings: _selectedServings,
      );
      if (!confirmed) return;

      final success = await _cookingService.startCooking(
        widget.recipe,
        _selectedServings,
      );

      if (success) {
        showSuccessDialog(context);
      } else {
        showErrorDialog(
          context,
          'ไม่สามารถเริ่มทำอาหารได้ กรุณาตรวจสอบวัตถุดิบ',
        );
      }
    } catch (e) {
      showErrorDialog(context, 'เกิดข้อผิดพลาด: ${e.toString()}');
    } finally {
      setState(() => _isStartingCook = false);
    }
  }
}
