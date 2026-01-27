#include <WiFi.h>
#include <WebServer.h>
#include <WiFiManager.h>
#include <ESPmDNS.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <Adafruit_PWMServoDriver.h>

#include <Firebase_ESP_Client.h>
#include "addons/TokenHelper.h"
#include "addons/RTDBHelper.h"

// =====================================================
// RESET WIFI BUTTON
// =====================================================
#define RESET_WIFI_PIN 13   // GPIO13 -> ปุ่ม -> GND

// =====================================================
// COMMAND STRUCT
// =====================================================
struct CommandItem {
  String lockerCode;
  String command;
  String timestamp;
};

// =====================================================
// WEB / WIFI CONFIG
// =====================================================
WebServer server(80);

const char* ADMIN_PIN = "1234";

const char* AP_NAME = "ESP32-SETUP";
const char* AP_PASS = "FLOWZA@2026";
const char* MDNS_NAME = "esp32";

String sessionToken = "";

// =====================================================
// TOKEN
// =====================================================
String genToken() {
  uint32_t r1 = esp_random();
  uint32_t r2 = esp_random();

  char buf[32];
  snprintf(buf, sizeof(buf), "%08lx%08lx",
           (unsigned long)r1,
           (unsigned long)r2);

  return String(buf);
}

bool isAuthed() {

  if (!server.hasHeader("X-Auth")) return false;

  String t = server.header("X-Auth");

  return (sessionToken.length() > 0 && t == sessionToken);
}

void sendJSON(int code, const String& json) {
  server.send(code, "application/json", json);
}

void sendText(int code, const String& text) {
  server.send(code, "text/plain; charset=utf-8", text);
}

// =====================================================
// FIREBASE CONFIG
// =====================================================
#define API_KEY "AIzaSyDmSkeG8YUWCiWI8FtnmGwoXzOoYmWGNXI"
#define DATABASE_URL "https://projectlocker001-default-rtdb.asia-southeast1.firebasedatabase.app/"

FirebaseData fbWrite;
FirebaseAuth auth;
FirebaseConfig config;

// =====================================================
// SERVO CONFIG
// =====================================================
Adafruit_PWMServoDriver pca(0x40);

#define SERVO_FREQ 50
#define SERVOMIN 110
#define SERVOMAX 490

int angleToPulse(int angle) {

  angle = constrain(angle, 0, 180);

  return map(angle, 0, 180, SERVOMIN, SERVOMAX);
}

void servoWrite(int channel, int angle) {

  int pulse = angleToPulse(angle);

  pca.setPWM(channel, 0, pulse);
}

const int UNLOCK_ANGLE = 0;
const int LOCK_ANGLE   = 180;

// =====================================================
// LOCKER MAP
// =====================================================
struct LockerMap {
  const char* code;
  int servoChannel;
};

LockerMap lockers[] = {
  {"A-001", 0},
  {"A-002", 1},
  {"A-003", 2},
};

const int lockerCount =
  sizeof(lockers) / sizeof(lockers[0]);

int lockerIndexByCode(const String &code) {

  for (int i = 0; i < lockerCount; i++) {
    if (code == lockers[i].code) return i;
  }
  return -1;
}

int findServoChannelByLockerCode(const String &code) {

  int idx = lockerIndexByCode(code);

  if (idx < 0) return -1;

  return lockers[idx].servoChannel;
}

// =====================================================
// QUEUE
// =====================================================
#define QUEUE_SIZE 12

CommandItem cmdQueue[QUEUE_SIZE];

int qHead = 0;
int qTail = 0;

bool queueIsEmpty() {
  return qHead == qTail;
}

bool queueIsFull() {
  return ((qTail + 1) % QUEUE_SIZE) == qHead;
}

bool queuePush(const CommandItem &item) {

  if (queueIsFull()) return false;

  cmdQueue[qTail] = item;

  qTail = (qTail + 1) % QUEUE_SIZE;

  return true;
}

bool queuePop(CommandItem &out) {

  if (queueIsEmpty()) return false;

  out = cmdQueue[qHead];

  qHead = (qHead + 1) % QUEUE_SIZE;

  return true;
}

// =====================================================
// FIREBASE WRITE
// =====================================================
bool updateLockerNode(const String &lockerCode,
                      const String &relayStatus,
                      const String &relayMessage,
                      bool isLockedValue) {

  String base = "/lockers/" + lockerCode;

  FirebaseJson json;

  json.set("relay/status", relayStatus);
  json.set("relay/message", relayMessage);
  json.set("isLocked", isLockedValue);

  if (!Firebase.RTDB.updateNode(&fbWrite, base, &json)) {

    Serial.println("Update failed: " + fbWrite.errorReason());

    return false;
  }

  return true;
}

bool setRelayStatusOnly(const String &lockerCode,
                        const String &status) {

  String p = "/lockers/" + lockerCode + "/relay/status";

  if (!Firebase.RTDB.setString(&fbWrite, p, status)) {

    Serial.println("Set status failed: " + fbWrite.errorReason());

    return false;
  }

  return true;
}

// =====================================================
// EXECUTE COMMAND
// =====================================================
void executeCommand(const CommandItem &job) {

  int ch = findServoChannelByLockerCode(job.lockerCode);

  if (ch < 0) {

    updateLockerNode(job.lockerCode,
                     "error",
                     "unknown locker",
                     false);
    return;
  }

  setRelayStatusOnly(job.lockerCode, "running");

  if (job.command == "open" || job.command == "unlock") {

    servoWrite(ch, UNLOCK_ANGLE);

    updateLockerNode(job.lockerCode,
                     "completed",
                     "ok",
                     false);
  }

  else if (job.command == "close" || job.command == "lock") {

    servoWrite(ch, LOCK_ANGLE);

    updateLockerNode(job.lockerCode,
                     "completed",
                     "ok",
                     true);
  }

  else {

    updateLockerNode(job.lockerCode,
                     "error",
                     "unknown command",
                     false);
  }
}

// =====================================================
// WIFI CHANGE (WEB)
// =====================================================
void handleWifiChange() {

  if (!isAuthed()) {
    sendText(401, "Unauthorized");
    return;
  }

  sendText(200, "Restarting to WiFi setup mode...");
  delay(1000);

  WiFi.disconnect(true);
  delay(500);

  ESP.restart();   // รีบูตให้เข้า portal ใหม่
}

// =====================================================
// SETUP
// =====================================================
void setup() {

  Serial.begin(115200);
  delay(500);

  // Reset WiFi Button
  pinMode(RESET_WIFI_PIN, INPUT_PULLUP);

  // Servo
  Wire.begin(21, 22);

  pca.begin();
  pca.setPWMFreq(SERVO_FREQ);

  for (int i = 0; i < lockerCount; i++) {
    servoWrite(lockers[i].servoChannel, UNLOCK_ANGLE);
    delay(200);
  }

  // ================= WIFI =================
  WiFi.mode(WIFI_STA);

  WiFiManager wm;

  wm.setBreakAfterConfig(true);   // สำคัญ
  wm.setConnectTimeout(15);
  wm.setConfigPortalTimeout(180);

  if (!wm.autoConnect(AP_NAME, AP_PASS)) {

    Serial.println("WiFi failed");
    ESP.restart();
  }

  Serial.println("WiFi Connected");
  Serial.println(WiFi.localIP());

  // ================= mDNS =================
  if (MDNS.begin(MDNS_NAME)) {

    Serial.println("http://esp32.local");
  }

  // ================= WEB =================
  const char* headerKeys[] = {"X-Auth"};

  server.collectHeaders(headerKeys, 1);

  server.on("/wifi", HTTP_POST, handleWifiChange);

  server.begin();

  // ================= FIREBASE =================
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  config.token_status_callback = tokenStatusCallback;

  Firebase.signUp(&config, &auth, "", "");

  Firebase.begin(&config, &auth);

  Firebase.reconnectWiFi(true);

  Serial.println("SYSTEM READY");
}

// =====================================================
// LOOP
// =====================================================
void loop() {

  server.handleClient();

  // ===== RESET WIFI BUTTON =====
  if (digitalRead(RESET_WIFI_PIN) == LOW) {

    delay(1500);

    if (digitalRead(RESET_WIFI_PIN) == LOW) {

      Serial.println("RESET WIFI");

      WiFiManager wm;

      wm.resetSettings();   // ล้าง WiFi

      delay(500);

      ESP.restart();
    }
  }
  // ============================

  CommandItem job;

  if (queuePop(job)) {
    executeCommand(job);
  }

  delay(10);
}
