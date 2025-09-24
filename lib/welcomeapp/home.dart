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

  // สร้างครั้งเดียว เพื่อไม่ให้ state ในแต่ละแท็บหาย
  final List<Widget> _pages = [
    const DashboardTab(),
    ShoppingListScreen(),
    const RecommendationPage(),
    const ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE0E0E0), width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (i) => setState(() => _currentIndex = i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          elevation: 0,
          items: [
            _navItem(icon: Icons.home, index: 0),
            _navItem(icon: Icons.description, index: 1),
            _navItem(icon: Icons.restaurant_menu, index: 2),
            _navItem(icon: Icons.person, index: 3),
          ],
        ),
      ),
    );
  }

  BottomNavigationBarItem _navItem({
    required IconData icon,
    required int index,
  }) {
    final active = _currentIndex == index;
    return BottomNavigationBarItem(
      label: '',
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.black : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          color: active ? Colors.white : Colors.grey[600],
          size: 20,
        ),
      ),
    );
  }
}
