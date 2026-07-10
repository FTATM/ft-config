#include "WebAPI.h"
#include "WiFiManager.h"
#include "DeviceIdentity.h"
#include <WiFi.h>
#include <ArduinoJson.h>

WebServer server(80);

// =====================================================
// Scan state — แยก "ขอสแกน" กับ "เริ่มสแกนจริง" ออกจากกันคนละรอบ loop()
// เพื่อไม่ให้วิทยุสลับไปสแกนก่อนที่ response ของ HTTP request นี้จะถูกส่งออก
// ทาง AP ไปถึงมือถือให้ครบ (คือสาเหตุที่ round แรกของการ poll ช้าผิดปกติ)
// =====================================================
static volatile bool scanRequested = false;
static volatile bool scanStarted = false;


// =====================================================
// Route Registration
// =====================================================
void handleRoot();
void handleAuth();
void handleStatus();
void handleWiFi();
void handleInfo();
void handleScanWiFi();
void handleSetupWiFi();
void handleResetWiFi();

void setupAPI() {
  server.on("/", HTTP_GET, handleRoot);

  server.on("/api/auth", HTTP_GET, handleAuth);

  server.on("/api/status", HTTP_GET, handleStatus);

  server.on("/api/wifi", HTTP_GET, handleWiFi);

  server.on("/api/info", HTTP_GET, handleInfo);

  server.on("/api/scan_wifi", HTTP_GET, handleScanWiFi);

  server.on("/api/setup_wifi", HTTP_POST, handleSetupWiFi);

  server.on("/api/reset_wifi", HTTP_POST, handleResetWiFi);
}

void handleRoot() {
  server.send(
    200,
    "text/plain",
    "ESP32 API Server");
}

void handleAuth() {
  DynamicJsonDocument doc(256);

  doc["success"] = true;

  doc["token"] = 12345678;

  String json;

  serializeJson(doc, json);

  server.send(
    200,
    "application/json",
    json);
}

void handleStatus() {
  DynamicJsonDocument doc(256);

  doc["success"] = true;

  doc["mode"] = apMode ? "AP" : "STA";

  doc["connected"] = wifiConnected;

  doc["ip"] = wifiConnected ? WiFi.localIP().toString() : WiFi.softAPIP().toString();

  String json;

  serializeJson(doc, json);

  server.send(
    200,
    "application/json",
    json);
}

void handleInfo() {
  DynamicJsonDocument doc(384);

  doc["success"] = true;

  doc["mode"] = apMode ? "AP" : "STA";

  doc["connected"] = wifiConnected;

  // RSSI/BSSID มีความหมายเฉพาะตอนต่อกับ router จริง (STA mode)
  // ถ้ายังอยู่ AP mode (ยังไม่เคย setup wifi) ค่าพวกนี้จะไม่ valid
  if (wifiConnected) {
    doc["ssid"] = WiFi.SSID();
    doc["bssid"] = WiFi.BSSIDstr();
    doc["rssi"] = WiFi.RSSI();
    doc["ip"] = WiFi.localIP().toString();
    doc["gateway"] = WiFi.gatewayIP().toString();
  } else {
    doc["ssid"] = nullptr;
    doc["ip"] = WiFi.softAPIP().toString();
  }

  doc["mac"] = WiFi.macAddress();

  doc["uptime_ms"] = millis();

  String json;

  serializeJson(doc, json);

  server.send(
    200,
    "application/json",
    json);
}

void handleWiFi() {
  DynamicJsonDocument doc(256);

  doc["success"] = true;

  doc["ssid"] = wifiSSID;

  String json;

  serializeJson(doc, json);

  server.send(
    200,
    "application/json",
    json);
}

void handleScanWiFi() {
  int status = WiFi.scanComplete();

  if (status == WIFI_SCAN_RUNNING) {
    // กำลังสแกนอยู่จริง (เริ่มไปแล้วจาก handlePendingScan() ในรอบ loop ก่อนหน้า)
    server.send(200, "application/json", "{\"success\":true,\"status\":\"scanning\"}");
    return;
  }

  if (status == WIFI_SCAN_FAILED) {
    // แค่ "ขอ" ให้เริ่มสแกน ไม่เรียก WiFi.scanNetworks() ตรงนี้เลย —
    // ให้ response นี้มีเวลาส่งออกทาง AP ก่อน แล้วค่อยเริ่มสแกนจริงในรอบ loop ถัดไป
    if (!scanStarted) {
      scanRequested = true;
    }
    server.send(200, "application/json", "{\"success\":true,\"status\":\"started\"}");
    return;
  }

  // status >= 0 คือจำนวนเครือข่ายที่เจอ สแกนเสร็จแล้วจริง ๆ
  DynamicJsonDocument doc(4096);
  JsonArray networks = doc.createNestedArray("networks");

  for (int i = 0; i < status; i++) {
    JsonObject obj = networks.createNestedObject();
    obj["ssid"] = WiFi.SSID(i);
    obj["rssi"] = WiFi.RSSI(i);
    obj["secure"] = WiFi.encryptionType(i) != WIFI_AUTH_OPEN;
  }

  WiFi.scanDelete();
  scanStarted = false; // เคลียร์ไว้ เผื่อ user กดสแกนใหม่รอบหน้า

  doc["success"] = true;
  doc["status"] = "done";

  String json;
  serializeJson(doc, json);
  server.send(200, "application/json", json);
}

void handlePendingScan() {
  if (scanRequested && !scanStarted) {
    scanStarted = true;
    scanRequested = false;
    WiFi.scanNetworks(true); // true = async, ไม่ block
  }
}

void handleSetupWiFi() {
  DynamicJsonDocument doc(512);

  DeserializationError error =
    deserializeJson(
      doc,
      server.arg("plain"));

  if (error) {
    server.send(
      400,
      "application/json",
      "{\"success\":false,\"message\":\"Invalid JSON\"}");

    return;
  }

  String ssid = doc["ssid"] | "";

  String password = doc["password"] | "";

  // Validate ssid is not empty before attempting to connect
  // (fixed vs original code, which allowed an empty ssid through).
  if (ssid == "") {
    server.send(
      400,
      "application/json",
      "{\"success\":false,\"message\":\"SSID is required\"}");

    return;
  }

  WiFi.disconnect(true);

  delay(500);

  WiFi.mode(WIFI_AP_STA);

  WiFi.begin(
    ssid.c_str(),
    password.c_str());

  unsigned long start = millis();

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);

    if (millis() - start > 15000) {
      server.send(
        200,
        "application/json",
        "{\"success\":false,\"message\":\"Connect Failed\"}");

      startAP();

      return;
    }
  }

  saveWiFi(
    ssid,
    password);

  wifiConnected = true;

  DynamicJsonDocument res(256);

  res["success"] = true;

  res["message"] = "Connected";

  res["ip"] =
    WiFi.localIP().toString();

  String json;

  serializeJson(
    res,
    json);

  server.send(
    200,
    "application/json",
    json);

  // ให้เวลา TCP stack ส่ง response ผ่านลิงก์ AP ไปถึงมือถือให้ครบก่อน
  // ค่อยปิด AP — ไม่งั้น interface หายไปก่อน client จะ ACK รับ response ทัน
  delay(1000);

  stopAP();

  restartMDNS();

}

void handleResetWiFi() {
  clearWiFi();

  DynamicJsonDocument doc(128);

  doc["success"] = true;

  String json;

  serializeJson(doc, json);

  server.send(
    200,
    "application/json",
    json);

  delay(1000);

  ESP.restart();
}

void setupServer() {
  setupAPI();

  server.begin();

  Serial.println("Web Server Started");
}
