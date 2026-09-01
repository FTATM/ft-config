import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// =====================================================
// TcpSetupPage — ตั้งค่า Modbus TCP Input เท่านั้น: host/port/unit id + register map
//
// การเลือก/ตั้งค่า Output ไม่อยู่ในหน้านี้อีกต่อไป — ย้ายไปที่:
//   - เปิด/ปิด output ตัวไหน: หน้า Dashboard (ผ่าน /api/mode)
//   - ตั้งค่ารายละเอียดของแต่ละ output (url/host/topic ฯลฯ): outputSetup.dart
// โครงเดียวกับ Rs485SetupPage ทุกอย่าง ต่างแค่ "การเชื่อมต่อ" เป็น Host/Port แทน serial pin/baud
//
// API paths:
//   GET/POST /api/input/tcp
//   GET/POST /api/input/tcp/registers
//   POST     /api/input/tcp/poll_now  ← ทดสอบอ่านค่า + ส่งออกไปยัง output ที่เปิดไว้ทันที
// =====================================================
class TcpSetupPage extends StatefulWidget {
  const TcpSetupPage({super.key, this.baseUrl = 'http://192.168.4.1'});

  final String baseUrl;

  @override
  State<TcpSetupPage> createState() => _TcpSetupPageState();
}

class _RegisterRow {
  _RegisterRow({
    required String label,
    required String address,
    String type = 'uint16',
    String scale = '1',
    bool swapWords = false,
  })  : labelController = TextEditingController(text: label),
        addressController = TextEditingController(text: address),
        scaleController = TextEditingController(text: scale),
        type = type,
        swapWords = swapWords;

  final TextEditingController labelController;
  final TextEditingController addressController;
  final TextEditingController scaleController;
  String type;
  bool swapWords;

  void dispose() {
    labelController.dispose();
    addressController.dispose();
    scaleController.dispose();
  }
}

class _TcpSetupPageState extends State<TcpSetupPage> {
  static const _timeout = Duration(seconds: 15);
  static const _dataTypes = ['uint16', 'int16', 'uint32', 'int32', 'float32'];

  // ── TCP connection config ─────────────────────────
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '502');
  final _unitIdController = TextEditingController(text: '1');
  final _pollIntervalController = TextEditingController();
  int _functionCode = 3;
  bool _loadingConfig = true;
  bool _savingConfig = false;
  String? _configError;

  // ── Registers ─────────────────────────────────────
  final List<_RegisterRow> _registerRows = [];
  bool _loadingRegisters = true;
  bool _savingRegisters = false;
  String? _registersError;

  // ── Test ──────────────────────────────────────────
  bool _testing = false;
  String? _testResult;

  // ── Lifecycle ─────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _unitIdController.dispose();
    _pollIntervalController.dispose();
    for (final r in _registerRows) r.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadConfig(),
      _loadRegisters(),
    ]);
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  // =====================================================
  // API: /api/input/tcp  (host/port/unit id/function code)
  // =====================================================
  Future<void> _loadConfig() async {
    setState(() { _loadingConfig = true; _configError = null; });
    try {
      final res = await http
          .get(Uri.parse('${widget.baseUrl}/api/input/tcp'))
          .timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _hostController.text         = data['host']?.toString() ?? '';
        _portController.text         = '${data['port']              ?? 502}';
        _unitIdController.text       = '${data['unit_id']            ?? 1}';
        _pollIntervalController.text = '${data['poll_interval_ms']   ?? 5000}';
        setState(() {
          _functionCode = int.tryParse('${data['function_code'] ?? 3}') ?? 3;
          _loadingConfig = false;
        });
      } else {
        setState(() { _configError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})'; _loadingConfig = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _configError = 'หมดเวลาเชื่อมต่อ'; _loadingConfig = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _configError = 'เกิดข้อผิดพลาด: $e'; _loadingConfig = false; });
    }
  }

  Future<void> _saveConfig() async {
    if (_hostController.text.trim().isEmpty) {
      _showMessage('กรุณากรอก Host ของอุปกรณ์ Modbus TCP');
      return;
    }
    setState(() => _savingConfig = true);
    final body = {
      "host":              _hostController.text.trim(),
      "port":              int.tryParse(_portController.text.trim())         ?? 502,
      "unit_id":           int.tryParse(_unitIdController.text.trim())       ?? 1,
      "function_code":     _functionCode,
      "poll_interval_ms":  int.tryParse(_pollIntervalController.text.trim()) ?? 5000,
    };
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/input/tcp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึกการตั้งค่า Modbus TCP สำเร็จ'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingConfig = false);
    }
  }

  // =====================================================
  // API: /api/input/tcp/registers
  // =====================================================
  Future<void> _loadRegisters() async {
    setState(() { _loadingRegisters = true; _registersError = null; });
    try {
      final res = await http
          .get(Uri.parse('${widget.baseUrl}/api/input/tcp/registers'))
          .timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        for (final r in _registerRows) r.dispose();
        _registerRows.clear();
        data.forEach((label, value) {
          final v = value as Map<String, dynamic>;
          _registerRows.add(_RegisterRow(
            label:     label,
            address:   v['address']?.toString()  ?? '',
            type:      v['type']?.toString()     ?? 'uint16',
            scale:     '${v['scale']             ?? 1}',
            swapWords: v['swap_words'] == true,
          ));
        });
        setState(() => _loadingRegisters = false);
      } else {
        setState(() { _registersError = 'โหลด register ไม่สำเร็จ (${res.statusCode})'; _loadingRegisters = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _registersError = 'หมดเวลาเชื่อมต่อ'; _loadingRegisters = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _registersError = 'เกิดข้อผิดพลาด: $e'; _loadingRegisters = false; });
    }
  }

  Future<void> _saveRegisters() async {
    setState(() => _savingRegisters = true);
    final Map<String, dynamic> body = {};
    for (final row in _registerRows) {
      final label   = row.labelController.text.trim();
      final address = row.addressController.text.trim();
      if (label.isEmpty || address.isEmpty) continue;
      body[label] = {
        "address":    address,
        "type":       row.type,
        "scale":      double.tryParse(row.scaleController.text.trim()) ?? 1.0,
        "swap_words": row.swapWords,
      };
    }
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/input/tcp/registers'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึก Register สำเร็จ (${body.length} รายการ)'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingRegisters = false);
    }
  }

  void _addRegisterRow() => setState(() => _registerRows.add(_RegisterRow(label: '', address: '')));
  void _removeRegisterRow(int index) => setState(() => _registerRows.removeAt(index).dispose());

  // =====================================================
  // API: POST /api/input/tcp/poll_now
  // =====================================================
  Future<void> _testPollNow() async {
    setState(() { _testing = true; _testResult = null; });
    try {
      final res = await http
          .post(Uri.parse('${widget.baseUrl}/api/input/tcp/poll_now'))
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>?;
        if (data?['success'] == true) {
          final results = (data?['results'] as Map<String, dynamic>?) ?? {};
          final summary = results.entries
              .map((e) => '${e.key}: ${e.value == true ? "สำเร็จ" : "ไม่สำเร็จ"}')
              .join(', ');
          setState(() {
            _testResult = 'อ่านได้ ${data?['fields_read'] ?? 0} field'
                '${summary.isNotEmpty ? " → $summary" : " (ไม่มี output เปิดอยู่ — ไปเปิดที่หน้า Dashboard)"}';
          });
        } else {
          setState(() => _testResult = data?['message']?.toString() ?? 'ทดสอบไม่สำเร็จ');
        }
      } else {
        setState(() => _testResult = 'ทดสอบไม่สำเร็จ (${res.statusCode})');
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _testResult = 'หมดเวลารอผลทดสอบ');
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult = 'เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  // =====================================================
  // Build
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ตั้งค่า Modbus TCP"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll)],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildConnectionCard(),
            const SizedBox(height: 16),
            _buildRegistersCard(),
            const SizedBox(height: 16),
            _buildTestCard(),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // Card widgets
  // =====================================================

  Widget _buildConnectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("การเชื่อมต่อ Modbus TCP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              "เชื่อมต่อไปยังอุปกรณ์ Modbus TCP ผ่านเครือข่าย LAN เดียวกัน (เช่น PLC / gateway ที่รองรับ Modbus TCP)",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_loadingConfig)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_configError != null) ...[
                Text(_configError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Expanded(flex: 3, child: TextField(controller: _hostController,
                    decoration: const InputDecoration(labelText: "Host / IP อุปกรณ์", hintText: "192.168.1.100", border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _portController, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Port", hintText: "502", border: OutlineInputBorder()))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: _unitIdController, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Unit ID (Slave ID)", border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: DropdownButtonFormField<int>(
                  initialValue: _functionCode,
                  isExpanded:  true,
                  decoration: const InputDecoration(labelText: "Function Code", border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 3, child: Text("FC3 (Holding)")),
                    DropdownMenuItem(value: 4, child: Text("FC4 (Input)")),
                  ],
                  onChanged: (v) => setState(() => _functionCode = v ?? 3),
                )),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _pollIntervalController, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Poll Interval (ms)", helperText: "ความถี่ในการอ่านค่า+ส่งข้อมูลอัตโนมัติ",
                    border: OutlineInputBorder())),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingConfig ? null : _saveConfig,
                  icon: _savingConfig
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึกการตั้งค่า"),
                )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRegistersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Register Mapping", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(icon: const Icon(Icons.add_circle), tooltip: "เพิ่มแถว", onPressed: _addRegisterRow),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingRegisters)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_registersError != null) ...[
                Text(_registersError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              if (_registerRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text("ยังไม่มี register — กด + เพื่อเพิ่ม", style: TextStyle(color: Colors.grey)),
                ),
              ..._registerRows.asMap().entries.map((e) => _buildRegisterRow(e.key, e.value)),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingRegisters ? null : _saveRegisters,
                  icon: _savingRegisters
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึก Register ทั้งหมด"),
                )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterRow(int index, _RegisterRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Row(children: [
              Expanded(flex: 3, child: TextField(controller: row.labelController,
                  decoration: const InputDecoration(labelText: "Label", hintText: "temperature", isDense: true))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: row.addressController,
                  decoration: const InputDecoration(labelText: "Address", hintText: "M100", isDense: true))),
              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _removeRegisterRow(index)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: row.type, isExpanded: true,
                decoration: const InputDecoration(labelText: "Type", isDense: true),
                items: _dataTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => row.type = v ?? 'uint16'),
              )),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: row.scaleController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: "Scale", isDense: true))),
              const SizedBox(width: 8),
              Column(mainAxisSize: MainAxisSize.min, children: [
                const Text("Swap", style: TextStyle(fontSize: 11, color: Colors.grey)),
                Checkbox(value: row.swapWords, onChanged: (v) => setState(() => row.swapWords = v ?? false)),
              ]),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildTestCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ทดสอบ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            const Text(
              "สั่งให้ ESP32 อ่านค่าจาก Modbus TCP ตาม register ที่ตั้งไว้ทันที แล้วส่งออกไปยัง Output "
              "ทุกตัวที่เปิดใช้งานไว้ (ตั้งค่าที่หน้า Dashboard/Config Output) โดยไม่ต้องรอ interval",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _testing ? null : _testPollNow,
                icon: _testing
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(_testing ? "กำลังทดสอบ..." : "ทดสอบอ่านค่าตอนนี้"),
              )),
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              Text(_testResult!),
            ],
          ],
        ),
      ),
    );
  }
}
