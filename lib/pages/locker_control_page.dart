// locker_control_page.dart
// ไฟล์นี้เป็นหน้าควบคุมตู้ล็อกเกอร์ที่เรียกใช้หลังจากล็อกอินแล้ว

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
 import 'locker_selection_page.dart'; // import หน้าเลือกตู้

class LockerControlPage extends StatefulWidget {
  final String userId; // รับ userId จากหน้าล็อกอิน
  final String lockerCode; // รับรหัสตู้จากหน้าล็อกอินหรือจาก Database
  
  const LockerControlPage({
    Key? key,
    required this.userId,
    required this.lockerCode,
  }) : super(key: key);

  @override
  State<LockerControlPage> createState() => _LockerControlPageState();
}

class _LockerControlPageState extends State<LockerControlPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  bool isLocked = true;
  DateTime? bookingStartTime; // เวลาที่จองตู้ (ไม่ใช่เวลาที่ปลดล็อก)
  Duration? elapsedTime;
  List<Map<String, dynamic>> bookingHistory = [];
  bool isLoading = true;
  String? errorMessage;
  
  @override
  void initState() {
    super.initState();
    // ตรวจสอบว่ามี lockerCode หรือไม่
    if (widget.lockerCode.isEmpty) {
      setState(() {
        errorMessage = 'ไม่พบรหัสตู้ กรุณาเข้าสู่ระบบอีกครั้ง';
        isLoading = false;
      });
      return;
    }
    _initializeFirebase();
    _startTimeTracking();
  }

  void _initializeFirebase() async {
    try {
      // ตรวจสอบว่าตู้มีอยู่ใน Database หรือไม่
      final lockerSnapshot = await _database.child('lockers/${widget.lockerCode}').get();
      
      if (!lockerSnapshot.exists) {
        // ถ้าไม่มีข้อมูล ให้สร้างข้อมูลเริ่มต้น
        final now = DateTime.now().toUtc().add(const Duration(hours: 7));
        await _database.child('lockers/${widget.lockerCode}').set({
          'isLocked': true,
          'bookingStartTime': now.toIso8601String(), // บันทึกเวลาที่จองตู้
          'currentUserId': widget.userId,
        });
      } else {
        // ถ้ามีข้อมูลแล้ว แต่ไม่มี bookingStartTime ให้สร้างใหม่
        final data = lockerSnapshot.value as Map<dynamic, dynamic>;
        if (data['bookingStartTime'] == null) {
          final now = DateTime.now().toUtc().add(const Duration(hours: 7));
          await _database.child('lockers/${widget.lockerCode}/bookingStartTime').set(now.toIso8601String());
        }
      }

      // ฟังการเปลี่ยนแปลงสถานะล็อก
      _database.child('lockers/${widget.lockerCode}/isLocked').onValue.listen((event) {
        if (mounted) {
          setState(() {
            isLocked = event.snapshot.value as bool? ?? true;
            isLoading = false;
          });
        }
      }, onError: (error) {
        if (mounted) {
          setState(() {
            errorMessage = 'เกิดข้อผิดพลาด: $error';
            isLoading = false;
          });
        }
      });

      // ฟังเวลาเริ่มจอง (เวลาที่จองตู้ครั้งแรก)
      _database.child('lockers/${widget.lockerCode}/bookingStartTime').onValue.listen((event) {
        if (mounted) {
          setState(() {
            if (event.snapshot.value != null) {
              try {
                bookingStartTime = DateTime.parse(event.snapshot.value as String);
              } catch (e) {
                bookingStartTime = null;
              }
            } else {
              bookingStartTime = null;
            }
          });
        }
      });

      // โหลดประวัติการจอง
      await _loadBookingHistory();
      
      // ตั้งให้หยุด loading หลังจาก 3 วินาที (timeout)
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && isLoading) {
          setState(() {
            isLoading = false;
          });
        }
      });
      
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'ไม่สามารถเชื่อมต่อ Firebase: $e';
          isLoading = false;
        });
      }
    }
  }

  void _startTimeTracking() {
    // อัพเดทเวลาทุก 1 วินาที - นับจากเวลาที่จองตู้ (ไม่ใช่เวลาที่ปลดล็อก)
    Stream.periodic(const Duration(seconds: 1)).listen((_) {
      if (mounted && bookingStartTime != null) {
        setState(() {
          elapsedTime = DateTime.now().difference(bookingStartTime!);
        });
      } else if (mounted) {
        setState(() {
          elapsedTime = null;
        });
      }
    });
  }

  Future<void> _loadBookingHistory() async {
    try {
      final snapshot = await _database.child('lockers/${widget.lockerCode}/history').get();
      if (snapshot.exists && mounted) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        final allHistory = data.entries.map((e) {
          final value = e.value as Map<dynamic, dynamic>;
          return {
            'action': value['action'],
            'timestamp': value['timestamp'],
            'duration': value['duration'],
            'userId': value['userId'] ?? '',
          };
        }).toList();
        
        // เรียงจากใหม่ไปเก่า
        allHistory.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
        
        setState(() {
          // เอาเฉพาะ 3 รายการล่าสุด
          bookingHistory = allHistory.take(3).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
    }
  }

  Future<void> _toggleLock() async {
    try {
      final newLockState = !isLocked;
      final now = DateTime.now();
      final bangkokTime = now.toUtc().add(const Duration(hours: 7));

      // อัพเดทสถานะล็อก
      await _database.child('lockers/${widget.lockerCode}/isLocked').set(newLockState);

      // บันทึกประวัติการล็อก/ปลดล็อก
      await _saveHistory(newLockState ? 'lock' : 'unlock', bangkokTime, null);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newLockState ? 'ล็อกตู้สำเร็จ' : 'ปลดล็อกตู้สำเร็จ'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: newLockState ? const Color(0xFF48BB78) : const Color(0xFFED8936),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }

      await _loadBookingHistory();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _returnLocker() async {
    // แสดง Dialog ยืนยันการคืนตู้
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFED7D7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFE53E3E),
              ),
            ),
            const SizedBox(width: 12),
            const Text('ยืนยันการคืนตู้'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'คุณต้องการคืนตู้ ${widget.lockerCode} ใช่หรือไม่?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFED7D7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.warning, color: Color(0xFFE53E3E), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'การคืนตู้จะลบข้อมูลและไม่สามารถกู้คืนได้',
                      style: TextStyle(
                        color: Color(0xFFE53E3E),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53E3E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('ยืนยันคืนตู้'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // แสดง Loading
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final now = DateTime.now().toUtc().add(const Duration(hours: 7));

        // คำนวณระยะเวลาที่ใช้ตู้
        Duration? totalDuration;
        if (bookingStartTime != null) {
          totalDuration = now.difference(bookingStartTime!);
        }

        // บันทึกประวัติการคืนตู้
        final historyRef = _database.child('lockers/${widget.lockerCode}/history').push();
        await historyRef.set({
          'action': 'returned',
          'timestamp': now.toIso8601String(),
          'duration': totalDuration?.inSeconds,
          'userId': widget.userId,
        });

        // ลบข้อมูลผู้ใช้ออกจากตู้
        await _database.child('lockers/${widget.lockerCode}').update({
          'currentUserId': null,
          'isLocked': true,
          'bookingStartTime': null,
        });

        // ลบรหัสตู้ออกจากผู้ใช้
        await _database.child('users/${widget.userId}/lockerCode').remove();

        if (mounted) {
          Navigator.pop(context); // ปิด loading dialog
          
          // แสดงข้อความสำเร็จ
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('คืนตู้ ${widget.lockerCode} สำเร็จ'),
              backgroundColor: const Color(0xFF48BB78),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );

          // รอครู่แล้วกลับไปหน้าเลือกตู้
          await Future.delayed(const Duration(milliseconds: 500));
          
          // กลับไปหน้าเลือกตู้
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => LockerSelectionPage(
                userId: widget.userId,
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // ปิด loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('เกิดข้อผิดพลาด: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _backToSelection() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => LockerSelectionPage(
          userId: widget.userId,
        ),
      ),
    );
  }

  Future<void> _saveHistory(String action, DateTime timestamp, Duration? duration) async {
    final historyRef = _database.child('lockers/${widget.lockerCode}/history').push();
    await historyRef.set({
      'action': action,
      'timestamp': timestamp.toIso8601String(),
      'duration': duration?.inSeconds,
      'userId': widget.userId,
    });
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      final formatter = DateFormat('dd/MM/yyyy HH:mm:ss');
      return formatter.format(dateTime);
    } catch (e) {
      return isoString;
    }
  }

  String _getActionText(String action) {
    switch (action) {
      case 'unlock':
        return 'ปลดล็อก';
      case 'lock':
        return 'ล็อก';
      case 'booked':
        return 'จองตู้';
      case 'returned':
        return 'คืนตู้';
      default:
        return action;
    }
  }

  @override
  Widget build(BuildContext context) {
    // แสดง Error ถ้ามี
    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      errorMessage = null;
                      isLoading = true;
                    });
                    _initializeFirebase();
                  },
                  child: const Text('ลองอีกครั้ง'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _backToSelection,
                  child: const Text('กลับ'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // แสดง Loading
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'กำลังโหลดข้อมูล...',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF718096),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2D3748)),
          onPressed: _backToSelection, // กลับไปหน้าเลือกตู้
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF2D3748)),
            onPressed: _loadBookingHistory,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ตู้ล็อกเกอร์ของฉัน',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'จัดการและควบคุมตู้ของคุณ',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF718096),
                  ),
                ),
                const SizedBox(height: 40),
                
                // Locker Info Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667EEA).withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'รหัสตู้',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.lockerCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Status Card with Timer
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isLocked
                                  ? const Color(0xFFEDF2F7)
                                  : const Color(0xFFFED7D7),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                              color: isLocked
                                  ? const Color(0xFF4A5568)
                                  : const Color(0xFFE53E3E),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'สถานะตู้',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF718096),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isLocked ? 'ล็อก' : 'ปลดล็อก',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: isLocked
                                        ? const Color(0xFF2D3748)
                                        : const Color(0xFFE53E3E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: isLocked
                                  ? const Color(0xFF48BB78)
                                  : const Color(0xFFED8936),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: (isLocked
                                          ? const Color(0xFF48BB78)
                                          : const Color(0xFFED8936))
                                      .withOpacity(0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // แสดงเวลาที่ใช้ตู้ตลอดเวลา
                      if (elapsedTime != null) ...[
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 20),
                        Column(
                          children: [
                            const Text(
                              'เวลาที่ใช้ตู้',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF718096),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatDuration(elapsedTime!),
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2D3748),
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Control Button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _toggleLock,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isLocked
                          ? const Color(0xFFED8936)
                          : const Color(0xFF48BB78),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isLocked ? 'ปลดล็อกตู้' : 'ล็อกตู้',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Return Locker Button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: OutlinedButton(
                    onPressed: _returnLocker,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE53E3E),
                      side: const BorderSide(color: Color(0xFFE53E3E), width: 2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.logout_rounded, size: 24),
                        SizedBox(width: 12),
                        Text(
                          'คืนตู้ล็อกเกอร์',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Booking History
                const Text(
                  'ประวัติการใช้งาน',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 20),
                
                if (bookingHistory.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'ยังไม่มีประวัติการใช้งาน',
                        style: TextStyle(
                          color: Color(0xFF718096),
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: bookingHistory.length,
                    itemBuilder: (context, index) {
                      final history = bookingHistory[index];
                      final action = history['action'] as String;
                      
                      IconData icon;
                      Color iconColor;
                      Color bgColor;
                      
                      switch (action) {
                        case 'unlock':
                          icon = Icons.lock_open_rounded;
                          iconColor = const Color(0xFFE53E3E);
                          bgColor = const Color(0xFFFED7D7);
                          break;
                        case 'lock':
                          icon = Icons.lock_rounded;
                          iconColor = const Color(0xFF4A5568);
                          bgColor = const Color(0xFFEDF2F7);
                          break;
                        case 'booked':
                          icon = Icons.check_circle;
                          iconColor = const Color(0xFF48BB78);
                          bgColor = const Color(0xFFD4EDDA);
                          break;
                        case 'returned':
                          icon = Icons.logout_rounded;
                          iconColor = const Color(0xFFED8936);
                          bgColor = const Color(0xFFFFE5D0);
                          break;
                        default:
                          icon = Icons.info;
                          iconColor = const Color(0xFF4A5568);
                          bgColor = const Color(0xFFEDF2F7);
                      }
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(icon, color: iconColor, size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getActionText(action),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2D3748),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDateTime(history['timestamp']),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF718096),
                                    ),
                                  ),
                                  if (action == 'returned' && history['duration'] != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'ระยะเวลาที่ใช้: ${_formatDuration(Duration(seconds: history['duration']))}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF4A5568),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}