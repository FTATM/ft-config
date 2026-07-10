import 'package:flutter/services.dart';

class WifiNative {
  // Must match MainActivity.kt: private const val CHANNEL = "ftconfig/wifi"
  static const MethodChannel _channel = MethodChannel("ftconfig/wifi");

  /// Connect WiFi
  static Future<bool> connect({
    required String ssid,
    required String password,
  }) async {
    final bool? result = await _channel.invokeMethod(
      "connectWifi",
      {
        "ssid": ssid,
        "password": password,
      },
    );

    return result ?? false;
  }

  /// Disconnect
  static Future<bool> disconnect() async {
    final bool? result = await _channel.invokeMethod("disconnectWifi");
    return result ?? false;
  }

  /// Check Permission
  static Future<bool> hasPermission() async {
    final bool? result = await _channel.invokeMethod("hasPermission");
    return result ?? false;
  }

  /// Request Permission
  /// Native side replies only after onRequestPermissionsResult fires, so this
  /// already resolves to the real grant result — no need to poll/delay after it.
  static Future<bool> requestPermission() async {
    final bool? result = await _channel.invokeMethod("requestPermission");
    return result ?? false;
  }

  /// Optional extras exposed by MainActivity.kt, in case you need them later
  static Future<String?> getCurrentWifi() async {
    return await _channel.invokeMethod("getCurrentWifi");
  }

  static Future<bool> isWifiEnabled() async {
    final bool? result = await _channel.invokeMethod("isWifiEnabled");
    return result ?? false;
  }

  static Future<bool> enableWifi() async {
    final bool? result = await _channel.invokeMethod("enableWifi");
    return result ?? false;
  }

  static Future<List<Map<String, dynamic>>> scanWifi() async {
    final List<dynamic>? result = await _channel.invokeMethod("scanWifi");
    return result?.map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
  }


  /// ต้อง acquire ก่อนเริ่ม mDNS discovery ทุกครั้ง ไม่งั้น Android จะบล็อก
  /// multicast packet ไว้ ทำให้หา ESP32 ผ่าน .local ไม่เจอเลย
  static Future<bool> acquireMulticastLock() async {
    final bool? result = await _channel.invokeMethod("acquireMulticastLock");
    return result ?? false;
  }
 
  /// เรียกทันทีหลังเลิกใช้ mDNS discovery แล้ว (เช่นใน finally block)
  /// ปล่อย lock ทิ้งไว้นานเกินจำเป็นจะกินแบตเตอรี่
  static Future<bool> releaseMulticastLock() async {
    final bool? result = await _channel.invokeMethod("releaseMulticastLock");
    return result ?? false;
  }
}
