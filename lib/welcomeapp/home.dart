// home.dart
import 'package:flutter/material.dart';
import 'package:my_app/dashboard/dashboard.dart';
import 'package:my_app/foodreccom/recommendation_page.dart';
import 'package:my_app/profile/profile_tab.dart';
import 'package:my_app/rawmaterial/screens/shopping_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const DashboardTab(),
    ShoppingListScreen(),
    const RecommendationPage(),
    const ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE0E0E0), width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: Colors.transparent, // ซ่อนสีเดิม
          unselectedItemColor: Colors.transparent, // ซ่อนสีเดิม
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 0, // ซ่อน label
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w400,
            fontSize: 0, // ซ่อน label
          ),
          elevation: 0,
          items: [
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _currentIndex == 0 ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.home,
                  color: _currentIndex == 0 ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _currentIndex == 1 ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.description,
                  color: _currentIndex == 1 ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _currentIndex == 2 ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.restaurant_menu,
                  color: _currentIndex == 2 ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _currentIndex == 3 ? Colors.black : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.person,
                  color: _currentIndex == 3 ? Colors.white : Colors.grey[600],
                  size: 20,
                ),
              ),
              label: '',
            ),
          ],
        ),
      ),
    );
  }
}
