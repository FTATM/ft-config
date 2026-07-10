#ifndef WEB_API_H
#define WEB_API_H

#include <WebServer.h>

extern WebServer server;

void setupAPI();
void setupServer();

// เรียกทุกรอบใน loop() หลัก — ถ้ามีการขอสแกน WiFi ค้างไว้จาก handleScanWiFi()
// จะเริ่ม WiFi.scanNetworks() จริงตรงนี้ (คนละรอบ loop กับตอนตอบ HTTP response)
// เพื่อให้ response "started" มีเวลาส่งออกทาง AP ก่อนวิทยุจะสลับไปสแกน
void handlePendingScan();

#endif
