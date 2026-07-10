#ifndef DEVICE_IDENTITY_H
#define DEVICE_IDENTITY_H

#include <Arduino.h>

// เรียกให้เร็วที่สุดใน setup() — ก่อน setupWiFi() เลย — เพื่อโหลด/สุ่ม id และโหลด name
// จาก NVS ให้พร้อมใช้งาน ก่อนที่ WiFi.begin() จุดไหนจะถูกเรียก (WiFi.setHostname()
// ต้องตั้งค่าก่อน WiFi.begin() เสมอ ไม่งั้น router จะยังเห็นชื่อ default "esp32-XXXXXX")
void loadDeviceIdentity();

// เรียกหลัง setupWiFi() (ต้องมี network interface ขึ้นก่อน) — ลงทะเบียน route
// /api/device_name และเริ่ม mDNS responder ด้วยชื่อปัจจุบัน
void setupDeviceIdentity();

// เรียกซ้ำได้ทุกครั้งที่ network interface เปลี่ยน (เช่น หลัง connect WiFi บ้านสำเร็จ,
// หรือหลังเปลี่ยนชื่อผ่าน API) เพื่อให้ mDNS responder ประกาศ hostname ใหม่บน interface ปัจจุบัน
void restartMDNS();

String getDeviceId();       // id แบบสุ่ม คงที่ตลอดอายุอุปกรณ์ (ไม่รวม prefix "esp-")
String getDeviceName();     // ชื่อที่ตั้งไว้ ("" ถ้ายังไม่เคยตั้ง)
String getEffectiveName();  // name ถ้ามี ไม่งั้น id
String getMdnsHostname();   // "esp-<effective_name>" (ไม่รวม ".local")

// คืน false ถ้าชื่อไม่ผ่าน validation (ไม่เหลือตัวอักษรที่ใช้ได้เลยหลัง sanitize)
bool setDeviceName(const String &newName);

void handleGetDeviceName();
void handleSetDeviceName();

#endif
