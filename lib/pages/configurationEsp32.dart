import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ── เปลี่ยนจาก dashboard import เดิม ─────────────────
import 'package:ftconfig/pages/dashboard.dart';
import 'package:ftconfig/services/discovery.dart';
import 'package:ftconfig/services/wifi_service.dart';
import 'package:http/http.dart' as http;

class configurationEsp32Page extends StatefulWidget {
  const configurationEsp32Page({super.key});
  @override
  State<configurationEsp32Page> createState() => _configurationEsp32PageState();
}

class _configurationEsp32PageState extends State<configurationEsp32Page> {
  final WifiService _wifiService = WifiService();

  bool isLoading     = true;
  bool isRequesting  = false;
  bool hasPermission = false;
  String? errorMessage;
  List<Esp32Device> devices = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() { isLoading = true; errorMessage = null; });
    final granted = await _wifiService.ensurePermission();
    if (!mounted) return;
    setState(() => hasPermission = granted);
    if (granted) {
      await _scan();
    } else {
      setState(() => isLoading = false);
    }
  }

  Future<void> _requestPermission() async {
    setState(() => isRequesting = true);
    final granted = await _wifiService.ensurePermission();
    if (!mounted) return;
    setState(() { isRequesting = false; hasPermission = granted; });
    if (granted) await _scan();
  }

  Future<void> _onRefresh() async {
    if (!hasPermission) {
      await _requestPermission();
    } else {
      await _scan();
    }
  }

  Future<void> _scan() async {
    setState(() { isLoading = true; errorMessage = null; });
    try {
      final result = await Esp32Discovery.discover(timeout: const Duration(seconds: 5));
      if (!mounted) return;
      setState(() { devices = result; isLoading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { errorMessage = 'สแกนไม่สำเร็จ: $e'; isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ESP32 List"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: isLoading ? null : _onRefresh,
          ),
        ],
      ),
      body: RefreshIndicator(onRefresh: _onRefresh, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("กำลังค้นหาเครือข่าย WiFi..."),
          ],
        ),
      );
    }

    if (!hasPermission) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.location_off, size: 48, color: Colors.orange.shade300),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              "ต้องใช้สิทธิ์ตำแหน่ง (Location) เพื่อสแกนหา ESP32 ใน WiFi นี้",
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              onPressed: isRequesting ? null : _requestPermission,
              icon: isRequesting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_open),
              label: Text(isRequesting ? "กำลังขอสิทธิ์..." : "ขอสิทธิ์"),
            ),
          ),
        ],
      );
    }

    if (errorMessage != null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Center(child: Text(errorMessage!, textAlign: TextAlign.center)),
        ],
      );
    }

    if (devices.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.wifi_find, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Center(child: Text("ไม่พบ ESP32 ใน WLAN นี้")),
          const SizedBox(height: 8),
          Center(
            child: Text(
              "ลากลงเพื่อสแกนใหม่ $isLoading",
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      itemCount: devices.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final device = devices[index];
        return ListTile(
          leading: const Icon(Icons.developer_board),
          title: Text(device.hostname),
          subtitle: Text('${device.ip}:${device.port}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _authenticateDevice(device.hostname, device.ip),
        );
      },
    );
  }

  Future<void> _authenticateDevice(String hostname, String ip) async {
    try {
      final response = await http
          .get(Uri.parse('http://$ip/api/auth'))
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
            // ── showConfigButton: true เพราะเชื่อมผ่าน STA (มี IP จริง) ──
            builder: (_) => dashboardPage(
              baseUrl:          'http://$ip',
              showConfigButton: true,
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
