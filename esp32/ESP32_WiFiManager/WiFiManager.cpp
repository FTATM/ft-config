#include "WiFiManager.h"
#include "DeviceIdentity.h"
#include <WiFi.h>
#include <Preferences.h>

// =====================================================
// AP Config
// =====================================================
const char* AP_SSID = "ESP32-Setup";
const char* AP_PASSWORD = "12345678";

// =====================================================
// Global State
// =====================================================
String wifiSSID = "";
String wifiPASS = "";

bool wifiConnected = false;
bool apMode = false;

static Preferences preferences;

// =====================================================
// Load WiFi
// =====================================================
void loadWiFi() {
  preferences.begin("wifi", true);

  wifiSSID = preferences.getString("ssid", "");
  wifiPASS = preferences.getString("pass", "");

  preferences.end();

  Serial.println("========== Stored WiFi ==========");
  Serial.print("SSID : ");
  Serial.println(wifiSSID);
  Serial.println("=================================");
}

// =====================================================
// Save WiFi
// =====================================================
void saveWiFi(String ssid, String password) {
  preferences.begin("wifi", false);

  preferences.putString("ssid", ssid);
  preferences.putString("pass", password);

  preferences.end();

  wifiSSID = ssid;
  wifiPASS = password;

  Serial.println("WiFi Saved.");
}

// =====================================================
// Clear WiFi
// =====================================================
void clearWiFi() {
  preferences.begin("wifi", false);

  preferences.clear();

  preferences.end();

  wifiSSID = "";
  wifiPASS = "";

  Serial.println("WiFi Cleared.");
}

// =====================================================
// Connect WiFi (STA)
// =====================================================
bool connectWiFi() {
  if (wifiSSID == "") {
    Serial.println("No WiFi Config.");

    wifiConnected = false;

    return false;
  }

  Serial.println();
  Serial.println("Connecting WiFi...");
  Serial.println(wifiSSID);

  WiFi.mode(WIFI_STA);

  // ต้องตั้ง hostname ก่อน WiFi.begin() เสมอ ไม่งั้น router จะเห็นชื่อ default
  // "esp32-XXXXXX" (จาก MAC) แทนชื่อที่ผู้ใช้ตั้งไว้ผ่าน /api/device_name —
  // จุดนี้สำคัญเพราะเป็น path ที่ ESP32 auto-reconnect เองตอนบูต (ไม่ผ่าน handleSetupWiFi())
  String targetHostname = getMdnsHostname();
  bool hostnameOk = WiFi.setHostname(targetHostname.c_str());

  // DEBUG ชั่วคราว — เอาไว้เช็คว่า ESP32 คิดว่าตัวเองตั้งชื่อสำเร็จหรือเปล่า
  // ลบออกได้หลัง debug เสร็จ
  Serial.print("[DEBUG] setHostname(\"");
  Serial.print(targetHostname);
  Serial.print("\") returned: ");
  Serial.println(hostnameOk ? "true" : "false");
  Serial.print("[DEBUG] WiFi.getHostname() now reports: ");
  Serial.println(WiFi.getHostname());

  WiFi.begin(
    wifiSSID.c_str(),
    wifiPASS.c_str());

  unsigned long startTime = millis();

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);

    Serial.print(".");

    if (millis() - startTime > 15000) {
      Serial.println();
      Serial.println("Connect Timeout.");

      wifiConnected = false;

      return false;
    }
  }

  Serial.println();
  Serial.println("Connected.");

  Serial.print("IP : ");
  Serial.println(WiFi.localIP());

  wifiConnected = true;

  return true;
}

// =====================================================
// AP Mode
// =====================================================
void startAP() {
  if (apMode)
    return;

  Serial.println();
  Serial.println("Starting AP Mode...");

  WiFi.mode(WIFI_AP);

  WiFi.softAP(
    AP_SSID,
    AP_PASSWORD);

  Serial.print("AP IP : ");
  Serial.println(WiFi.softAPIP());

  apMode = true;
}

void stopAP() {
  if (!apMode)
    return;

  WiFi.softAPdisconnect(true);

  apMode = false;

  Serial.println("AP Stopped.");
}

// =====================================================
// Helpers
// =====================================================
String getIPAddress() {
  if (WiFi.status() == WL_CONNECTED) {
    return WiFi.localIP().toString();
  }

  return "";
}

// =====================================================
// Entry point called from setup()
// =====================================================
void setupWiFi() {
  loadWiFi();

  if (connectWiFi()) {
    Serial.println("WiFi Ready");
    return;
  }

  Serial.println("Start AP Mode");

  startAP();
}
