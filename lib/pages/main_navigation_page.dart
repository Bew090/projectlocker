// main_navigation_page.dart
// หน้าหลักที่มี Bottom Navigation Bar (รวมหน้าแอดมิน)

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'locker_selection_page.dart';
import 'history_page.dart';
import 'profile_page.dart';
import 'admin_control_page.dart';

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
  bool isAdmin = false;
  bool isCheckingAdmin = true;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    try {
      final userSnapshot = await _database.child('users/${widget.userId}').get();
      
      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        final email = userData['email'] as String?;
        
        setState(() {
          isAdmin = email == 'admin001@gmail.com';
          isCheckingAdmin = false;
        });
        
        _initializePages();
      } else {
        setState(() {
          isCheckingAdmin = false;
        });
        _initializePages();
      }
    } catch (e) {
      debugPrint('Error checking admin status: $e');
      setState(() {
        isCheckingAdmin = false;
      });
      _initializePages();
    }
  }

  void _initializePages() {
    setState(() {
      if (isAdmin) {
        _pages = [
          LockerSelectionPage(userId: widget.userId),
          HistoryPage(userId: widget.userId),
          AdminControlPage(userId: widget.userId),
          ProfilePage(userId: widget.userId),
        ];
      } else {
        _pages = [
          LockerSelectionPage(userId: widget.userId),
          HistoryPage(userId: widget.userId),
          ProfilePage(userId: widget.userId),
        ];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isCheckingAdmin) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FA),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

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
            items: isAdmin
                ? const [
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
                      icon: Icon(Icons.admin_panel_settings_rounded, size: 26),
                      activeIcon: Icon(Icons.admin_panel_settings_rounded, size: 28),
                      label: 'แอดมิน',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.person_rounded, size: 26),
                      activeIcon: Icon(Icons.person_rounded, size: 28),
                      label: 'โปรไฟล์',
                    ),
                  ]
                : const [
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