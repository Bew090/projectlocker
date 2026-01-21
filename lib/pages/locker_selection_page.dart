// locker_selection_page.dart
// หน้าเลือกจองตู้ล็อกเกอร์

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'locker_time_selection_page.dart';
import 'locker_control_page.dart';

class LockerSelectionPage extends StatefulWidget {
  final String userId;
  
  const LockerSelectionPage({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  State<LockerSelectionPage> createState() => _LockerSelectionPageState();
}

class _LockerSelectionPageState extends State<LockerSelectionPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final List<String> lockerCodes = ['A-247', 'A-248', 'B-101', 'B-102', 'C-305', 'C-306'];
  Map<String, bool> lockerStatus = {};
  Map<String, String?> lockerUsers = {};
  bool isLoading = true;
  String? userCurrentLocker;

  @override
  void initState() {
    super.initState();
    _loadLockerStatus();
    _checkUserCurrentLocker();
  }

  Future<void> _checkUserCurrentLocker() async {
    try {
      final snapshot = await _database.child('users/${widget.userId}/lockerCode').get();
      if (snapshot.exists && mounted) {
        setState(() {
          userCurrentLocker = snapshot.value as String;
        });
      }
    } catch (e) {
      debugPrint('Error checking user locker: $e');
    }
  }

  void _loadLockerStatus() {
    for (String lockerCode in lockerCodes) {
      _database.child('lockers/$lockerCode').onValue.listen((event) {
        if (event.snapshot.exists && mounted) {
          final data = event.snapshot.value;
          if (data is Map) {
            setState(() {
              // ตู้ว่าง = ไม่มี currentUserId
              lockerStatus[lockerCode] = data['currentUserId'] == null;
              lockerUsers[lockerCode] = data['currentUserId'] as String?;
              isLoading = false;
            });
            
            // ลบส่วนที่บังคับปลดล็อกตู้ออก - ให้ตู้รักษาสถานะเดิมไว้
            // *** ไม่แก้ไขค่า isLocked ของตู้ที่มีผู้ใช้อยู่ ***
          }
        } else if (mounted) {
          setState(() {
            lockerStatus[lockerCode] = true;
            lockerUsers[lockerCode] = null;
            isLoading = false;
          });
        }
      });
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('แจ้งเตือน'),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ตรวจสอบ'),
          ),
        ],
      ),
    );
  }

  Future<void> _goToCurrentLocker() async {
    if (userCurrentLocker != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => LockerControlPage(
            userId: widget.userId,
            lockerCode: userCurrentLocker!,
          ),
        ),
      );
    }
  }

  Color _getStatusColor(String lockerCode) {
    if (userCurrentLocker == lockerCode) {
      return const Color(0xFF667EEA);
    }
    return lockerStatus[lockerCode] == true 
        ? const Color(0xFF48BB78)
        : const Color(0xFFE53E3E);
  }

  String _getStatusText(String lockerCode) {
    if (userCurrentLocker == lockerCode) {
      return 'ตู้ของฉัน';
    }
    return lockerStatus[lockerCode] == true ? 'ว่าง' : 'ไม่ว่าง';
  }

  IconData _getStatusIcon(String lockerCode) {
    if (userCurrentLocker == lockerCode) {
      return Icons.check_circle;
    }
    return lockerStatus[lockerCode] == true 
        ? Icons.lock_open_rounded 
        : Icons.lock_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'เลือกตู้ล็อกเกอร์',
          style: TextStyle(
            color: Color(0xFF2D3748),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          if (userCurrentLocker != null)
            IconButton(
              icon: const Icon(Icons.dashboard, color: Color(0xFF2D3748)),
              tooltip: 'ไปยังตู้ของฉัน',
              onPressed: _goToCurrentLocker,
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF667EEA).withOpacity(0.3),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.inventory_2_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'เลือกตู้ล็อกเกอร์ของคุณ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          userCurrentLocker != null
                              ? 'ตู้ปัจจุบัน: $userCurrentLocker'
                              : 'คุณยังไม่ได้จองตู้',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLegendItem(
                        Icons.lock_open_rounded,
                        'ว่าง',
                        const Color(0xFF48BB78),
                      ),
                      _buildLegendItem(
                        Icons.lock_rounded,
                        'ไม่ว่าง',
                        const Color(0xFFE53E3E),
                      ),
                      _buildLegendItem(
                        Icons.check_circle,
                        'ตู้ของฉัน',
                        const Color(0xFF667EEA),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: lockerCodes.length,
                    itemBuilder: (context, index) {
                      final lockerCode = lockerCodes[index];
                      final isAvailable = lockerStatus[lockerCode] == true;
                      final isMyLocker = userCurrentLocker == lockerCode;
                      
                      return GestureDetector(
                        onTap: () {
                          if (isMyLocker) {
                            _goToCurrentLocker();
                          } else if (isAvailable) {
                            _showBookingConfirmation(lockerCode);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('ตู้นี้ไม่ว่าง'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _getStatusColor(lockerCode).withOpacity(0.3),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _getStatusColor(lockerCode).withOpacity(0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(lockerCode).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _getStatusIcon(lockerCode),
                                  size: 48,
                                  color: _getStatusColor(lockerCode),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                lockerCode,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2D3748),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(lockerCode),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _getStatusText(lockerCode),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isMyLocker
                                    ? 'แตะเพื่อเข้าใช้'
                                    : isAvailable
                                        ? 'แตะเพื่อจอง'
                                        : 'ไม่สามารถจองได้',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: const Color(0xFF718096),
                                  fontWeight: isMyLocker ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDF2F7),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.info_outline,
                          color: Color(0xFF4A5568),
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'คุณสามารถจองได้เพียง 1 ตู้เท่านั้น\nการจองตู้ใหม่จะยกเลิกตู้เก่าอัตโนมัติ\nสถานะตู้จะถูกรักษาไว้ตามที่ผู้ใช้ตั้งค่า',
                            style: TextStyle(
                              color: Color(0xFF4A5568),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildLegendItem(IconData icon, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF718096),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  void _showBookingConfirmation(String lockerCode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF48BB78).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                color: Color(0xFF48BB78),
              ),
            ),
            const SizedBox(width: 12),
            const Text('ยืนยันการจอง'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'คุณต้องการจองตู้ $lockerCode ใช่หรือไม่?',
              style: const TextStyle(fontSize: 16),
            ),
            if (userCurrentLocker != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFED7D7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Color(0xFFE53E3E), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ตู้เดิม ($userCurrentLocker) จะถูกยกเลิก',
                        style: const TextStyle(
                          color: Color(0xFFE53E3E),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LockerTimeSelectionPage(
                    userId: widget.userId,
                    lockerCode: lockerCode,
                    previousLocker: userCurrentLocker,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF48BB78),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
  }
}