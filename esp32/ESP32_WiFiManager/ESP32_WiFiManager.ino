#include <WiFi.h>
#include "WiFiManager.h"
#include "WebAPI.h"
#include "DeviceIdentity.h"

void setup()
{
    Serial.begin(115200);

    delay(1000);

    Serial.println();
    Serial.println("========================");
    Serial.println("ESP32 Boot");
    Serial.println("========================");

    loadDeviceIdentity(); // ต้องเรียกก่อน setupWiFi() เพื่อให้ WiFi.setHostname() ใช้ค่านี้ได้ทัน

    setupWiFi();

    setupDeviceIdentity(); // เรียกหลัง setupWiFi() เพราะ mDNS ต้องมี network interface ขึ้นก่อน

    setupServer();

    Serial.println();
    Serial.println("========== DEVICE ==========");
    Serial.print("ID       : ");
    Serial.println(getDeviceId());
    Serial.print("Name     : ");
    Serial.println(getDeviceName().length() > 0 ? getDeviceName() : "(not set, using id)");
    Serial.print("Hostname : ");
    Serial.print(getMdnsHostname());
    Serial.println(".local");
    Serial.println("=============================");
}

void loop()
{
    server.handleClient();

    // ถ้ามีคำขอสแกน WiFi ค้างไว้จาก handleScanWiFi() ให้เริ่มสแกนจริงตรงนี้
    // (คนละรอบ loop กับตอนที่ตอบ HTTP response "started" ไป)
    handlePendingScan();

    static unsigned long lastPrint = 0;

    if (millis() - lastPrint > 5000)
    {
        lastPrint = millis();

        Serial.println();

        Serial.println("========== STATUS ==========");

        Serial.print("Device ID : ");

        Serial.println(getDeviceId());

        Serial.print("Device Name : ");

        Serial.println(getDeviceName().length() > 0 ? getDeviceName() : "(not set, using id)");

        Serial.print("Mode : ");

        Serial.println(apMode ? "AP" : "STA");

        Serial.print("Connected : ");

        Serial.println(wifiConnected);

        Serial.print("IP : ");

        if (wifiConnected)
        {
            Serial.println(WiFi.localIP());
        }
        else
        {
            Serial.println(WiFi.softAPIP());
        }

        Serial.println("============================");
    }
}

