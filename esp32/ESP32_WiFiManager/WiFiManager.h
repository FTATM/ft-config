#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include <Arduino.h>

// =====================================================
// AP Config
// =====================================================
extern const char* AP_SSID;
extern const char* AP_PASSWORD;

// =====================================================
// Global State (shared with WebAPI.cpp / main .ino)
// =====================================================
extern String wifiSSID;
extern String wifiPASS;
extern bool wifiConnected;
extern bool apMode;

// =====================================================
// Function Declarations
// =====================================================
bool connectWiFi();
void startAP();
void stopAP();

void loadWiFi();
void saveWiFi(String ssid, String password);
void clearWiFi();

String getIPAddress();

void setupWiFi();

#endif
