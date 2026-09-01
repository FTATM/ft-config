import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ── เปลี่ยนจาก infomation.dart → dashboard.dart ──────
import 'package:ftconfig/pages/dashboard.dart';
import 'package:ftconfig/services/wifi_service.dart';
import 'package:http/http.dart' as http;
import 'package:wifi_scan/wifi_scan.dart';

class WifiConnectPage extends StatefulWidget {
  final WiFiAccessPoint accessPoint;

  const WifiConnectPage({super.key, required this.accessPoint});

  @override
  State<WifiConnectPage> createState() => _WifiConnectPageState();
}

class _WifiConnectPageState extends State<WifiConnectPage> {
  final passwordController = TextEditingController();

  String statusBtn  = "เชื่อมต่อ";
  String statusText = "ไม่ได้เชื่อมต่อ";
  bool obscure = true;

  final wifi = WifiService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Connect WiFi")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.wifi, size: 80),
            const SizedBox(height: 20),
            Text(widget.accessPoint.ssid,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(statusText, style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 30),
            TextField(
              controller: passwordController,
              obscureText: obscure,
              decoration: InputDecoration(
                labelText: "รหัสผ่าน",
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => obscure = !obscure),
                ),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: const ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(Colors.blueAccent),
                ),
                onPressed: () => _connectWifi(widget.accessPoint.ssid, passwordController.text),
                child: Text(statusBtn, style: const TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectWifi(String ssid, String password) async {
    if (!mounted) return;
    setState(() => statusText = "กำลังเชื่อมต่อไปยัง $ssid");

    if (ssid.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("กรุณากรอกรหัสผ่าน")),
      );
      return;
    }

    final ok = await wifi.connect(ssid, password);
    if (!mounted) return;

    if (ok) {
      setState(() => statusText = "เชื่อมต่อสำเร็จแล้ว");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("เชื่อมต่อสำเร็จ")));
      if (!mounted) return;
      await _authenticateAndProceed(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("เชื่อมต่อไม่สำเร็จ")));
    }
  }

  Future<void> _authenticateAndProceed(BuildContext context) async {
    const apBaseUrl = 'http://192.168.4.1';
    try {
      final response = await http
          .get(Uri.parse('$apBaseUrl/api/auth'))
          .timeout(const Duration(seconds: 5));

      if (!context.mounted) return;

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("เชื่อมต่อไม่สำเร็จ (${response.statusCode})")),
        );
        return;
      }

      late final Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } on FormatException {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("รูปแบบข้อมูลจากอุปกรณ์ไม่ถูกต้อง")),
        );
        return;
      }

      final success = data['success'] == true;
      final token   = data['token']?.toString();

      if (success && token != null) {
        if (!context.mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            // ── showConfigButton: false เพราะยังอยู่ใน AP mode ──
            builder: (_) => const dashboardPage(
              baseUrl:          'http://192.168.4.1',
              showConfigButton: false,
            ),
          ),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Authenticate ไม่สำเร็จ")),
        );
      }
    } on TimeoutException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("หมดเวลาเชื่อมต่ออุปกรณ์")),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("เกิดข้อผิดพลาด: $e")),
      );
    }
  }
}
