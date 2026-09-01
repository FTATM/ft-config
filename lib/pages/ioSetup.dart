import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// =====================================================
// IoSetupPage — ตั้งค่า IO (GPIO) ทั้งหมดในหน้าเดียว: Input mapping (อ่าน digital/analog
// เข้ามาเป็น payload field) + Output rules (สั่ง digitalWrite ตามเงื่อนไข) — รวมหน้าเดียว
// แบบเดียวกับ CanSetupPage เพราะเป็น mapping table ทั้งคู่ ไม่ใช่ key-value ธรรมดา
// ต่างจาก CAN ตรงที่ pin ฝั่ง Input กับฝั่ง Output เป็นคนละขากันจริง (ไม่ใช่ controller
// เดียวกัน) จึงตั้งค่าอิสระจากกันได้เต็มที่ ไม่มีข้อจำกัดเรื่อง sharing เหมือน CAN bus
//
// Input:  ทุกรอบ poll interval จะ digitalRead()/analogRead() ตาม mapping แล้วส่งออกเป็น
//         payload field label นั้นๆ ให้ Output ทุกตัวที่เปิดไว้ (ต้องเลือก "IO" เป็น Input
//         Type ที่หน้า Dashboard ก่อน ถึงจะ active จริง — Input เลือกได้ทีละอย่างเท่านั้น)
// Output: ทุกครั้งที่ Input (ไม่ว่าจะเป็น RS485/TCP/CAN/IO) อ่านค่าได้ payload field ที่ label
//         ตรงกับ rule ด้านล่าง จะเทียบค่ากับ Threshold ตาม Comparator แล้วสั่งขา Pin ที่กำหนด
//         (ต้องเปิดใช้งาน "io" เป็น Output ที่หน้า Dashboard ก่อน)
//
// API paths:
//   GET/POST /api/input/io            ← poll_interval_ms
//   GET/POST /api/input/io/mappings   ← label -> pin/mode(digital|analog)/scale
//   POST     /api/input/io/poll_now   ← ทดสอบอ่านค่าตอนนี้ + ส่งออก output ที่เปิดไว้
//   GET/POST /api/output/io           ← label -> pin/comparator/threshold/active_high
// =====================================================
class IoSetupPage extends StatefulWidget {
  const IoSetupPage({super.key, this.baseUrl = 'http://192.168.4.1'});

  final String baseUrl;

  @override
  State<IoSetupPage> createState() => _IoSetupPageState();
}

class _IoInputRow {
  _IoInputRow({
    required String label,
    String pin = '',
    String mode = 'digital',
    String scale = '1',
  })  : labelController = TextEditingController(text: label),
        pinController = TextEditingController(text: pin),
        scaleController = TextEditingController(text: scale),
        mode = mode;

  final TextEditingController labelController;
  final TextEditingController pinController;
  final TextEditingController scaleController;
  String mode;

  void dispose() {
    labelController.dispose();
    pinController.dispose();
    scaleController.dispose();
  }
}

class _IoOutputRow {
  _IoOutputRow({
    required String label,
    String pin = '',
    String comparator = '>',
    String threshold = '0',
    bool activeHigh = true,
  })  : labelController = TextEditingController(text: label),
        pinController = TextEditingController(text: pin),
        thresholdController = TextEditingController(text: threshold),
        comparator = comparator,
        activeHigh = activeHigh;

  final TextEditingController labelController;
  final TextEditingController pinController;
  final TextEditingController thresholdController;
  String comparator;
  bool activeHigh;

  void dispose() {
    labelController.dispose();
    pinController.dispose();
    thresholdController.dispose();
  }
}

class _IoSetupPageState extends State<IoSetupPage> {
  static const _timeout = Duration(seconds: 5);
  static const _comparators = ['>', '<', '>=', '<=', '==', '!='];
  static const _inputModes = ['digital', 'analog'];

  // ── Input settings (poll interval) ──
  final _pollIntervalController = TextEditingController(text: '1000');
  bool _loadingInputSettings = true;
  bool _savingInputSettings = false;
  String? _inputSettingsError;

  // ── Input mapping ──
  final List<_IoInputRow> _inputRows = [];
  bool _loadingInputMappings = true;
  bool _savingInputMappings = false;
  String? _inputMappingsError;

  // ── Output rules ──
  final List<_IoOutputRow> _outputRows = [];
  bool _loadingOutputRules = true;
  bool _savingOutputRules = false;
  String? _outputRulesError;

  // ── Test (input) ──
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _pollIntervalController.dispose();
    for (final r in _inputRows) r.dispose();
    for (final r in _outputRows) r.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadInputSettings(),
      _loadInputMappings(),
      _loadOutputRules(),
    ]);
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  // =====================================================
  // API: /api/input/io  (poll interval)
  // =====================================================
  Future<void> _loadInputSettings() async {
    setState(() { _loadingInputSettings = true; _inputSettingsError = null; });
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/input/io')).timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _pollIntervalController.text = '${data['poll_interval_ms'] ?? 1000}';
        setState(() => _loadingInputSettings = false);
      } else {
        setState(() { _inputSettingsError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})'; _loadingInputSettings = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _inputSettingsError = 'หมดเวลาเชื่อมต่อ'; _loadingInputSettings = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _inputSettingsError = 'เกิดข้อผิดพลาด: $e'; _loadingInputSettings = false; });
    }
  }

  Future<void> _saveInputSettings() async {
    setState(() => _savingInputSettings = true);
    final body = {
      "poll_interval_ms": int.tryParse(_pollIntervalController.text.trim()) ?? 1000,
    };
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/input/io'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึกการตั้งค่า IO Input สำเร็จ'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingInputSettings = false);
    }
  }

  // =====================================================
  // API: /api/input/io/mappings
  // =====================================================
  Future<void> _loadInputMappings() async {
    setState(() { _loadingInputMappings = true; _inputMappingsError = null; });
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/input/io/mappings')).timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        for (final r in _inputRows) r.dispose();
        _inputRows.clear();
        data.forEach((label, value) {
          final v = value as Map<String, dynamic>;
          _inputRows.add(_IoInputRow(
            label: label,
            pin:   '${v['pin'] ?? -1}',
            mode:  v['mode']?.toString() ?? 'digital',
            scale: '${v['scale'] ?? 1}',
          ));
        });
        setState(() => _loadingInputMappings = false);
      } else {
        setState(() { _inputMappingsError = 'โหลด mapping ไม่สำเร็จ (${res.statusCode})'; _loadingInputMappings = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _inputMappingsError = 'หมดเวลาเชื่อมต่อ'; _loadingInputMappings = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _inputMappingsError = 'เกิดข้อผิดพลาด: $e'; _loadingInputMappings = false; });
    }
  }

  Future<void> _saveInputMappings() async {
    setState(() => _savingInputMappings = true);
    final Map<String, dynamic> body = {};
    for (final row in _inputRows) {
      final label = row.labelController.text.trim();
      if (label.isEmpty) continue;
      body[label] = {
        "pin":   int.tryParse(row.pinController.text.trim()) ?? -1,
        "mode":  row.mode,
        "scale": double.tryParse(row.scaleController.text.trim()) ?? 1.0,
      };
    }
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/input/io/mappings'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึก Input Mapping สำเร็จ (${body.length} รายการ)'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingInputMappings = false);
    }
  }

  void _addInputRow() => setState(() => _inputRows.add(_IoInputRow(label: '')));
  void _removeInputRow(int index) => setState(() => _inputRows.removeAt(index).dispose());

  // =====================================================
  // API: POST /api/input/io/poll_now
  // =====================================================
  Future<void> _testPollNow() async {
    setState(() { _testing = true; _testResult = null; });
    try {
      final res = await http
          .post(Uri.parse('${widget.baseUrl}/api/input/io/poll_now'))
          .timeout(const Duration(seconds: 10));
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
  // API: /api/output/io
  // =====================================================
  Future<void> _loadOutputRules() async {
    setState(() { _loadingOutputRules = true; _outputRulesError = null; });
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/output/io')).timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        for (final r in _outputRows) r.dispose();
        _outputRows.clear();
        data.forEach((label, value) {
          final v = value as Map<String, dynamic>;
          _outputRows.add(_IoOutputRow(
            label:      label,
            pin:        '${v['pin'] ?? -1}',
            comparator: v['comparator']?.toString() ?? '>',
            threshold:  '${v['threshold'] ?? 0}',
            activeHigh: v['active_high'] != false,
          ));
        });
        setState(() => _loadingOutputRules = false);
      } else {
        setState(() { _outputRulesError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})'; _loadingOutputRules = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _outputRulesError = 'หมดเวลาเชื่อมต่อ'; _loadingOutputRules = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _outputRulesError = 'เกิดข้อผิดพลาด: $e'; _loadingOutputRules = false; });
    }
  }

  Future<void> _saveOutputRules() async {
    setState(() => _savingOutputRules = true);
    final Map<String, dynamic> body = {};
    for (final row in _outputRows) {
      final label = row.labelController.text.trim();
      if (label.isEmpty) continue;
      body[label] = {
        "pin":         int.tryParse(row.pinController.text.trim()) ?? -1,
        "comparator":  row.comparator,
        "threshold":   double.tryParse(row.thresholdController.text.trim()) ?? 0.0,
        "active_high": row.activeHigh,
      };
    }
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/output/io'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึก Output Rule สำเร็จ (${body.length} รายการ) — มีผลทันทีโดยไม่ต้อง restart'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingOutputRules = false);
    }
  }

  void _addOutputRow() => setState(() => _outputRows.add(_IoOutputRow(label: '')));
  void _removeOutputRow(int index) => setState(() => _outputRows.removeAt(index).dispose());

  // =====================================================
  // Build
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ตั้งค่า IO (GPIO)"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll)],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildInputSettingsCard(),
            const SizedBox(height: 16),
            _buildInputMappingCard(),
            const SizedBox(height: 16),
            _buildTestCard(),
            const SizedBox(height: 16),
            _buildOutputRulesCard(),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // Card widgets
  // =====================================================
  Widget _buildInputSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Input — การอ่านค่า", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              "ต้องเลือก \"IO\" เป็น Input Type ที่หน้า Dashboard ก่อน mapping ด้านล่างถึงจะ active จริง",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_loadingInputSettings)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_inputSettingsError != null) ...[
                Text(_inputSettingsError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              TextField(controller: _pollIntervalController, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Poll Interval (ms)", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingInputSettings ? null : _saveInputSettings,
                  icon: _savingInputSettings
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

  Widget _buildInputMappingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Input Mapping (อ่านค่าเข้า)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(icon: const Icon(Icons.add_circle), tooltip: "เพิ่มแถว", onPressed: _addInputRow),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              "digital = digitalRead() คืน 0/1, analog = analogRead() คืนค่าดิบ 0-4095 — คูณด้วย "
              "Scale เพื่อแปลงหน่วย เช่น scale = 3.3/4095 แปลง analog เป็นโวลต์",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (_loadingInputMappings)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_inputMappingsError != null) ...[
                Text(_inputMappingsError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              if (_inputRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text("ยังไม่มี mapping — กด + เพื่อเพิ่ม", style: TextStyle(color: Colors.grey)),
                ),
              ..._inputRows.asMap().entries.map((e) => _buildInputRow(e.value, onRemove: () => _removeInputRow(e.key))),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingInputMappings ? null : _saveInputMappings,
                  icon: _savingInputMappings
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึก Mapping ทั้งหมด"),
                )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputRow(_IoInputRow row, {required VoidCallback onRemove}) {
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
                  decoration: const InputDecoration(labelText: "Label", hintText: "door_sensor", isDense: true))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: row.pinController, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Pin", hintText: "34", isDense: true))),
              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: onRemove),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: row.mode, isExpanded: true,
                decoration: const InputDecoration(labelText: "Mode", isDense: true),
                items: _inputModes.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setState(() => row.mode = v ?? 'digital'),
              )),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: row.scaleController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: "Scale", isDense: true))),
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
              "อ่านค่า GPIO ตาม Input Mapping ด้านบนทันที แล้วส่งออกไปยัง Output ทุกตัวที่เปิดใช้งานไว้ "
              "(ตั้งค่าที่หน้า Dashboard) — ทดสอบได้แม้ Input Type ปัจจุบันจะไม่ใช่ \"IO\" ก็ตาม",
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

  Widget _buildOutputRulesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Output Rules (เขียนค่าออก)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(icon: const Icon(Icons.add_circle), tooltip: "เพิ่ม rule", onPressed: _addOutputRow),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              "ทุกครั้งที่ Input อ่านค่าได้ payload field ที่ label ตรงกับ rule นี้ จะเทียบค่ากับ Threshold "
              "ตาม Comparator แล้วสั่งขา Pin ที่กำหนด — ต้องเปิดใช้งาน \"io\" เป็น Output ที่หน้า Dashboard ก่อน",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (_loadingOutputRules)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_outputRulesError != null) ...[
                Text(_outputRulesError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              if (_outputRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text("ยังไม่มี rule — กด + เพื่อเพิ่ม", style: TextStyle(color: Colors.grey)),
                ),
              ..._outputRows.asMap().entries.map((e) => _buildOutputRow(e.value, onRemove: () => _removeOutputRow(e.key))),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingOutputRules ? null : _saveOutputRules,
                  icon: _savingOutputRules
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึก Rule ทั้งหมด"),
                )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOutputRow(_IoOutputRow row, {required VoidCallback onRemove}) {
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
              Expanded(flex: 2, child: TextField(controller: row.pinController, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Pin", hintText: "25", isDense: true))),
              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: onRemove),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: row.comparator, isExpanded: true,
                decoration: const InputDecoration(labelText: "Comparator", isDense: true),
                items: _comparators.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => row.comparator = v ?? '>'),
              )),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: row.thresholdController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: "Threshold", isDense: true))),
            ]),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text("Active High (ปิด = relay active-low)", style: TextStyle(fontSize: 12)),
              value: row.activeHigh,
              onChanged: (v) => setState(() => row.activeHigh = v ?? true),
            ),
          ],
        ),
      ),
    );
  }
}
