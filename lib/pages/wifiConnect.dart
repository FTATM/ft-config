import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ftconfig/pages/infomation.dart';
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

  String statusBtn = "เชื่อมต่อ";
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
            Icon(Icons.wifi, size: 80),

            const SizedBox(height: 20),

            Text(widget.accessPoint.ssid, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),

            Text(statusText, style: const TextStyle(fontSize: 16, color: Colors.grey)),

            const SizedBox(height: 30),

            TextField(
              controller: passwordController,

              obscureText: obscure,

              decoration: InputDecoration(
                labelText: "รหัสผ่าน",

                border: OutlineInputBorder(),

                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),

                  onPressed: () {
                    setState(() {
                      obscure = !obscure;
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.blueAccent)),
                onPressed: () {
                  connectWifi(widget.accessPoint.ssid, passwordController.text);
                },

                child: Text(statusBtn, style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> connectWifi(String ssid, String password) async {
    if (!mounted) return;
    setState(() {
      statusText = "กำลังเชื่อมต่อไปยัง $ssid";
    });

    if (ssid.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("กรุณากรอกรหัสผ่าน")));
      return;
    }
    bool ok = await wifi.connect(ssid, password);
    if (!mounted) return;

    if (ok) {
      setState(() {
        statusText = "เชื่อมต่อสำเร็จแล้ว";
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("เชื่อมต่อสำเร็จ")));

      if (!mounted) return;

      authenticateAndProceed(context);

    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("เชื่อมต่อไม่สำเร็จ")));
    }
  }

  Future<void> authenticateAndProceed(BuildContext context) async {
    try {
      final response = await http.get(Uri.parse('http://192.168.4.1/api/auth')).timeout(const Duration(seconds: 5));

      // ป้องกัน context ถูกใช้หลัง widget ถูก dispose ระหว่างรอ network
      if (!context.mounted) return;

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("เชื่อมต่อไม่สำเร็จ (${response.statusCode})")));
        return;
      }

      late final Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } on FormatException {
        // ESP32 ตอบมาไม่ใช่ JSON ที่ถูกต้อง (เช่น ยังเป็น "Not found: /auth" แบบ plain text)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("รูปแบบข้อมูลจากอุปกรณ์ไม่ถูกต้อง")));
        return;
      }

      final success = data['success'] == true;
      final token = data['token']?.toString();

      if (success && token != null) {
        // TODO: เก็บ token ไว้ใช้ต่อ (เช่น secure storage) — ตอนนี้ยังไม่เข้ารหัสตามที่แจ้งไว้
        if (!context.mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const InfomationPage()),
          (route) => false, // ลบทุก route เดิมทิ้งหมด ไม่เหลือให้ pop กลับ
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Authenticate ไม่สำเร็จ")));
      }
    } on TimeoutException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("หมดเวลาเชื่อมต่ออุปกรณ์")));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("เกิดข้อผิดพลาด: $e")));
    }
  }
}
