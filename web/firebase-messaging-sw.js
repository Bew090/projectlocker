// firebase-messaging-sw.js
// Service Worker สำหรับจัดการ Push Notification

importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

// ⚠️ แทนที่ด้วย Firebase Config ของคุณ
const firebaseConfig = {
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_PROJECT_ID.firebaseapp.com",
  databaseURL: "https://YOUR_PROJECT_ID.firebaseio.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT_ID.appspot.com",
  messagingSenderId: "YOUR_SENDER_ID",
  appId: "YOUR_APP_ID"
};

// Initialize Firebase
firebase.initializeApp(firebaseConfig);

const messaging = firebase.messaging();

// จัดการการแจ้งเตือนเมื่อเว็บปิดอยู่หรืออยู่เบื้องหลัง
messaging.onBackgroundMessage((payload) => {
  console.log('[SW] Received background message: ', payload);
  
  const notificationTitle = payload.notification?.title || 'แจ้งเตือนจากตู้ล็อกเกอร์';
  const notificationOptions = {
    body: payload.notification?.body || 'คุณมีการแจ้งเตือนใหม่',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    vibrate: [200, 100, 200, 100, 200],
    tag: 'locker-notification',
    requireInteraction: true, // ให้การแจ้งเตือนอยู่จนกว่าจะกด
    data: {
      url: '/',
      timestamp: Date.now(),
      ...payload.data
    },
  };

  // แสดงการแจ้งเตือน
  return self.registration.showNotification(notificationTitle, notificationOptions);
});

// จัดการเมื่อกดที่การแจ้งเตือน
self.addEventListener('notificationclick', (event) => {
  console.log('[SW] Notification clicked: ', event);
  
  event.notification.close();
  
  // เปิดหน้าต่างแอพ
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((clientList) => {
        // ถ้ามีหน้าต่างเปิดอยู่แล้ว ให้ focus
        for (let client of clientList) {
          if (client.url === '/' && 'focus' in client) {
            return client.focus();
          }
        }
        // ถ้าไม่มี ให้เปิดหน้าต่างใหม่
        if (clients.openWindow) {
          return clients.openWindow('/');
        }
      })
  );
});

// จัดการเมื่อปิดการแจ้งเตือน
self.addEventListener('notificationclose', (event) => {
  console.log('[SW] Notification closed: ', event);
});

console.log('[SW] Service Worker loaded successfully');