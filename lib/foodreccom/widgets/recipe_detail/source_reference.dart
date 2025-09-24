//lib/foodreccom/widgets/recipe_detail/source_reference.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/recipe/recipe.dart';

class RecipeSourceReference extends StatelessWidget {
  final RecipeModel recipe;
  const RecipeSourceReference({super.key, required this.recipe});

  @override
  Widget build(BuildContext context) {
    if (recipe.source == null && recipe.sourceUrl == null) {
      return const SizedBox();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (recipe.source != null) Text('📖 ${recipe.source}'),
        if (recipe.sourceUrl != null)
          InkWell(
            onTap: () async {
              final uri = Uri.parse(recipe.sourceUrl!);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Text(
              'ดูสูตรต้นฉบับ',
              style: TextStyle(
                color: Colors.blue[600],
                decoration: TextDecoration.underline,
              ),
            ),
          ),
      ],
    );
  }
}
