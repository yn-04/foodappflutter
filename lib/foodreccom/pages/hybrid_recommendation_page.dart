//lib/foodreccom/pages/hybrid_recommendation_page.dart
import 'package:flutter/material.dart';
import '../providers/hybrid_recommendation_provider.dart';
import '../widgets/recipe_card.dart';
import '../widgets/recipe_detail/enhanced_recipe_detail_sheet.dart';
import 'package:provider/provider.dart';
import '../models/recipe/recipe.dart';

class HybridRecommendationPage extends StatefulWidget {
  const HybridRecommendationPage({super.key});

  @override
  State<HybridRecommendationPage> createState() =>
      _HybridRecommendationPageState();
}

class _HybridRecommendationPageState extends State<HybridRecommendationPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HybridRecommendationProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
        title: const Text(
          'ระบบแนะนำเมนูอัจฉริยะ',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          Consumer<HybridRecommendationProvider>(
            builder: (context, provider, child) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.tune, color: Colors.black),
                onSelected: (value) => _handleMenuAction(value, provider),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'settings',
                    child: Row(
                      children: [
                        Icon(Icons.settings, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        const Text('การตั้งค่า'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'analytics',
                    child: Row(
                      children: [
                        Icon(Icons.analytics, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        const Text('รายงานการใช้งาน'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'shopping_list',
                    child: Row(
                      children: [
                        Icon(Icons.shopping_cart, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        const Text('รายการซื้อของ'),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.orange[600],
          unselectedLabelColor: Colors.grey[600],
          indicatorColor: Colors.orange[600],
          tabs: const [
            Tab(text: 'ทั้งหมด', icon: Icon(Icons.restaurant_menu, size: 20)),
            Tab(text: 'ป้องกันเสีย', icon: Icon(Icons.warning, size: 20)),
            Tab(text: 'ทำเร็ว', icon: Icon(Icons.timer, size: 20)),
            Tab(text: 'ประหยัด', icon: Icon(Icons.attach_money, size: 20)),
          ],
        ),
      ),
      body: Consumer<HybridRecommendationProvider>(
        builder: (context, provider, child) {
          return RefreshIndicator(
            onRefresh: provider.refresh,
            color: Colors.orange[600],
            child: Column(
              children: [
                _buildStatusAndAnalysis(provider),
                _buildCookingHistorySection(provider),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAllRecommendations(provider),
                      _buildWastePreventionTab(provider),
                      _buildQuickRecipesTab(provider),
                      _buildBudgetFriendlyTab(provider),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: Consumer<HybridRecommendationProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) return Container();

          return FloatingActionButton(
            onPressed: () {
              provider.getHybridRecommendations();
              _showSnackBar('กำลังค้นหาเมนูใหม่...');
            },
            backgroundColor: Colors.orange[600],
            child: const Icon(Icons.auto_awesome, color: Colors.white),
          );
        },
      ),
    );
  }

  // ------------------- STATUS & ANALYSIS -------------------
  Widget _buildStatusAndAnalysis(HybridRecommendationProvider provider) {
    if (provider.isLoading) return _buildLoadingCard();
    if (provider.error != null) return _buildErrorCard(provider.error!);

    final analysis = provider.hybridAnalysis;
    if (analysis == null) return Container();

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    analysis.summary,
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildScoreItem(
                  'ป้องกันเสีย',
                  '${analysis.wastePreventionScore}%',
                  Colors.green,
                ),
                _buildScoreItem(
                  'หลากหลาย',
                  '${analysis.diversityScore}%',
                  Colors.purple,
                ),
                _buildScoreItem(
                  'รวม',
                  '${analysis.overallScore}',
                  Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'AI ${analysis.aiRecommendationCount} เมนู, API ${analysis.externalRecommendationCount} เมนู',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCookingHistorySection(HybridRecommendationProvider provider) {
    final history = provider.cookingHistory;
    if (history.isEmpty) return const SizedBox.shrink();

    final recent = [...history]
      ..sort((a, b) => b.cookedAt.compareTo(a.cookedAt));
    final display = recent.take(10).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: Colors.orange[600]),
              const SizedBox(width: 8),
              const Text(
                'เมนูที่เคยทำล่าสุด',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: display.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = display[index];
                return Container(
                  width: 170,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.recipeName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.orange[900],
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(Icons.people_alt, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            '${item.servingsMade} เสิร์ฟ',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            _formatThaiDate(item.cookedAt),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatThaiDate(DateTime date) {
    const months = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    final month = months[date.month - 1];
    final buddhistYear = date.year + 543;
    return '${date.day} $month ${buddhistYear.toString().substring(2)}';
  }

  Widget _buildScoreItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildLoadingCard() =>
      const Center(child: CircularProgressIndicator());
  Widget _buildErrorCard(String error) => Center(
    child: Text('❌ $error', style: TextStyle(color: Colors.red)),
  );

  // ------------------- RECIPE TABS -------------------
  Widget _buildAllRecommendations(HybridRecommendationProvider provider) {
    final recs = provider.allRecommendations;
    if (recs.isEmpty) return _buildEmptyState('ยังไม่มีเมนูแนะนำ');
    return _buildRecipeList(recs);
  }

  Widget _buildWastePreventionTab(HybridRecommendationProvider provider) {
    final recs = provider.wastePreventionRecommendations;
    if (recs.isEmpty) return _buildEmptyState('ไม่มีเมนูป้องกันของเสีย');
    return _buildRecipeList(recs);
  }

  Widget _buildQuickRecipesTab(HybridRecommendationProvider provider) {
    final recs = provider.quickRecipes;
    if (recs.isEmpty) return _buildEmptyState('ไม่มีเมนูทำเร็ว');
    return _buildRecipeList(recs);
  }

  Widget _buildBudgetFriendlyTab(HybridRecommendationProvider provider) {
    final recs = provider.budgetFriendlyRecipes;
    if (recs.isEmpty) return _buildEmptyState('ไม่มีเมนูประหยัด');
    return _buildRecipeList(recs);
  }

  Widget _buildRecipeList(List<RecipeModel> recipes) {
    return ListView.builder(
      itemCount: recipes.length,
      itemBuilder: (context, index) {
        final recipe = recipes[index];
        return RecipeCard(
          recipe: recipe,
          compact: true,
          onTap: () => _showRecipeDetail(recipe),
        );
      },
    );
  }

  Widget _buildEmptyState(String text) {
    return Center(
      child: Text(text, style: TextStyle(color: Colors.grey[600])),
    );
  }

  // ------------------- MENU ACTIONS -------------------
  void _handleMenuAction(String action, HybridRecommendationProvider provider) {
    switch (action) {
      case 'settings':
        _showSettingsDialog(provider);
        break;
      case 'analytics':
        _showAnalyticsDialog(provider);
        break;
      case 'shopping_list':
        _showShoppingListDialog(provider);
        break;
    }
  }

  void _showSettingsDialog(HybridRecommendationProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('การตั้งค่าระบบแนะนำ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('จำนวนสูตรจาก API'),
              subtitle: Slider(
                value: provider.maxExternalRecipes.toDouble(),
                min: 1,
                max: 15,
                divisions: 14,
                label: '${provider.maxExternalRecipes}',
                onChanged: (value) {
                  provider.setExternalRecipeSettings(
                    maxExternal: value.round(),
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  void _showAnalyticsDialog(HybridRecommendationProvider provider) {
    final stats = provider.getSummaryStats();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('รายงานการใช้งาน'),
        content: Text(stats.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }

  void _showShoppingListDialog(HybridRecommendationProvider provider) {
    final shoppingList = provider.getSmartShoppingList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('รายการซื้อของอัตโนมัติ'),
        content: Text(shoppingList.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
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

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
