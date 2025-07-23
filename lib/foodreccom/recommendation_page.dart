// lib/pages/recommendation_page.dart
import 'package:flutter/material.dart';
import 'package:my_app/foodreccom/models/recipe_model.dart';
import 'package:my_app/foodreccom/providers/recommendation_provider.dart';
import 'package:my_app/foodreccom/widgets/enhanced_recipe_detail_sheet.dart';
import 'package:my_app/foodreccom/widgets/recipe_card.dart';
import 'package:provider/provider.dart';

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
      context.read<RecommendationProvider>().refresh();
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
        title: const Text(
          '🍳 แนะนำเมนูอาหาร',
          style: TextStyle(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: () {
              context.read<RecommendationProvider>().refresh();
            },
          ),
        ],
      ),
      body: Consumer<RecommendationProvider>(
        builder: (context, provider, child) {
          return RefreshIndicator(
            onRefresh: provider.refresh,
            color: Colors.yellow[600],
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // สถานะวัตถุดิบ
                  _buildIngredientsStatus(provider),

                  const SizedBox(height: 24),

                  // คำแนะนำเมนู
                  _buildRecommendations(provider),

                  const SizedBox(height: 80), // Space for bottom
                ],
              ),
            ),
          );
        },
      ),
      // FloatingActionButton สำหรับรีเฟรช
      floatingActionButton: Consumer<RecommendationProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return Container(); // ซ่อน FAB ขณะกำลังโหลด
          }

          return FloatingActionButton(
            onPressed: () {
              provider.getRecommendations();
              _showSnackBar('🤖 กำลังขอคำแนะนำใหม่...');
            },
            backgroundColor: Colors.yellow[600],
            child: const Icon(Icons.psychology, color: Colors.black),
          );
        },
      ),
    );
  }

  Widget _buildIngredientsStatus(RecommendationProvider provider) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.yellow[50]!, Colors.orange[50]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.inventory_2,
                    color: Colors.orange[700],
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'สถานะวัตถุดิบ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // สถิติ
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

            // วัตถุดิบใกล้หมดอายุ
            if (provider.nearExpiryIngredients.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning, color: Colors.red[600], size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'วัตถุดิบที่ต้องใช้ด่วน:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: provider.nearExpiryIngredients.take(5).map((
                        ingredient,
                      ) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${ingredient.name} (${ingredient.daysToExpiry} วัน)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red[700],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusItem(
    String label,
    String count,
    Color color,
    IconData icon,
  ) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: color.withOpacity(0.3), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(height: 2),
              Text(
                count,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendations(RecommendationProvider provider) {
    if (provider.isLoading) {
      return _buildLoadingState();
    }

    if (provider.error != null) {
      return _buildErrorState(provider);
    }

    if (provider.recommendations.isEmpty) {
      return _buildEmptyState(provider);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.restaurant_menu,
                color: Colors.green[700],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'เมนูแนะนำสำหรับคุณ',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // แสดงคำแนะนำจาก AI
        if (provider.recommendations.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.psychology, color: Colors.blue[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '🤖 AI แนะนำ ${provider.recommendations.length} เมนู ตามวัตถุดิบที่คุณมี',
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // รายการเมนู
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: provider.recommendations.length,
          itemBuilder: (context, index) {
            return RecipeCard(
              recipe: provider.recommendations[index],
              onTap: () => _showRecipeDetail(provider.recommendations[index]),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.yellow[50],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.yellow[100],
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.yellow[700]!,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '🤖 AI กำลังคิดเมนูให้...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.yellow[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'กรุณารอสักครู่',
                  style: TextStyle(fontSize: 14, color: Colors.yellow[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(RecommendationProvider provider) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Icon(Icons.error_outline, size: 80, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  'เกิดข้อผิดพลาด',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  provider.error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red[600], fontSize: 14),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => provider.getRecommendations(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('ลองใหม่'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(RecommendationProvider provider) {
    final hasIngredients = provider.ingredients.isNotEmpty;

    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Icon(
                  hasIngredients ? Icons.restaurant_menu : Icons.inventory_2,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  hasIngredients ? 'ยังไม่มีเมนูแนะนำ' : 'ไม่มีวัตถุดิบในระบบ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasIngredients
                      ? 'AI ไม่สามารถแนะนำเมนูได้ในขณะนี้'
                      : 'กรุณาเพิ่มวัตถุดิบก่อนเพื่อรับคำแนะนำ',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (hasIngredients) ...[
                      ElevatedButton(
                        onPressed: () => provider.getRecommendations(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellow[600],
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('ขอคำแนะนำใหม่'),
                      ),
                    ] else ...[
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellow[600],
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('เพิ่มวัตถุดิบ'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.yellow[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
