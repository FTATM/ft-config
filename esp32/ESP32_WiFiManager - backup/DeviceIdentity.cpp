#include "DeviceIdentity.h"
#include "WebAPI.h"
#include <Preferences.h>
#include <ESPmDNS.h>
#include <ArduinoJson.h>
#include <esp_system.h>

static Preferences prefs;
static String deviceId;
static String deviceName;

// mDNS hostname label ใช้ได้แค่ a-z, 0-9, '-' (RFC 1035) และห้ามขึ้น/ลงท้ายด้วย '-'
static String sanitizeForHostname(const String &input) {
  String out;
  out.reserve(input.length());

  for (size_t i = 0; i < input.length(); i++) {
    char c = input.charAt(i);

    if (c >= 'A' && c <= 'Z') {
      c = c - 'A' + 'a'; // แปลงเป็นตัวพิมพ์เล็กให้หมด
    }

    bool ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-';

    if (ok) {
      out += c;
    } else if (c == ' ' || c == '_') {
      out += '-'; // แทนที่ space/underscore ด้วย '-'
    }
    // ตัวอักษรอื่นที่ไม่รองรับ (เช่น ไทย, emoji, สัญลักษณ์) จะถูกตัดทิ้งไปเงียบๆ
  }

  while (out.startsWith("-")) out.remove(0, 1);
  while (out.endsWith("-")) out.remove(out.length() - 1, 1);

  // "esp-" กิน 4 ตัวไปแล้ว เผื่อพื้นที่ไว้ ทั้ง label ต้องไม่เกิน 63 ตัวตาม RFC 1035
  const size_t maxLen = 40;
  if (out.length() > maxLen) {
    out = out.substring(0, maxLen);
  }

  return out;
}

static String generateRandomId() {
  // ใช้ esp_random() (hardware RNG จริงของ ESP32 ไม่ใช่ pseudo-random จาก seed)
  uint32_t r = esp_random();
  char buf[7];
  snprintf(buf, sizeof(buf), "%06x", (unsigned int)(r & 0xFFFFFF));
  return String(buf);
}

void setupDeviceIdentity() {
  prefs.begin("device", false);

  deviceId = prefs.getString("id", "");

  if (deviceId.length() == 0) {
    // สุ่มครั้งแรกที่บูตแล้วเก็บถาวรใน flash — จากนี้ id จะไม่เปลี่ยนอีก
    // แม้จะรีสตาร์ทเครื่องหรือ reset wifi credentials ก็ตาม
    deviceId = generateRandomId();
    prefs.putString("id", deviceId);
  }

  deviceName = prefs.getString("name", "");

  server.on("/api/device_name", HTTP_GET, handleGetDeviceName);
  server.on("/api/device_name", HTTP_POST, handleSetDeviceName);

  restartMDNS();
}

void restartMDNS() {
  MDNS.end();

  String hostname = getMdnsHostname();

  if (MDNS.begin(hostname.c_str())) {
    MDNS.addService("http", "tcp", 80);
    Serial.print("mDNS started: ");
    Serial.print(hostname);
    Serial.println(".local");
  } else {
    Serial.println("mDNS start failed");
  }
}

String getDeviceId() {
  return deviceId;
}

String getDeviceName() {
  return deviceName;
}

String getEffectiveName() {
  return deviceName.length() > 0 ? deviceName : deviceId;
}

String getMdnsHostname() {
  return "esp-" + getEffectiveName();
}

bool setDeviceName(const String &newName) {
  String clean = sanitizeForHostname(newName);

  if (clean.length() == 0) {
    return false; // ไม่เหลือตัวอักษรที่ใช้ได้เลยหลัง sanitize
  }

  deviceName = clean;
  prefs.putString("name", deviceName);

  restartMDNS(); // ประกาศ hostname ใหม่ทันที

  return true;
}

void handleGetDeviceName() {
  DynamicJsonDocument doc(256);

  doc["success"] = true;
  doc["id"] = getDeviceId();
  doc["name"] = getDeviceName();
  doc["effective_name"] = getEffectiveName();
  doc["hostname"] = getMdnsHostname() + ".local";

  String json;
  serializeJson(doc, json);

  server.send(200, "application/json", json);
}

void handleSetDeviceName() {
  DynamicJsonDocument doc(256);

  DeserializationError error = deserializeJson(doc, server.arg("plain"));

  if (error) {
    server.send(400, "application/json", "{\"success\":false,\"message\":\"Invalid JSON\"}");
    return;
  }

  String requestedName = doc["name"] | "";

  if (!setDeviceName(requestedName)) {
    server.send(
      400,
      "application/json",
      "{\"success\":false,\"message\":\"Invalid name (must contain at least one a-z/0-9/- character)\"}");
    return;
  }

  DynamicJsonDocument res(256);
  res["success"] = true;
  res["name"] = getDeviceName();
  res["effective_name"] = getEffectiveName();
  res["hostname"] = getMdnsHostname() + ".local";

  String json;
  serializeJson(res, json);

  server.send(200, "application/json", json);
}
