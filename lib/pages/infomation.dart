import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ftconfig/pages/menu.dart';
import 'package:ftconfig/pages/wifiSetup.dart';
import 'package:http/http.dart' as http;

class InfomationPage extends StatefulWidget {
  const InfomationPage({super.key, this.baseUrl = 'http://192.168.4.1'});

  final String baseUrl;

  @override
  State<InfomationPage> createState() => _InfomationPageState();
}

class _InfomationPageState extends State<InfomationPage> {
  late String _baseUrl;
  static const _timeout = Duration(seconds: 5);

  Map<String, dynamic>? _infoData;
  Map<String, dynamic>? _infoDevice;

  String? _infoError;
  String? _deviceError;

  bool _loadingInfo = true;
  bool _loadingDevice = true;

  @override
  void initState() {
    super.initState();
    _baseUrl = widget.baseUrl;
    _loadInfo();
    _loadDevice();
  }

  Future<void> _loadInfo() async {
    print("กำลังเชื่อมกับ $_baseUrl");
    setState(() {
      _loadingInfo = true;
      _infoError = null;
    });

    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/info')).timeout(_timeout);

      if (!mounted) return;

      if (res.statusCode == 200) {
        setState(() {
          _infoData = jsonDecode(res.body) as Map<String, dynamic>;
          _loadingInfo = false;
        });
      } else {
        setState(() {
          _infoError = 'ดึงข้อมูลอุปกรณ์ผิดพลาด (${res.statusCode})';
          _loadingInfo = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _infoError = 'หมดเวลาเชื่อมต่อ';
        _loadingInfo = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _infoError = 'เกิดข้อผิดพลาด: $e';
        _loadingInfo = false;
      });
    }
  }

  Future<void> _loadDevice() async {
    print("กำลังเชื่อมกับ $_baseUrl");
    setState(() {
      _loadingDevice = true;
      _deviceError = null;
    });

    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/device_name')).timeout(_timeout);

      if (!mounted) return;

      if (res.statusCode == 200) {
        setState(() {
          _infoDevice = jsonDecode(res.body) as Map<String, dynamic>;
          _loadingDevice = false;
        });
      } else {
        setState(() {
          _deviceError = 'ดึงข้อมูลอุปกรณ์ผิดพลาด (${res.statusCode})';
          _loadingDevice = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _deviceError = 'หมดเวลาเชื่อมต่อ';
        _loadingDevice = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deviceError = 'เกิดข้อผิดพลาด: $e';
        _loadingDevice = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadInfo(), _loadDevice()]);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // ปิดการ pop ด้วย back ปุ่ม/gesture ทั้งหมด
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Dashboard"),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshAll)],
        ),
        body: RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildInfoDeviceCard(
                title: "ข้อมูลอุปกรณ์",
                loading: _loadingDevice,
                error: _deviceError,
                data: _infoDevice,
              ),
              const SizedBox(height: 16),
              _buildSectionCard(title: "ข้อมูลการเชื่อมต่อ", loading: _loadingInfo, error: _infoError, data: _infoData),
              const SizedBox(height: 16),
              Visibility(visible: _infoData?['mode'] == "AP", child: _buildWifiConnectionButton()),
              Visibility(visible: _infoData?['mode'] != "AP", child: _buildLogoutButton()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required bool loading,
    required String? error,
    required Map<String, dynamic>? data,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (error != null)
              Text(error, style: const TextStyle(color: Colors.red))
            else if (data == null || data.isEmpty)
              const Text("ไม่มีข้อมูล")
            else
              ...data.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key, style: const TextStyle(color: Colors.grey)),
                      Text("${e.value}"),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoDeviceCard({
    required String title,
    required bool loading,
    required String? error,
    required Map<String, dynamic>? data,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.edit, size: 16),
                  tooltip: "แก้ไขชื่ออุปกรณ์",
                  // ปิดปุ่มไว้ระหว่างโหลด/error เพราะยังไม่รู้ชื่อปัจจุบันแน่ชัด
                  onPressed: (loading || data == null)
                      ? null
                      : () => _showEditDeviceNameDialog(currentName: data['name']?.toString() ?? ''),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (error != null)
              Text(error, style: const TextStyle(color: Colors.red))
            else if (data == null || data.isEmpty)
              const Text("ไม่มีข้อมูล")
            else
              ...data.entries.map((e) {
                final isNameField = e.key == 'name';
                final isUnset = isNameField && data['effective_name'] == data['id'];

                Widget valueWidget = Text(
                  isUnset ? "แก้ไข" : "${e.value}",
                  style: isUnset ? const TextStyle(color: Colors.blue, decoration: TextDecoration.underline) : null,
                );

                // ให้กดแก้ไขได้เฉพาะแถว "name" เท่านั้น (ไม่ว่าจะยังไม่ตั้งชื่อ หรือตั้งแล้วก็แก้ต่อได้)
                if (isNameField) {
                  valueWidget = InkWell(
                    onTap: () => _showEditDeviceNameDialog(currentName: isUnset ? '' : e.value?.toString() ?? ''),
                    child: valueWidget,
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key, style: const TextStyle(color: Colors.grey)),
                      valueWidget,
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.logout),
        title: const Text("Back to menu"),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const MenuPage()),
            (route) => false, // ลบทุก route เดิมทิ้งหมด ไม่เหลือให้ pop กลับ
          );
        },
      ),
    );
  }

  Widget _buildWifiConnectionButton() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.wifi),
        title: const Text("Wifi Connection"),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final newIp = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const WifiSetupPage()));

          if (newIp == null || newIp.isEmpty) return;
          if (!mounted) return;
          print(newIp);
          setState(() {
            // ESP32 ย้ายจาก AP (192.168.4.1) ไปอยู่บน home WiFi แล้ว — ดึงข้อมูลจาก IP ใหม่แทน
            _baseUrl = 'http://$newIp';
          });

          await _refreshAll();
        },
      ),
    );
  }

  Future<void> _showEditDeviceNameDialog({required String currentName}) async {
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();
    bool submitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text("แก้ไขชื่ออุปกรณ์"),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: "ชื่ออุปกรณ์",
                    hintText: "เช่น farm-box-1",
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'กรุณากรอกชื่อ';
                    }
                    return null;
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(dialogContext),
                  child: const Text("ยกเลิก"),
                ),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          if (!(formKey.currentState?.validate() ?? false)) return;

                          setDialogState(() => submitting = true);

                          final ok = await _submitDeviceName(controller.text.trim());

                          if (!dialogContext.mounted) return;

                          if (ok) {
                            Navigator.pop(dialogContext);
                          } else {
                            setDialogState(() => submitting = false);
                          }
                        },
                  child: submitting
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("บันทึก"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _submitDeviceName(String newName) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/device_name'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({"name": newName}),
          )
          .timeout(_timeout);

      if (!mounted) return false;

      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      final success = data?['success'] == true;

      if (res.statusCode == 200 && success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("เปลี่ยนชื่ออุปกรณ์สำเร็จ")));
        await _loadDevice();
        return true;
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(data?['message']?.toString() ?? 'เปลี่ยนชื่อไม่สำเร็จ')));
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      return false;
    }
  }
}
