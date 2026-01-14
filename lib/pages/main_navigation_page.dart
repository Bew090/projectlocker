// main_navigation_page.dart
// หน้าหลักที่มี Bottom Navigation Bar

import 'package:flutter/material.dart';
import 'locker_selection_page.dart';
import 'history_page.dart';
import 'profile_page.dart';

class MainNavigationPage extends StatefulWidget {
  final String userId;

  const MainNavigationPage({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      LockerSelectionPage(userId: widget.userId),
      HistoryPage(userId: widget.userId),
      ProfilePage(userId: widget.userId),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // ถ้าอยู่หน้าตู้ล็อกเกอร์ (index 0) ให้ออกจากแอป
        if (_currentIndex == 0) {
          return true;
        }
        
        // ถ้าอยู่หน้าอื่น ให้กลับไปหน้าตู้ล็อกเกอร์
        setState(() {
          _currentIndex = 0;
        });
        return false;
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: _pages,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
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
            selectedItemColor: const Color(0xFF667EEA),
            unselectedItemColor: const Color(0xFF718096),
            selectedFontSize: 12,
            unselectedFontSize: 12,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            elevation: 0,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.inventory_2_rounded, size: 26),
                activeIcon: Icon(Icons.inventory_2_rounded, size: 28),
                label: 'ตู้ล็อกเกอร์',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.history_rounded, size: 26),
                activeIcon: Icon(Icons.history_rounded, size: 28),
                label: 'ประวัติ',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded, size: 26),
                activeIcon: Icon(Icons.person_rounded, size: 28),
                label: 'โปรไฟล์',
              ),
            ],
          ),
        ),
      ),
    );
  }
}