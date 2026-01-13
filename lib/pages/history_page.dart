// history_page.dart
// หน้าประวัติการใช้งานตู้ล็อกเกอร์

import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class HistoryPage extends StatefulWidget {
  final String userId;

  const HistoryPage({Key? key, required this.userId}) : super(key: key);

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  DateTime selectedDate = DateTime.now();
  List<Map<String, dynamic>> historyList = [];
  bool isLoading = true;
  bool isLocaleInitialized = false;
  Map<String, int> statsSummary = {
    'booked': 0,
    'unlock': 0,
    'lock': 0,
    'returned': 0,
  };

  @override
  void initState() {
    super.initState();
    _initializeLocale();
  }

  Future<void> _initializeLocale() async {
    try {
      await initializeDateFormatting('th_TH', null);
      setState(() {
        isLocaleInitialized = true;
      });
      _loadHistory();
    } catch (e) {
      debugPrint('Error initializing locale: $e');
      setState(() {
        isLocaleInitialized = true; // ให้ทำงานต่อแม้ locale ไม่สำเร็จ
      });
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      isLoading = true;
    });

    try {
      final snapshot = await _database.child('lockers').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        List<Map<String, dynamic>> allHistory = [];
        Map<String, int> stats = {
          'booked': 0,
          'unlock': 0,
          'lock': 0,
          'returned': 0,
        };

        // วนลูปทุกตู้
        data.forEach((lockerCode, lockerData) {
          if (lockerData is Map && lockerData['history'] != null) {
            final history = lockerData['history'] as Map<dynamic, dynamic>;
            
            history.forEach((key, value) {
              if (value is Map && value['userId'] == widget.userId) {
                try {
                  final timestamp = DateTime.parse(value['timestamp']);
                  final selectedDateOnly = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                  );
                  final historyDateOnly = DateTime(
                    timestamp.year,
                    timestamp.month,
                    timestamp.day,
                  );

                  // ตรวจสอบว่าตรงกับวันที่เลือกหรือไม่
                  if (historyDateOnly == selectedDateOnly) {
                    allHistory.add({
                      'lockerCode': lockerCode,
                      'action': value['action'],
                      'timestamp': value['timestamp'],
                      'duration': value['duration'],
                      'relayStatus': value['relayStatus'],
                    });

                    // นับสถิติ
                    final action = value['action'] as String;
                    if (stats.containsKey(action)) {
                      stats[action] = (stats[action] ?? 0) + 1;
                    }
                  }
                } catch (e) {
                  debugPrint('Error parsing history: $e');
                }
              }
            });
          }
        });

        // เรียงตาม timestamp จากใหม่ไปเก่า
        allHistory.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

        setState(() {
          historyList = allHistory;
          statsSummary = stats;
          isLoading = false;
        });
      } else {
        setState(() {
          historyList = [];
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF667EEA),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF2D3748),
            ),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
      _loadHistory();
    }
  }

  void _quickSelectDate(int daysAgo) {
    setState(() {
      selectedDate = DateTime.now().subtract(Duration(days: daysAgo));
    });
    _loadHistory();
  }

  String _formatDateTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      final formatter = DateFormat('HH:mm:ss');
      return formatter.format(dateTime);
    } catch (e) {
      return isoString;
    }
  }

  String _formatDate(DateTime date) {
    try {
      // ลองใช้ locale ไทยก่อน ถ้าไม่ได้ใช้รูปแบบปกติ
      final months = [
        'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
        'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'
      ];
      return '${date.day} ${months[date.month - 1]} ${date.year + 543}';
    } catch (e) {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
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

  Color _getActionColor(String action) {
    switch (action) {
      case 'unlock':
        return const Color(0xFFE53E3E);
      case 'lock':
        return const Color(0xFF4A5568);
      case 'booked':
        return const Color(0xFF48BB78);
      case 'returned':
        return const Color(0xFFED8936);
      default:
        return const Color(0xFF4A5568);
    }
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'unlock':
        return Icons.lock_open_rounded;
      case 'lock':
        return Icons.lock_rounded;
      case 'booked':
        return Icons.check_circle;
      case 'returned':
        return Icons.logout_rounded;
      default:
        return Icons.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isLocaleInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FA),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final isToday = DateTime.now().day == selectedDate.day &&
        DateTime.now().month == selectedDate.month &&
        DateTime.now().year == selectedDate.year;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'ประวัติการใช้งาน',
          style: TextStyle(
            color: Color(0xFF2D3748),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF2D3748)),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Card with Gradient
          Container(
            margin: const EdgeInsets.all(24),
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
                  Icons.history_rounded,
                  size: 48,
                  color: Colors.white,
                ),
                const SizedBox(height: 12),
                const Text(
                  'ประวัติการใช้งานตู้',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'รายการทั้งหมด ${historyList.length} รายการ',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // Quick Date Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: _buildQuickDateButton(
                    'วันนี้',
                    Icons.today_rounded,
                    isToday,
                    () => _quickSelectDate(0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildQuickDateButton(
                    'เมื่อวาน',
                    Icons.history_rounded,
                    !isToday && selectedDate.difference(DateTime.now()).inDays == -1,
                    () => _quickSelectDate(1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildQuickDateButton(
                    'เลือกวัน',
                    Icons.calendar_month_rounded,
                    false,
                    _selectDate,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Selected Date Display
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF667EEA).withOpacity(0.3),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF667EEA).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.calendar_today_rounded,
                      color: Color(0xFF667EEA),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatDate(selectedDate),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D3748),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Stats Summary
          if (historyList.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'จองตู้',
                      statsSummary['booked'] ?? 0,
                      Icons.check_circle,
                      const Color(0xFF48BB78),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'ปลดล็อก',
                      statsSummary['unlock'] ?? 0,
                      Icons.lock_open_rounded,
                      const Color(0xFFE53E3E),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'ล็อก',
                      statsSummary['lock'] ?? 0,
                      Icons.lock_rounded,
                      const Color(0xFF4A5568),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'คืนตู้',
                      statsSummary['returned'] ?? 0,
                      Icons.logout_rounded,
                      const Color(0xFFED8936),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // History List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : historyList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.inbox_rounded,
                                size: 80,
                                color: Colors.grey.shade400,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'ไม่มีประวัติในวันนี้',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'ลองเลือกวันอื่นดูสิ',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        itemCount: historyList.length,
                        itemBuilder: (context, index) {
                          final history = historyList[index];
                          final action = history['action'] as String;
                          final lockerCode = history['lockerCode'] as String;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _getActionColor(action).withOpacity(0.2),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _getActionColor(action).withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _getActionColor(action).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getActionIcon(action),
                                  color: _getActionColor(action),
                                  size: 24,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    _getActionText(action),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2D3748),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF667EEA).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      lockerCode,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF667EEA),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.access_time_rounded,
                                        size: 14,
                                        color: Color(0xFF718096),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDateTime(history['timestamp']),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: Color(0xFF718096),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (action == 'returned' && history['duration'] != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.timer_rounded,
                                          size: 14,
                                          color: Color(0xFF4A5568),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'ใช้งาน: ${_formatDuration(history['duration'])}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF4A5568),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickDateButton(
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onPressed,
  ) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? const Color(0xFF667EEA) : Colors.white,
        foregroundColor: isSelected ? Colors.white : const Color(0xFF667EEA),
        elevation: isSelected ? 4 : 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? const Color(0xFF667EEA) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF718096),
            ),
          ),
        ],
      ),
    );
  }
}