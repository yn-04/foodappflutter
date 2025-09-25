import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:my_app/foodreccom/models/recipe/recipe.dart';
import 'package:my_app/foodreccom/providers/enhanced_recommendation_provider.dart';
import 'package:my_app/foodreccom/widgets/recipe_card.dart';
import 'package:my_app/foodreccom/widgets/recipe_detail/enhanced_recipe_detail_sheet.dart';
import 'package:my_app/foodreccom/extensions/ui_extensions.dart';
import 'package:my_app/foodreccom/widgets/status_card.dart';
import 'package:my_app/foodreccom/widgets/add_user_recipe_sheet.dart';

class RecommendationPage extends StatefulWidget {
  const RecommendationPage({super.key});

  @override
  State<RecommendationPage> createState() => _RecommendationPageState();
}

class _RecommendationPageState extends State<RecommendationPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnhancedRecommendationProvider>().getHybridRecommendations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: '🍳 แนะนำเมนูอาหาร'.asText(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.black),
            onPressed: () => _showFilterSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: () {
              context
                  .read<EnhancedRecommendationProvider>()
                  .getHybridRecommendations();
              context.showSnack(
                '🤖 กำลังรีเฟรชคำแนะนำ (Hybrid + แปลไทย)...',
                color: Colors.yellow[700]!,
              );
            },
          ),
        ],
      ),
      body: Consumer<EnhancedRecommendationProvider>(
        builder: (context, provider, child) {
          return RefreshIndicator(
            onRefresh: provider.getHybridRecommendations,
            color: Colors.yellow[600],
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIngredientsStatus(provider),
                  const SizedBox(height: 24),
                  _buildRecommendations(provider),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: Consumer<EnhancedRecommendationProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) return const SizedBox();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'add_user_recipe',
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const AddUserRecipeSheet(),
                ),
                backgroundColor: Colors.green[400],
                child: const Icon(Icons.add, color: Colors.white),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'refresh_recs',
                onPressed: () {
                  provider.getHybridRecommendations();
                  context.showSnack(
                    '🤖 กำลังขอคำแนะนำใหม่ และแปลเป็นภาษาไทย...',
                    color: Colors.yellow[700]!,
                  );
                },
                backgroundColor: Colors.yellow[600],
                child: const Icon(Icons.psychology, color: Colors.black),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIngredientsStatus(EnhancedRecommendationProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.inventory_2,
              color: Colors.orange,
            ).withPadding(const EdgeInsets.all(8)),
            'สถานะวัตถุดิบ'.asText(fontSize: 18, fontWeight: FontWeight.bold),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatusItem(
              'ทั้งหมด',
              '${provider.ingredients.length}',
              Colors.blue,
              Icons.inventory,
            ),
            _buildStatusItem(
              'ใกล้หมดอายุ',
              '${provider.nearExpiryIngredients.length}',
              Colors.red,
              Icons.warning,
            ),
            _buildStatusItem(
              'เมนูแนะนำ',
              '${provider.recommendations.length}',
              Colors.green,
              Icons.restaurant_menu,
            ),
          ],
        ),
      ],
    ).asCard(radius: 16, color: Colors.yellow[50]);
  }

  Widget _buildStatusItem(
    String label,
    String count,
    Color color,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, color: color).withPadding(const EdgeInsets.all(4)),
        count.asText(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        label.asText(fontSize: 12, color: Colors.grey[700]!),
      ],
    );
  }

  Widget _buildRecommendations(EnhancedRecommendationProvider provider) {
    if (provider.isLoading) {
      return const StatusCard.loading(
        title: '🤖 AI + API กำลังคิดเมนู...',
        subtitle: 'และกำลังแปลเป็นภาษาไทย 🇹🇭',
        color: Colors.yellow,
      );
    }

    if (provider.error != null) {
      return StatusCard.error(
        message: provider.error!,
        onRetry: () => provider.getHybridRecommendations(),
      );
    }

    if (provider.recommendations.isEmpty) {
      return StatusCard.empty(
        hasIngredients: provider.ingredients.isNotEmpty,
        onRetry: () => provider.getHybridRecommendations(),
        onAdd: () => Navigator.pop(context),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.restaurant_menu,
              color: Colors.green,
            ).withPadding(const EdgeInsets.all(8)),
            'เมนูแนะนำ (Hybrid)'.asText(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: provider.recommendations.length,
          itemBuilder: (context, index) {
            return RecipeCard(
              recipe: provider.recommendations[index],
              showSourceBadge: true,
              onTap: () => _showRecipeDetail(provider.recommendations[index]),
            );
          },
        ),
      ],
    );
  }

  void _showRecipeDetail(RecipeModel recipe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EnhancedRecipeDetailSheet(recipe: recipe),
    );
  }

  void _showFilterSheet(BuildContext context) {
    final provider = context.read<EnhancedRecommendationProvider>();
    final cuisines = const [
      {'th': 'จีน', 'en': 'chinese'},
      {'th': 'ญี่ปุ่น', 'en': 'japanese'},
      {'th': 'เกาหลี', 'en': 'korean'},
      {'th': 'ไทย', 'en': 'thai'},
    ];
    final dietKeys = const ['Vegan', 'High-Fiber', 'High-Protein', 'Low-Carb'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final current = provider.filters;
        final selectedCuisine = current.cuisineEn.toSet();
        final selectedDiet = current.dietGoals
            .map((e) => e[0].toUpperCase() + e.substring(1))
            .toSet();
        final manualNames =
            (current.manualIngredientNames ?? []).toSet();
        int? minCal = current.minCalories;
        int? maxCal = current.maxCalories;

        return StatefulBuilder(builder: (context, setState) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.9,
            minChildSize: 0.6,
            builder: (context, scroll) {
              return SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
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
                    'ตัวกรองเมนูอาหาร'.asText(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    const SizedBox(height: 16),
                    'วัตถุดิบที่ต้องการใช้ (เลือกได้)'.asText(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: provider.ingredients.take(20).map((ing) {
                        final checked = manualNames.contains(ing.name);
                        return FilterChip(
                          label: Text(ing.name),
                          selected: checked,
                          onSelected: (v) {
                            setState(() {
                              if (v) {
                                manualNames.add(ing.name);
                              } else {
                                manualNames.remove(ing.name);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    'ประเภทอาหาร'.asText(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    ...cuisines.map((c) {
                      final en = c['en']!;
                      final th = c['th']!;
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: selectedCuisine.contains(en),
                        title: Text(th),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              selectedCuisine.add(en);
                            } else {
                              selectedCuisine.remove(en);
                            }
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                    'โภชนาการ'.asText(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    ...dietKeys.map((k) {
                      final key = k.toLowerCase();
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: selectedDiet.contains(k),
                        title: Text(k),
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              selectedDiet.add(k);
                            } else {
                              selectedDiet.remove(k);
                            }
                          });
                        },
                      );
                    }).toList(),
                    const SizedBox(height: 8),
                    'แคลอรี่ต่อเมนู'.asText(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            keyboardType: TextInputType.number,
                            initialValue: minCal?.toString() ?? '',
                            decoration: const InputDecoration(
                              labelText: 'ขั้นต่ำ (kcal)',
                            ),
                            onChanged: (v) {
                              setState(() {
                                minCal = int.tryParse(v);
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            keyboardType: TextInputType.number,
                            initialValue: maxCal?.toString() ?? '',
                            decoration: const InputDecoration(
                              labelText: 'ขั้นสูง (kcal)',
                            ),
                            onChanged: (v) {
                              setState(() {
                                maxCal = int.tryParse(v);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            provider.setCuisineFilters(selectedCuisine.toList());
                            provider.setDietGoals(selectedDiet
                                .map((e) => e.toLowerCase())
                                .toSet());
                            provider.setCalorieRange(
                              min: minCal,
                              max: maxCal,
                            );
                            provider.setManualIngredientNames(manualNames.toList());
                            Navigator.pop(context);
                            provider.getHybridRecommendations();
                          },
                          child: const Text('Yes'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        });
      },
    );
  }
}
