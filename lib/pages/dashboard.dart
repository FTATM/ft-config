import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ftconfig/pages/canSetup.dart';
import 'package:ftconfig/pages/ioSetup.dart';
import 'package:ftconfig/pages/menu.dart';
import 'package:ftconfig/pages/outputSetup.dart';
import 'package:ftconfig/pages/rs485Setup.dart';
import 'package:ftconfig/pages/tcpSetup.dart';
import 'package:ftconfig/pages/wifiSetup.dart';
import 'package:http/http.dart' as http;

// Input type ที่มีหน้า config พร้อมใช้งานจริงแล้วตอนนี้ (ตรงกับ InputBase implementations
// ที่ implement poll() จริง ไม่ใช่แค่ stub — LoRa ยังเป็น TODO ฝั่ง ESP32 อยู่ จึงยังไม่
// เปิดให้เลือกในแอปจนกว่าจะเขียน Input class ฝั่งนั้นเสร็จ)
const Map<String, String> _kAvailableInputTypes = {
  'rs485': 'RS485 (Modbus RTU)',
  'tcp': 'Modbus TCP',
  'can': 'CAN Bus',
  'io': 'IO (GPIO digital/analog)',
};

// Output type ที่เปิดให้เลือกได้ — ใช้ร่วมกันได้ไม่ว่า Input จะเป็นอะไร (ตรงกับ
// ModeConfig.enabledOutputs ฝั่ง ESP32 ที่เปิดได้พร้อมกันหลายตัว) การตั้งค่ารายละเอียด
// ของแต่ละ output (url/host/topic ฯลฯ) อยู่รวมกันในหน้าเดียวที่ OutputSetupPage
// ไม่ผูกกับหน้า config ของ input ตัวไหนทั้งสิ้น — จุดนี้คือสิ่งที่ต่างจากดีไซน์เดิม
// ที่เคยเอา output card ไปแปะซ้ำในทุกหน้า input
const Map<String, String> _kAvailableOutputTypes = {
  'api': 'HTTP API',
  'mqtt': 'MQTT',
  'tcp': 'TCP',
  'udp': 'UDP',
  'app': 'แสดงผลในแอป (App)',
  'rs485': 'RS485 (Modbus RTU) — เขียนค่าออก',
  'modbus_tcp': 'Modbus TCP — เขียนค่าออก',
  'can': 'CAN Bus — เขียนค่าออก',
  'io': 'GPIO Output (Relay ตามเงื่อนไข)',
};

// =====================================================
// dashboardPage — รวม infomation.dart เข้ามาในไฟล์เดียว
//
// showConfigButton:
//   true  = มาจาก configurationEsp32Page (STA mode, เชื่อม router แล้ว)
//           → แสดงปุ่ม "Config Input/Output"
//   false = มาจาก wifiConnect (AP mode, ยังไม่เชื่อม router)
//           → ไม่แสดงปุ่ม Config (ยังตั้งค่าอะไรไม่ได้จนกว่าจะมี network)
// =====================================================
class dashboardPage extends StatefulWidget {
  const dashboardPage({super.key, this.baseUrl = 'http://192.168.4.1', this.showConfigButton = true});

  final String baseUrl;

  /// true = แสดงปุ่ม Config RS485 (ใช้ตอนเชื่อม STA แล้ว)
  final bool showConfigButton;

  @override
  State<dashboardPage> createState() => _dashboardPageState();
}

class _dashboardPageState extends State<dashboardPage> {
  late String _baseUrl;
  static const _timeout = Duration(seconds: 15);

  late bool showConfigButton = widget.showConfigButton;

  Map<String, dynamic>? _infoData;
  Map<String, dynamic>? _infoDevice;

  String? _infoError;
  String? _deviceError;

  bool _loadingInfo = true;
  bool _loadingDevice = true;

  // ── Input/Output ที่ ESP32 กำลังใช้งานอยู่ (จาก /api/mode) ──
  String _currentInput = 'rs485';
  final Set<String> _enabledOutputs = {'api'};
  bool _loadingMode = true;
  bool _savingMode = false;
  String? _modeError;

  @override
  void initState() {
    super.initState();
    _baseUrl = widget.baseUrl;
    _loadInfo();
    _loadDevice();
    _loadMode();
  }

  Future<void> _loadInfo() async {
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
          _infoError = 'ดึงข้อมูลผิดพลาด (${res.statusCode})';
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
          _deviceError = 'ดึงข้อมูลผิดพลาด (${res.statusCode})';
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
    print(_baseUrl);
    await Future.wait([_loadInfo(), _loadDevice(), _loadMode()]);
  }

  // =====================================================
  // /api/mode — รู้ว่าตอนนี้ device ตั้ง Input เป็นอะไรอยู่ (rs485/tcp/...)
  // และ Output ตัวไหนเปิดไว้บ้าง (เอาไว้ preserve ตอนเปลี่ยน input โดยไม่แตะ output)
  // =====================================================
  Future<void> _loadMode() async {
    setState(() {
      _loadingMode = true;
      _modeError = null;
    });
    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/mode')).timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final outputs = (data['outputs'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .where((t) => _kAvailableOutputTypes.containsKey(t))
            .toSet();
        setState(() {
          _currentInput = data['input']?.toString() ?? 'rs485';
          _enabledOutputs
            ..clear()
            ..addAll(outputs.isEmpty ? {'api'} : outputs);
          _loadingMode = false;
        });
      } else {
        setState(() {
          _modeError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})';
          _loadingMode = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _modeError = 'หมดเวลาเชื่อมต่อ';
        _loadingMode = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modeError = 'เกิดข้อผิดพลาด: $e';
        _loadingMode = false;
      });
    }
  }

  // บันทึกทั้ง input + outputs ปัจจุบันไปที่ /api/mode ในคำสั่งเดียว — ทั้งการเปลี่ยน
  // input dropdown และการติ๊ก/ถอด checkbox output ใช้ฟังก์ชันนี้ร่วมกัน
  Future<void> _saveMode() async {
    setState(() => _savingMode = true);
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/api/mode'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({"input": _currentInput, "outputs": _enabledOutputs.toList()}),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      if (res.statusCode == 200 && data?['success'] == true) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("บันทึกแล้ว — ต้อง restart อุปกรณ์เพื่อให้มีผลจริง")));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ')));
      }
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('หมดเวลาเชื่อมต่อ')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    } finally {
      if (mounted) setState(() => _savingMode = false);
    }
  }

  Future<void> _changeInputType(String? newType) async {
    if (newType == null || newType == _currentInput) return;
    setState(() => _currentInput = newType);
    await _saveMode();
  }

  Future<void> _toggleOutput(String type, bool? enabled) async {
    if (enabled == null) return;
    final next = Set<String>.from(_enabledOutputs);
    if (enabled) {
      next.add(type);
    } else {
      next.remove(type);
    }
    if (next.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('ต้องเปิดใช้งาน Output อย่างน้อย 1 ชนิด')));
      return;
    }
    setState(() {
      _enabledOutputs
        ..clear()
        ..addAll(next);
    });
    await _saveMode();
  }

  void _openInputConfig() {
    Widget page;
    if (_currentInput == 'tcp') {
      page = TcpSetupPage(baseUrl: _baseUrl);
    } else if (_currentInput == 'can') {
      page = CanSetupPage(baseUrl: _baseUrl);
    } else if (_currentInput == 'io') {
      page = IoSetupPage(baseUrl: _baseUrl);
    } else {
      page = Rs485SetupPage(baseUrl: _baseUrl);
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _openOutputConfig() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => OutputSetupPage(baseUrl: _baseUrl)));
  }

  // CAN ใช้ bus (pin/bitrate) และ TX mapping ร่วมกันในหน้าเดียว (CanSetupPage) ไม่ว่าจะเปิด
  // ใช้เป็น Input, Output, หรือทั้งคู่ — ปุ่มนี้เป็นทางเข้าสำรองสำหรับกรณีที่ Input ปัจจุบัน
  // ไม่ใช่ "can" (เช่น input=rs485) แต่เปิด output "can" ไว้ ซึ่งปุ่ม "Config Input" ด้านบน
  // จะพาไปหน้า RS485/TCP แทน เข้าไม่ถึงหน้า CAN — จึงต้องมีทางเข้าตรงนี้เพิ่ม
  void _openCanOutputConfig() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => CanSetupPage(baseUrl: _baseUrl)));
  }

  // io เป็น output-only type (ไม่มีทาง active เป็น input ได้ ต่างจาก can) จึงไม่มีทาง
  // เข้าถึงผ่านปุ่ม "Config Input" เลย ต้องมีทางเข้าตรงนี้เสมอเมื่อเปิดใช้งาน "io" ไว้
  void _openIoOutputConfig() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => IoSetupPage(baseUrl: _baseUrl)));
  }

  // =====================================================
  // Build
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
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

              // ── ปุ่มตามสถานะ WiFi mode ──────────────────────
              if (_infoData?['mode'] == "AP") ...[
                _buildWifiConnectionButton(),
                ListTile(
                  leading: const Icon(Icons.restart_alt, color: Colors.orange),
                  title: const Text("Restart อุปกรณ์"),
                  subtitle: const Text("รีสตาร์ทใหม่ ไม่ล้างค่าที่ตั้งไว้"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _restartDevice,
                ),
              ] else ...[
                // ปุ่ม config — แสดงเฉพาะ STA mode (เชื่อม router แล้ว)
                if (showConfigButton) ...[
                  _buildInputTypeCard(),
                  const SizedBox(height: 8),
                  _buildConfigButton(
                    icon: Icons.settings_input_component,
                    label: "Config ${_kAvailableInputTypes[_currentInput] ?? _currentInput} Input",
                    onTap: _openInputConfig,
                  ),
                  const SizedBox(height: 16),
                  _buildOutputTypeCard(),
                  const SizedBox(height: 8),
                  _buildConfigButton(
                    icon: Icons.settings_input_antenna,
                    label: "Config Output",
                    onTap: _openOutputConfig,
                  ),
                  const SizedBox(height: 8),
                  // LoRa input ยังเป็น TODO ฝั่ง firmware (poll() คืน false เสมอ) — เพิ่มปุ่ม
                  // config ให้ตอนที่ implement Input class เสร็จแล้ว (IOInput ก็ยังเป็น TODO
                  // เหมือนกัน แต่ IOOutput implement แล้ว จึงมีปุ่ม Config ด้านล่างนี้ให้)

                  // ปุ่มสำรองสำหรับตั้งค่า CAN Bus (TX mapping + bus settings) เมื่อเปิดใช้
                  // "CAN" เป็น Output แต่ Input ปัจจุบันไม่ใช่ "can" (ปุ่ม Config Input ด้านบน
                  // จะพาไปหน้า Input ของ input ปัจจุบันแทน เข้าไม่ถึงหน้า CAN)
                  if (_enabledOutputs.contains('can') && _currentInput != 'can') ...[
                    _buildConfigButton(
                      icon: Icons.settings_input_hdmi,
                      label: "Config CAN Bus Output",
                      onTap: _openCanOutputConfig,
                    ),
                    const SizedBox(height: 8),
                  ],

                  // ปุ่มสำรองสำหรับตั้งค่า IO (input mapping + output rules อยู่หน้าเดียวกันใน
                  // IoSetupPage) เมื่อเปิดใช้ "io" เป็น Output แต่ Input ปัจจุบันไม่ใช่ "io" —
                  // เหตุผลเดียวกับปุ่ม CAN ด้านบน (ปุ่ม Config Input จะพาไปหน้า Input ปัจจุบันแทน)
                  if (_enabledOutputs.contains('io') && _currentInput != 'io') ...[
                    _buildConfigButton(icon: Icons.toggle_on, label: "Config IO Output", onTap: _openIoOutputConfig),
                    const SizedBox(height: 8),
                  ],
                ],
                _buildMaintenanceCard(),
                const SizedBox(height: 16),
                // _buildLogoutButton(),
              ],
              _buildLogoutButton(),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // Widgets
  // =====================================================
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
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.edit, size: 16),
                  tooltip: "แก้ไขชื่ออุปกรณ์",
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

  Widget _buildOutputTypeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Output ที่เปิดใช้งาน", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              "เลือกได้มากกว่า 1 อย่างพร้อมกัน ไม่ผูกกับ Input ที่เลือกไว้ด้านบน — "
              "ตั้งค่ารายละเอียดของแต่ละตัว (URL/Host/Topic ฯลฯ) ได้ที่ปุ่ม \"Config Output\" ด้านล่าง "
              "บันทึกแล้วต้อง restart อุปกรณ์เพื่อให้มีผลจริง",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_loadingMode)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_savingMode) const LinearProgressIndicator(),
              ..._kAvailableOutputTypes.entries.map(
                (e) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  value: _enabledOutputs.contains(e.key),
                  onChanged: _savingMode ? null : (v) => _toggleOutput(e.key, v),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputTypeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ประเภท Input", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              "เลือกได้ทีละอย่าง (Input เป็น mutually exclusive) — บันทึกแล้วต้อง restart อุปกรณ์เพื่อให้มีผลจริง",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_loadingMode)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_modeError != null) ...[
                Text(_modeError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              DropdownButtonFormField<String>(
                initialValue: _kAvailableInputTypes.containsKey(_currentInput) ? _currentInput : null,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                hint: Text(_currentInput), // เผื่อ device ตั้งเป็น lora/io ที่แอปยังไม่รองรับหน้า config
                items: _kAvailableInputTypes.entries
                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                    .toList(),
                onChanged: _savingMode ? null : _changeInputType,
              ),
              if (_savingMode) ...[const SizedBox(height: 8), const LinearProgressIndicator()],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConfigButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return Card(
      child: ListTile(leading: Icon(icon), title: Text(label), trailing: const Icon(Icons.chevron_right), onTap: onTap),
    );
  }

  // =====================================================
  // Maintenance — Restart / Reset อุปกรณ์
  //   Restart  → POST /api/restart    รีบูตเฉย ๆ การตั้งค่าทั้งหมดยังอยู่
  //   Reset    → POST /api/reset_wifi ล้างค่า WiFi แล้วรีบูตกลับเข้าโหมด AP
  //              (การตั้งค่า Input/Output อื่น ๆ ไม่ถูกล้าง)
  // =====================================================
  Widget _buildMaintenanceCard() {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.restart_alt, color: Colors.orange),
            title: const Text("Restart อุปกรณ์"),
            subtitle: const Text("รีสตาร์ทใหม่ ไม่ล้างค่าที่ตั้งไว้"),
            trailing: const Icon(Icons.chevron_right),
            onTap: _restartDevice,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore, color: Colors.red),
            title: const Text("Reset อุปกรณ์"),
            subtitle: const Text("ล้างค่า WiFi แล้วกลับเข้าโหมด AP"),
            trailing: const Icon(Icons.chevron_right),
            onTap: _resetDevice,
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("ยกเลิก")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _restartDevice() async {
    final confirmed = await _confirmDialog(
      title: "Restart อุปกรณ์",
      message:
          "อุปกรณ์จะรีสตาร์ททันที การตั้งค่าทั้งหมดยังอยู่ครบ\n"
          "จะเสียการเชื่อมต่อชั่วคราวประมาณ 10-20 วินาที",
      confirmLabel: "Restart",
      confirmColor: Colors.orange,
    );
    if (confirmed != true || !mounted) return;
    try {
      final res = await http.post(Uri.parse('$_baseUrl/api/restart')).timeout(_timeout);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.statusCode == 200
                ? "สั่ง Restart แล้ว — รอสักครู่แล้วลากลงเพื่อโหลดใหม่"
                : "สั่ง Restart ไม่สำเร็จ (${res.statusCode})",
          ),
        ),
      );
    } on TimeoutException {
      // ESP32 อาจรีบูตก่อนตอบกลับ ถือว่าปกติ
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("สั่ง Restart แล้ว — อุปกรณ์กำลังรีบูต")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    }
  }

  Future<void> _resetDevice() async {
    final confirmed = await _confirmDialog(
      title: "Reset อุปกรณ์ (ล้างค่า WiFi)",
      message:
          "จะล้างค่า WiFi ที่บันทึกไว้แล้วรีสตาร์ท อุปกรณ์จะกลับเข้าโหมด AP "
          "ให้ตั้งค่าใหม่ผ่าน \"ESP32_Config\"\n\n"
          "การตั้งค่า Input/Output อื่น ๆ ยังอยู่",
      confirmLabel: "Reset",
      confirmColor: Colors.red,
    );
    if (confirmed != true || !mounted) return;
    try {
      final res = await http.post(Uri.parse('$_baseUrl/api/reset_wifi')).timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.statusCode == 200 && data?['success'] == true
                ? "Reset แล้ว — อุปกรณ์กำลังรีบูตเข้าโหมด AP"
                : "Reset ไม่สำเร็จ (${res.statusCode})",
          ),
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Reset แล้ว — อุปกรณ์กำลังรีบูตเข้าโหมด AP")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    }
  }

  Widget _buildLogoutButton() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.logout),
        title: const Text("Back to menu"),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MenuPage()),
          (route) => false,
        ),
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
          print("==== new IP ====");
          print(newIp ?? "no return IP");
          if (newIp == null || newIp.isEmpty || !mounted) return;
          setState(() {
            _baseUrl = 'http://$newIp';
            showConfigButton = true;
          });
          await _refreshAll();
        },
      ),
    );
  }

  // =====================================================
  // Edit device name dialog
  // =====================================================
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
                    if (value == null || value.trim().isEmpty) return 'กรุณากรอกชื่อ';
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
