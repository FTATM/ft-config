import 'package:ftconfig/services/wifi_native.dart';

class WifiService {
  Future<bool> ensurePermission() async {
    bool ok = await WifiNative.hasPermission();

    if (!ok) {
      await WifiNative.requestPermission();

      await Future.delayed(const Duration(seconds: 1));

      ok = await WifiNative.hasPermission();
    }

    return ok;
  }

  Future<bool> connect(
    String ssid,
    String password,
  ) async {
    final permission = await ensurePermission();

    if (!permission) {
      return false;
    }

    return await WifiNative.connect(
      ssid: ssid,
      password: password,
    );
  }

  Future<void> disconnect() async {
    await WifiNative.disconnect();
  }
}