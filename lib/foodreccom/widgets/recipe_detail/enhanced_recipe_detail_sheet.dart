//lib/foodreccom/widgets/recipe_detail/enhanced_recipe_detail_sheet.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/recipe/recipe_model.dart';
import '../../services/cooking_service.dart';
import 'header.dart';
import 'basic_info.dart';
import 'servings_selector.dart';
import 'ingredients_list.dart';
import 'nutrition_info.dart';
import 'bottom_actions.dart';
import 'dialogs.dart';
import 'missing_ingredients.dart';
import 'frequency_notice.dart';
import '../../pages/cooking_session_page.dart';
import '../../providers/enhanced_recommendation_provider.dart';

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
  Map<String, double> _manualIngredientAmounts = const {};
  late final int _maxSelectableServings;

  @override
  void initState() {
    super.initState();
    final baseServings = widget.recipe.servings <= 0
        ? 1
        : widget.recipe.servings;
    _maxSelectableServings = math.max(10, baseServings);
    final provider = context.read<EnhancedRecommendationProvider>();
    final override = provider.getServingsOverride(widget.recipe.id);
    if (override != null && override > 0) {
      _selectedServings = override;
    } else {
      _selectedServings = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        provider.setServingsOverride(widget.recipe.id, _selectedServings);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: size.height,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 16),
              RecipeHeader(recipe: widget.recipe),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RecipeBasicInfo(recipe: widget.recipe),
                      RecipeFrequencyNotice(recipe: widget.recipe),
                      const SizedBox(height: 24),
                      ServingsSelector(
                        selected: _selectedServings,
                        max: _maxSelectableServings,
                        onChanged: (value) {
                          setState(() {
                            _selectedServings = value;
                            _manualIngredientAmounts = const {};
                          });
                          context
                              .read<EnhancedRecommendationProvider>()
                              .setServingsOverride(widget.recipe.id, value);
                        },
                      ),
                      // Missing ingredients block (highlight)
                      MissingIngredientsSection(
                        recipe: widget.recipe,
                        servings: _selectedServings,
                        manualRequiredAmounts: _manualIngredientAmounts.isEmpty
                            ? null
                            : _manualIngredientAmounts,
                      ),
                      const SizedBox(height: 16),
                      IngredientsList(
                        recipe: widget.recipe,
                        servings: _selectedServings,
                        manualRequiredAmounts: _manualIngredientAmounts.isEmpty
                            ? null
                            : _manualIngredientAmounts,
                      ),
                      const SizedBox(height: 24),
                      NutritionInfoSection(
                        recipe: widget.recipe,
                        servings: _selectedServings,
                      ),
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
        ),
      ),
    );
  }

  Future<void> _startCooking() async {
    final adjustments = await showIngredientConfirmationDialog(
      context,
      recipe: widget.recipe,
      servings: _selectedServings,
      initialRequiredAmounts: _manualIngredientAmounts.isEmpty
          ? null
          : _manualIngredientAmounts,
    );
    if (adjustments == null) return;

    final manual = Map<String, double>.from(adjustments);

    setState(() {
      _isStartingCook = true;
      _manualIngredientAmounts = manual;
    });
    try {
      final preview = await _cookingService.previewCooking(
        widget.recipe,
        _selectedServings,
        manualRequiredAmounts: manual.isEmpty ? null : manual,
      );

      bool allowPartial = false;

      if (!preview.isSufficient && preview.shortages.isNotEmpty) {
        final proceed = await showShortageDialog(
          context,
          recipe: widget.recipe,
          servings: _selectedServings,
          shortages: preview.shortages,
          manualRequiredAmounts: manual.isEmpty ? null : manual,
        );
        if (!proceed) return;
        allowPartial = true;
      }

      final result = await _cookingService.startCooking(
        widget.recipe,
        _selectedServings,
        allowPartial: allowPartial,
        manualRequiredAmounts: manual.isEmpty ? null : manual,
      );

      if (result.success) {
        if (!mounted) return;
        final provider = context.read<EnhancedRecommendationProvider>();
        await provider.loadIngredients();
        final inventory = provider.ingredients;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CookingSessionPage(
              recipe: widget.recipe,
              servings: _selectedServings,
              inventory: inventory,
              shortages: result.shortages,
              partial: result.partial,
              manualRequiredAmounts: manual.isEmpty ? null : manual,
            ),
          ),
        );
      } else if (result.shortages.isNotEmpty) {
        showErrorDialog(
          context,
          'ไม่สามารถเริ่มทำอาหารได้ เนื่องจากวัตถุดิบไม่เพียงพอ',
        );
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
