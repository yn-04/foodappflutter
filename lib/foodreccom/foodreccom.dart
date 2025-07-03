// Food Recommendation Tab
import 'package:flutter/material.dart';

class FoodRecommendationTab extends StatelessWidget {
  const FoodRecommendationTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Food Recommendation')),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fastfood, size: 80, color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'Food Recommendation',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'แนะนำเมนูอาหารที่เหมาะสม',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
