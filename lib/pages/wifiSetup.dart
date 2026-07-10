import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ftconfig/services/wifi_native.dart';
import 'package:http/http.dart' as http;

class WifiSetupPage extends StatefulWidget {
  const WifiSetupPage({super.key});

  @override
  State<WifiSetupPage> createState() => _WifiSetupPageState();
}

class _WifiSetupPageState extends State<WifiSetupPage> {
  static const _baseUrl = 'http://192.168.4.1';
  static const _timeout = Duration(seconds: 8);
  static const _scanTimeout = Duration(seconds: 15); // scan ฝั่ง ESP32 ช้ากว่า request ปกติ

  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _submitting = false;

  bool _loadingNetworks = true;
  String? _networksError;
  List<Map<String, dynamic>> _networks = [];
  String? _selectedSsid;

  @override
  void initState() {
    super.initState();
    _loadNetworks();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  // แทนที่จะรอ response เดียวค้างนาน ๆ ซึ่งจะโดน connection abort ระหว่างที่วิทยุยุ่งอยู่กับสแกน
  static const _pollInterval = Duration(seconds: 1);
  static const _maxPolls = 15; // ~15 วิ สูงสุด กันเผื่อ ESP32 ค้าง

  Future<void> _loadNetworks() async {
    setState(() {
      _loadingNetworks = true;
      _networksError = null;
    });

    try {
      for (int attempt = 0; attempt < _maxPolls; attempt++) {
        print("round : $attempt");
        final res = await http.get(Uri.parse('$_baseUrl/api/scan_wifi')).timeout(_scanTimeout);

        if (!mounted) return;

        if (res.statusCode != 200) {
          setState(() {
            _networksError = 'สแกนไม่สำเร็จ (${res.statusCode})';
            _loadingNetworks = false;
          });
          return;
        }

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final status = data['status']?.toString();

        if (status == 'started' || status == 'scanning') {
          print(status);
          await Future.delayed(_pollInterval);
          continue;
        }

        // // status == 'done' (หรือ response เก่าที่ไม่มี status field เลย ถือว่าเสร็จแล้ว)
        final rawList = (data['networks'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

        final networks = rawList.toList()..sort((a, b) => (b['rssi'] as num).compareTo(a['rssi'] as num));

        print(networks);

        setState(() {
          _networks = networks;
          _loadingNetworks = false;
          // ถ้า SSID ที่เคยเลือกไว้หายไปจากผลสแกนใหม่ (เช่นกด refresh) ให้เคลียร์ค่าเลือกทิ้ง
          if (!_networks.any((n) => n['ssid'] == _selectedSsid)) {
            _selectedSsid = null;
          }
        });
        return;
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _networksError = 'หมดเวลาสแกน WiFi';
        _loadingNetworks = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _networksError = 'เกิดข้อผิดพลาด: $e';
        _loadingNetworks = false;
      });
    }
    if (_networksError != null) print(_networksError);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);

    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/setup_wifi'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({"ssid": _selectedSsid, "password": _passwordController.text}),
          )
          .timeout(_timeout);

      if (!mounted) return;

      if (res.statusCode != 200) {
        _showMessage('ตั้งค่าไม่สำเร็จ (${res.statusCode})');
        return;
      }

      Map<String, dynamic>? data;
      try {
        data = jsonDecode(res.body) as Map<String, dynamic>;
      } on FormatException {
        data = null;
      }

      print("Response From ESP32 : $data");

      final success = data?['success'] == true;

      if (success) {
        final ip = data?['ip']?.toString();

        _showMessage('ตั้งค่า WiFi สำเร็จ');

        // ปลด process ของแอปออกจาก network เฉพาะกิจของ ESP32 AP ทันที
        // ไม่ต้องรอ Android detect เอง (onLost มักดีเลย์หลายวินาทีหลัง ESP32 ปิด AP)
        // ไม่งั้น request ไป IP ใหม่ที่ Dashboard จะพลาด เพราะยังถูก bind ค้างกับ network ที่ตายไปแล้ว
        await WifiNative.disconnect();

        if (!mounted) return;
        Navigator.pop(context, ip); // ส่ง IP ใหม่กลับไปให้ Dashboard
      } else {
        _showMessage(data?['message']?.toString() ?? 'ตั้งค่า WiFi ไม่สำเร็จ');
      }
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่ออุปกรณ์');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildSsidField() {
    if (_loadingNetworks) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text("กำลังสแกน WiFi..."),
          ],
        ),
      );
    }

    if (_networksError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_networksError!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadNetworks,
              icon: const Icon(Icons.refresh),
              label: const Text("สแกนใหม่"),
            ),
          ],
        ),
      );
    }

    if (_networks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ไม่พบเครือข่าย WiFi"),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadNetworks,
              icon: const Icon(Icons.refresh),
              label: const Text("สแกนใหม่"),
            ),
          ],
        ),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: _selectedSsid,
      isExpanded: true,
      decoration: const InputDecoration(labelText: "SSID", prefixIcon: Icon(Icons.wifi), border: OutlineInputBorder()),
      items: _networks.map((net) {
        final ssid = net['ssid'].toString();
        final rssi = net['rssi'];
        final secure = net['secure'] == true;

        return DropdownMenuItem(
          value: ssid,
          child: Row(
            children: [
              Icon(secure ? Icons.lock : Icons.lock_open, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(ssid, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text("${rssi}dBm", style: const TextStyle(color: Colors.grey)),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) => setState(() => _selectedSsid = value),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'กรุณาเลือก SSID';
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Wifi Connection"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadingNetworks ? null : _loadNetworks)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSsidField(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: "Password",
                  prefixIcon: const Icon(Icons.lock),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'กรุณากรอกรหัสผ่าน';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text("บันทึกและเชื่อมต่อ"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
