// notification_service.dart
// ระบบแจ้งเตือนสำหรับ Flutter Web

import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  
  String? _currentUserId;
  String? _fcmToken;
  StreamSubscription? _bookingEndTimeListener;
  Timer? _notificationTimer;
  bool _hasShown5MinWarning = false;
  bool _hasShown1MinWarning = false;
  bool _hasShownExpiredWarning = false;

  // เริ่มต้นระบบแจ้งเตือน
  Future<void> initialize(String userId) async {
    _currentUserId = userId;
    
    try {
      // ขอสิทธิ์แจ้งเตือน
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ [WEB] User granted notification permission');
        
        // รับ FCM Token (ใส่ VAPID Key ของคุณตรงนี้)
        _fcmToken = await _firebaseMessaging.getToken(
          vapidKey: 'BMPCCG7MlQDCzQ-Mp_x0-5ArqeEdz83evLK6jDR2YD9B58yDda_vLTND68_JfH9iSJCSxbqZ-cCpnIaSC00XQNQ', // ⚠️ เปลี่ยนตรงนี้
        );
        
        if (_fcmToken != null) {
          print('📱 [WEB] FCM Token: $_fcmToken');
          
          // บันทึก FCM Token ลง Firebase
          await _database.child('users/$userId/fcmToken').set(_fcmToken);
          await _database.child('users/$userId/platform').set('web');
          await _database.child('users/$userId/lastActive').set(DateTime.now().toIso8601String());
        }
        
        // ฟังการแจ้งเตือนขณะใช้งานเว็บ
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          print('📬 [WEB] Foreground message: ${message.notification?.title}');
          // Browser จะแสดงการแจ้งเตือนอัตโนมัติ
        });
        
        // ฟังการแจ้งเตือนเมื่อกดที่การแจ้งเตือน
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          print('👆 [WEB] Notification clicked: ${message.notification?.title}');
          // สามารถนำทางไปหน้าที่ต้องการได้
        });
        
        // เริ่มตรวจสอบเวลา
        _startMonitoring(userId);
        
      } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
        print('❌ [WEB] User denied notification permission');
        _showPermissionDeniedMessage();
      } else {
        print('⚠️ [WEB] Notification permission: ${settings.authorizationStatus}');
      }
      
    } catch (e) {
      print('❌ [WEB] Error initializing notifications: $e');
    }
  }

  // เริ่มตรวจสอบเวลาหมดอายุ
  void _startMonitoring(String userId) {
    print('👀 [WEB] Start monitoring for user: $userId');
    
    // ฟังการเปลี่ยนแปลง bookingEndTime
    _bookingEndTimeListener = _database
        .child('users/$userId/bookingEndTime')
        .onValue
        .listen((event) {
      if (event.snapshot.value != null) {
        try {
          final endTime = DateTime.parse(event.snapshot.value as String);
          print('⏰ [WEB] Booking end time: $endTime');
          
          // รีเซ็ต flag เมื่อมีการจองใหม่
          _hasShown5MinWarning = false;
          _hasShown1MinWarning = false;
          _hasShownExpiredWarning = false;
          
          _scheduleNotifications(endTime);
        } catch (e) {
          print('❌ [WEB] Error parsing bookingEndTime: $e');
        }
      } else {
        print('🔕 [WEB] No active booking, stopping monitoring');
        _notificationTimer?.cancel();
        
        // รีเซ็ต flag
        _hasShown5MinWarning = false;
        _hasShown1MinWarning = false;
        _hasShownExpiredWarning = false;
      }
    });
  }

  // กำหนดการแจ้งเตือน
  void _scheduleNotifications(DateTime endTime) {
    _notificationTimer?.cancel();
    
    print('📅 [WEB] Scheduled notifications until: $endTime');
    
    // ตรวจสอบทุก 15 วินาที (เพื่อความแม่นยำ)
    _notificationTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      final now = DateTime.now();
      final remaining = endTime.difference(now);

      print('⏱️ [WEB] Time remaining: ${remaining.inMinutes}:${remaining.inSeconds % 60}');

      if (remaining.isNegative) {
        // หมดเวลาแล้ว
        if (!_hasShownExpiredWarning) {
          _hasShownExpiredWarning = true;
          _sendNotificationToFirebase(
            '⏰ หมดเวลาการใช้งานตู้ล็อกเกอร์',
            'กรุณาคืนตู้ภายใน 5 นาที มิฉะนั้นระบบจะคืนอัตโนมัติ',
            'expired',
          );
          print('🔴 [WEB] Sent expired notification');
        }
      } else if (remaining.inMinutes <= 5 && remaining.inMinutes > 1 && !_hasShown5MinWarning) {
        // เหลือ 5 นาที
        _hasShown5MinWarning = true;
        _sendNotificationToFirebase(
          '⚠️ เหลือเวลาอีก ${remaining.inMinutes} นาที',
          'กรุณาคืนตู้ล็อกเกอร์ในเร็วๆ นี้',
          'warning_5min',
        );
        print('🟡 [WEB] Sent 5-minute warning');
      } else if (remaining.inMinutes <= 1 && remaining.inSeconds > 0 && !_hasShown1MinWarning) {
        // เหลือ 1 นาที
        _hasShown1MinWarning = true;
        _sendNotificationToFirebase(
          '🚨 เหลือเวลาอีก 1 นาที!',
          'กรุณารีบคืนตู้ล็อกเกอร์ทันที',
          'warning_1min',
        );
        print('🟠 [WEB] Sent 1-minute warning');
      }
    });
  }

  // ส่งคำขอการแจ้งเตือนไปยัง Firebase (ให้ Cloud Function ส่ง)
  Future<void> _sendNotificationToFirebase(String title, String body, String type) async {
    if (_currentUserId == null || _fcmToken == null) return;

    try {
      // บันทึกคำขอส่งการแจ้งเตือนลง Firebase
      // Cloud Function หรือ Backend จะอ่านและส่ง FCM
      final notificationRef = _database.child('notifications').push();
      await notificationRef.set({
        'userId': _currentUserId,
        'token': _fcmToken,
        'title': title,
        'body': body,
        'type': type,
        'timestamp': DateTime.now().toIso8601String(),
        'sent': false,
        'platform': 'web',
      });
      
      print('✅ [WEB] Notification request saved to Firebase');
      
      // สำหรับทดสอบ: แสดง Browser Notification ทันที
      await _showBrowserNotification(title, body);
      
    } catch (e) {
      print('❌ [WEB] Error sending notification: $e');
    }
  }

  // แสดงการแจ้งเตือนผ่าน Browser (สำหรับทดสอบ)
  Future<void> _showBrowserNotification(String title, String body) async {
    try {
      // ใช้ Notification API ของ Browser
      // Note: ใน Production ควรใช้ FCM เท่านั้น
      print('🔔 [WEB] Showing browser notification: $title');
      
      // ส่งข้อมูลไปยัง Service Worker เพื่อแสดงการแจ้งเตือน
      await _database.child('webNotifications/${_currentUserId}').set({
        'title': title,
        'body': body,
        'timestamp': DateTime.now().toIso8601String(),
        'show': true,
      });
      
    } catch (e) {
      print('❌ [WEB] Error showing browser notification: $e');
    }
  }

  // แสดงข้อความเมื่อปิดสิทธิ์การแจ้งเตือน
  void _showPermissionDeniedMessage() {
    print('⚠️ [WEB] Please enable notifications in your browser settings');
  }

  // ยกเลิกการแจ้งเตือนทั้งหมด
  Future<void> cancelAllNotifications() async {
    _notificationTimer?.cancel();
    
    // ลบคำขอการแจ้งเตือนที่ยังไม่ส่ง
    if (_currentUserId != null) {
      try {
        final snapshot = await _database
            .child('notifications')
            .orderByChild('userId')
            .equalTo(_currentUserId)
            .get();
            
        if (snapshot.exists) {
          final updates = <String, dynamic>{};
          final data = snapshot.value as Map<dynamic, dynamic>;
          data.forEach((key, value) {
            updates['notifications/$key'] = null;
          });
          await _database.update(updates);
        }
        
        print('🔕 [WEB] Cancelled all notifications');
      } catch (e) {
        print('❌ [WEB] Error cancelling notifications: $e');
      }
    }
  }

  // หยุดการตรวจสอบ (เรียกตอน Logout)
  void dispose() {
    print('👋 [WEB] Disposing notification service');
    
    _notificationTimer?.cancel();
    _bookingEndTimeListener?.cancel();
    
    // ลบ FCM Token ออกจาก Firebase
    if (_currentUserId != null) {
      _database.child('users/$_currentUserId/fcmToken').remove();
      _database.child('users/$_currentUserId/platform').remove();
    }
    
    _currentUserId = null;
    _fcmToken = null;
    _hasShown5MinWarning = false;
    _hasShown1MinWarning = false;
    _hasShownExpiredWarning = false;
  }

  // อัพเดท FCM Token (กรณี Token เปลี่ยน)
  Future<void> refreshToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      
      _fcmToken = await _firebaseMessaging.getToken(
        vapidKey: 'BMPCCG7MlQDCzQ-Mp_x0-5ArqeEdz83evLK6jDR2YD9B58yDda_vLTND68_JfH9iSJCSxbqZ-cCpnIaSC00XQNQ', // ⚠️ เปลี่ยนตรงนี้
      );
      
      if (_fcmToken != null && _currentUserId != null) {
        await _database.child('users/$_currentUserId/fcmToken').set(_fcmToken);
        print('🔄 [WEB] Token refreshed: $_fcmToken');
      }
    } catch (e) {
      print('❌ [WEB] Error refreshing token: $e');
    }
  }
}