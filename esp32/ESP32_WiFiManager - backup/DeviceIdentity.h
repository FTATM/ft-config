#ifndef DEVICE_IDENTITY_H
#define DEVICE_IDENTITY_H

#include <Arduino.h>

// เรียกครั้งเดียวหลัง setupWiFi() (ต้องมี network interface ขึ้นแล้ว ไม่ว่า AP หรือ STA)
// โหลด/สุ่ม id ครั้งแรกถ้ายังไม่เคยมี แล้วเริ่ม mDNS responder ด้วยชื่อปัจจุบัน
// และลงทะเบียน route /api/device_name ทั้ง GET/POST
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
