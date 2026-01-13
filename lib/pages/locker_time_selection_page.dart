// locker_time_selection_page.dart
// หน้าเลือกระยะเวลาการใช้งานตู้ล็อกเกอร์

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'locker_control_page.dart'; // import หน้าควบคุมตู้

class LockerTimeSelectionPage extends StatefulWidget {
  final String userId;
  final String lockerCode;
  final String? previousLocker;

  const LockerTimeSelectionPage({
    Key? key,
    required this.userId,
    required this.lockerCode,
    this.previousLocker,
  }) : super(key: key);

  @override
  State<LockerTimeSelectionPage> createState() => _LockerTimeSelectionPageState();
}

class _LockerTimeSelectionPageState extends State<LockerTimeSelectionPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  
  String selectedType = ''; // 'hours' หรือ 'days'
  int selectedValue = 0;
  bool isProcessing = false;

  // ตัวเลือกสำหรับจองเป็นชั่วโมง (1-24)
  final List<int> hourOptions = List.generate(24, (index) => index + 1);
  
  // ตัวเลือกสำหรับจองเป็นวัน (1-3)
  final List<int> dayOptions = [1, 2, 3];

  Future<void> _confirmBooking() async {
    if (selectedType.isEmpty || selectedValue == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาเลือกระยะเวลาการใช้งาน'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      isProcessing = true;
    });

    try {
      // ตรวจสอบว่าตู้ยังว่างอยู่หรือไม่
      final lockerSnapshot = await _database
          .child('lockers/${widget.lockerCode}/currentUserId')
          .get();

      if (lockerSnapshot.exists && lockerSnapshot.value != null) {
        // ตู้ถูกจองไปแล้ว
        if (mounted) {
          setState(() {
            isProcessing = false;
          });
          _showErrorDialog('ตู้นี้ถูกจองไปแล้ว กรุณาเลือกตู้อื่น');
          return;
        }
      }

      // คำนวณเวลาสิ้นสุด
      final now = DateTime.now();
      DateTime endTime;
      
      if (selectedType == 'hours') {
        endTime = now.add(Duration(hours: selectedValue));
      } else {
        endTime = now.add(Duration(days: selectedValue));
      }

      // ถ้าผู้ใช้จองตู้อื่นอยู่แล้ว ให้ยกเลิกตู้เก่า
      if (widget.previousLocker != null && widget.previousLocker != widget.lockerCode) {
        await _database.child('lockers/${widget.previousLocker}').update({
          'currentUserId': null,
          'isLocked': false, // ปลดล็อกตู้เก่า
          'bookingStartTime': null,
          'bookingEndTime': null,
          'bookingDuration': null,
        });
        
        // ส่งคำสั่งรีเลย์ปลดล็อกตู้เก่า
        await _database.child('lockers/${widget.previousLocker}/relay').update({
          'command': 'unlock_vacant',
          'timestamp': now.toIso8601String(),
          'userId': null,
          'status': 'pending',
        });
      }

      // จองตู้ใหม่ - ตั้งเป็นปลดล็อก (isLocked: false)
      await _database.child('lockers/${widget.lockerCode}').update({
        'currentUserId': widget.userId,
        'isLocked': false, // ⭐ สำคัญ: ปลดล็อกไว้ให้ user ล็อกเอง
        'bookingStartTime': now.toIso8601String(),
        'bookingEndTime': endTime.toIso8601String(),
        'bookingDuration': {
          'type': selectedType,
          'value': selectedValue,
        },
      });

      // ส่งคำสั่งรีเลย์ปลดล็อกตู้ (เปิดตู้ให้ user)
      await _database.child('lockers/${widget.lockerCode}/relay').update({
        'command': 'open', // ⭐ สำคัญ: เปิดตู้ไว้
        'timestamp': now.toIso8601String(),
        'userId': widget.userId,
        'status': 'pending',
      });

      // บันทึกข้อมูลผู้ใช้
      await _database.child('users/${widget.userId}').update({
        'lockerCode': widget.lockerCode,
        'bookedAt': now.toIso8601String(),
        'bookingEndTime': endTime.toIso8601String(),
        'bookingDuration': '$selectedValue ${selectedType == "hours" ? "ชั่วโมง" : "วัน"}',
      });

      // บันทึกประวัติการจอง
      final historyRef = _database.child('lockers/${widget.lockerCode}/history').push();
      await historyRef.set({
        'action': 'booked',
        'timestamp': DateTime.now().toUtc().add(const Duration(hours: 7)).toIso8601String(),
        'userId': widget.userId,
        'duration': '$selectedValue ${selectedType == "hours" ? "ชั่วโมง" : "วัน"}',
      });

      if (mounted) {
        setState(() {
          isProcessing = false;
        });

        // แสดงข้อความสำเร็จ
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'จองตู้ ${widget.lockerCode} สำเร็จ\nระยะเวลา: $selectedValue ${selectedType == "hours" ? "ชั่วโมง" : "วัน"}\nตู้เปิดไว้ให้แล้ว กรุณาเข้าไปล็อกเอง',
            ),
            backgroundColor: const Color(0xFF48BB78),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        // ไปหน้าควบคุมตู้
        await Future.delayed(const Duration(milliseconds: 500));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => LockerControlPage(
              userId: widget.userId,
              lockerCode: widget.lockerCode,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isProcessing = false;
        });
        _showErrorDialog('เกิดข้อผิดพลาด: $e');
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('แจ้งเตือน'),
        content: Text(message),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // ปิด dialog
              Navigator.pop(context); // กลับไปหน้าเลือกตู้
            },
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'เลือกระยะเวลาการใช้งาน',
          style: TextStyle(
            color: Color(0xFF2D3748),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2D3748)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: isProcessing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'กำลังดำเนินการจองตู้...',
                    style: TextStyle(
                      color: Color(0xFF718096),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Card
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
                          Icons.schedule_rounded,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'กำหนดเวลาการใช้งาน',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ตู้: ${widget.lockerCode}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // เลือกประเภทการจอง
                  const Text(
                    'เลือกประเภทการจอง',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3748),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: _buildTypeCard(
                          icon: Icons.access_time_rounded,
                          title: 'จองเป็นชั่วโมง',
                          subtitle: 'สูงสุด 24 ชั่วโมง',
                          type: 'hours',
                          color: const Color(0xFF48BB78),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildTypeCard(
                          icon: Icons.calendar_today_rounded,
                          title: 'จองเป็นวัน',
                          subtitle: 'สูงสุด 3 วัน',
                          type: 'days',
                          color: const Color(0xFF4299E1),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // แสดงตัวเลือกตามประเภทที่เลือก
                  if (selectedType.isNotEmpty) ...[
                    const Text(
                      'เลือกระยะเวลา',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D3748),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildDurationOptions(),
                    const SizedBox(height: 32),
                  ],

                  // แสดงสรุป
                  if (selectedValue > 0) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF667EEA).withOpacity(0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF667EEA).withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF667EEA).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.summarize_rounded,
                                  color: Color(0xFF667EEA),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'สรุปการจอง',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2D3748),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildSummaryRow(
                            icon: Icons.inventory_2_rounded,
                            label: 'รหัสตู้',
                            value: widget.lockerCode,
                          ),
                          const Divider(height: 24),
                          _buildSummaryRow(
                            icon: selectedType == 'hours'
                                ? Icons.access_time_rounded
                                : Icons.calendar_today_rounded,
                            label: 'ระยะเวลา',
                            value: '$selectedValue ${selectedType == "hours" ? "ชั่วโมง" : "วัน"}',
                          ),
                          const Divider(height: 24),
                          _buildSummaryRow(
                            icon: Icons.event_available_rounded,
                            label: 'สิ้นสุดเมื่อ',
                            value: _getEndTimeText(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],

                  // Info Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF5F5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFFED7D7),
                      ),
                    ),
                    child: Row(
                      children: const [
                        Icon(
                          Icons.info_outline,
                          color: Color(0xFFE53E3E),
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'หลังจองตู้สำเร็จ:\n• ตู้จะเปิดไว้ให้อัตโนมัติ\n• กรุณาเข้าไปล็อกตู้เอง\n• จองได้เพียง 1 ตู้เท่านั้น',
                            style: TextStyle(
                              color: Color(0xFFE53E3E),
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ปุ่มยืนยัน
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: selectedValue > 0 ? _confirmBooking : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF48BB78),
                        disabledBackgroundColor: const Color(0xFFCBD5E0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: selectedValue > 0 ? 4 : 0,
                        shadowColor: const Color(0xFF48BB78).withOpacity(0.3),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.check_circle_rounded, size: 24),
                          SizedBox(width: 12),
                          Text(
                            'ยืนยันการจอง',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTypeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String type,
    required Color color,
  }) {
    final isSelected = selectedType == type;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (selectedType == type) {
            // ถ้าคลิกที่ตัวเดิม ให้ยกเลิก
            selectedType = '';
            selectedValue = 0;
          } else {
            // เลือกใหม่
            selectedType = type;
            selectedValue = 0;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? color : color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 32,
                color: isSelected ? Colors.white : color,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isSelected ? color : const Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF718096),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationOptions() {
    final options = selectedType == 'hours' ? hourOptions : dayOptions;
    final unit = selectedType == 'hours' ? 'ชั่วโมง' : 'วัน';

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: options.length,
      itemBuilder: (context, index) {
        final value = options[index];
        final isSelected = selectedValue == value;

        return GestureDetector(
          onTap: () {
            setState(() {
              selectedValue = value;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF667EEA)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF667EEA)
                    : const Color(0xFFE2E8F0),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: const Color(0xFF667EEA).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : const Color(0xFF2D3748),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white70 : const Color(0xFF718096),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF718096), size: 20),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF718096),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2D3748),
          ),
        ),
      ],
    );
  }

  String _getEndTimeText() {
    final now = DateTime.now();
    DateTime endTime;

    if (selectedType == 'hours') {
      endTime = now.add(Duration(hours: selectedValue));
    } else {
      endTime = now.add(Duration(days: selectedValue));
    }

    return '${endTime.day}/${endTime.month}/${endTime.year} ${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')} น.';
  }
}