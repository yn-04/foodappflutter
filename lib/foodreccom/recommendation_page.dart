import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:my_app/foodreccom/models/recipe/recipe.dart';
import 'package:my_app/foodreccom/providers/enhanced_recommendation_provider.dart';
import 'package:my_app/foodreccom/widgets/recipe_card.dart';
import 'package:my_app/foodreccom/widgets/recipe_detail/enhanced_recipe_detail_sheet.dart';
import 'package:my_app/foodreccom/extensions/ui_extensions.dart';
import 'package:my_app/foodreccom/widgets/status_card.dart';

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
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: () {
              context
                  .read<EnhancedRecommendationProvider>()
                  .getHybridRecommendations();
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
          return FloatingActionButton(
            onPressed: () {
              provider.getHybridRecommendations();
              context.showSnack(
                '🤖 กำลังขอคำแนะนำใหม่ (Hybrid)...',
                color: Colors.yellow[700]!,
              );
            },
            backgroundColor: Colors.yellow[600],
            child: const Icon(Icons.psychology, color: Colors.black),
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
        title: '🤖 AI + API กำลังคิดเมนูให้...',
        subtitle: 'กรุณารอสักครู่',
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
}
