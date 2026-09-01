import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// =====================================================
// CanSetupPage — ตั้งค่า CAN Bus (TWAI) ทั้งหมดในหน้าเดียว: bus settings (pin/bitrate) +
// RX frame mapping (สำหรับใช้เป็น Input) + TX frame mapping (สำหรับใช้เป็น Output)
//
// ต่างจาก RS485/TCP ที่แยกหน้า Input กับหน้า Output ออกจากกันชัดเจน (เพราะเป็นคนละ
// UART/socket กันจริงๆ) — CAN ต้องรวมไว้หน้าเดียว เพราะ ESP32 มี TWAI controller ตัวเดียว
// บน chip เดียว ไม่ว่าจะเปิดใช้ CAN เป็น Input, Output, หรือทั้งคู่พร้อมกัน ก็คือสาย CAN
// เส้นเดียวกันจริงๆ ทางฟิสิคัล (ตั้ง tx_pin/rx_pin/bitrate ซ้ำกันจากสองหน้าไม่มีประโยชน์
// แถมสับสน) — ดู comment เหนือ handleGetCANBus ในฝั่ง WebAPI.cpp ประกอบ
//
// การเลือก/เปิดปิด "CAN" เป็น Output ทำที่หน้า Dashboard (ผ่าน /api/mode) เหมือน output
// อื่นๆ ตามปกติ — หน้านี้แค่ตั้งรายละเอียด bus + frame mapping เท่านั้น
//
// API paths:
//   GET/POST /api/input/can            ← bus settings (tx_pin/rx_pin/bitrate/listen_only/poll_interval_ms)
//   GET/POST /api/input/can/frames     ← RX mapping: CAN ID -> label (ใช้ตอนเป็น Input)
//   GET/POST /api/output/can/frames    ← TX mapping: label -> CAN ID (ใช้ตอนเป็น Output)
//   POST     /api/input/can/poll_now   ← ทดสอบอ่านค่าที่ cache ไว้ล่าสุด + ส่งออก output ที่เปิดไว้
// =====================================================
class CanSetupPage extends StatefulWidget {
  const CanSetupPage({super.key, this.baseUrl = 'http://192.168.4.1'});

  final String baseUrl;

  @override
  State<CanSetupPage> createState() => _CanSetupPageState();
}

// แถวของ frame mapping หนึ่งรายการ (label <-> CAN ID + byte offset + type + scale) —
// ใช้ร่วมกันทั้ง RX (input) และ TX (output) เพราะโครงข้อมูลเหมือนกันทุกฟิลด์
//
// requestId/requestData/requestExtended มีความหมายเฉพาะฝั่ง RX (Input) เท่านั้น — สำหรับ
// sensor แบบ request-response ที่ต้องส่ง request ไปถามก่อนถึงจะตอบ (เว้นว่าง requestId ไว้ =
// โหมด broadcast/listen ปกติ) ฝั่ง TX (Output) จะไม่แสดง field กลุ่มนี้ในหน้า UI เลย
class _CanFrameRow {
  _CanFrameRow({
    required String label,
    required String id,
    bool extended = false,
    String byteOffset = '0',
    String type = 'uint8',
    String scale = '1',
    bool bigEndian = false,
    String requestId = '',
    String requestData = '',
    bool requestExtended = false,
  })  : labelController = TextEditingController(text: label),
        idController = TextEditingController(text: id),
        byteOffsetController = TextEditingController(text: byteOffset),
        scaleController = TextEditingController(text: scale),
        requestIdController = TextEditingController(text: requestId),
        requestDataController = TextEditingController(text: requestData),
        extended = extended,
        type = type,
        bigEndian = bigEndian,
        requestExtended = requestExtended;

  final TextEditingController labelController;
  final TextEditingController idController;
  final TextEditingController byteOffsetController;
  final TextEditingController scaleController;
  final TextEditingController requestIdController;
  final TextEditingController requestDataController;
  bool extended;
  String type;
  bool bigEndian;
  bool requestExtended;

  void dispose() {
    labelController.dispose();
    idController.dispose();
    byteOffsetController.dispose();
    scaleController.dispose();
    requestIdController.dispose();
    requestDataController.dispose();
  }
}

class _CanSetupPageState extends State<CanSetupPage> {
  static const _timeout = Duration(seconds: 5);
  static const _dataTypes = ['uint8', 'int8', 'uint16', 'int16', 'uint32', 'int32', 'float32'];
  static const _bitrates = [125000, 250000, 500000, 1000000];

  // ── Bus settings (tx_pin/rx_pin/bitrate/listen_only/poll_interval_ms) ──
  final _txPinController = TextEditingController();
  final _rxPinController = TextEditingController();
  final _pollIntervalController = TextEditingController();
  final _requestTimeoutController = TextEditingController();
  int _bitrate = 500000;
  bool _listenOnly = false;
  bool _loadingBus = true;
  bool _savingBus = false;
  String? _busError;

  // ── RX frame mapping (ใช้ตอนเป็น Input) ──
  final List<_CanFrameRow> _rxFrameRows = [];
  bool _loadingRxFrames = true;
  bool _savingRxFrames = false;
  String? _rxFramesError;

  // ── TX frame mapping (ใช้ตอนเป็น Output) ──
  final List<_CanFrameRow> _txFrameRows = [];
  bool _loadingTxFrames = true;
  bool _savingTxFrames = false;
  String? _txFramesError;

  // ── Test ──
  bool _testing = false;
  String? _testResult;

  // ── Bus status (debug) ──
  Map<String, dynamic>? _busStatus;
  bool _loadingStatus = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _txPinController.dispose();
    _rxPinController.dispose();
    _pollIntervalController.dispose();
    _requestTimeoutController.dispose();
    for (final r in _rxFrameRows) r.dispose();
    for (final r in _txFrameRows) r.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadBusSettings(),
      _loadRxFrames(),
      _loadTxFrames(),
    ]);
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  // =====================================================
  // API: /api/input/can  (bus settings — ใช้ endpoint เดียวกับที่ /api/output/can ชี้ไปหา)
  // =====================================================
  Future<void> _loadBusSettings() async {
    setState(() { _loadingBus = true; _busError = null; });
    try {
      final res = await http
          .get(Uri.parse('${widget.baseUrl}/api/input/can'))
          .timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _txPinController.text = '${data['tx_pin'] ?? 5}';
        _rxPinController.text = '${data['rx_pin'] ?? 4}';
        _pollIntervalController.text = '${data['poll_interval_ms'] ?? 200}';
        _requestTimeoutController.text = '${data['request_timeout_ms'] ?? 200}';
        setState(() {
          _bitrate = int.tryParse('${data['bitrate'] ?? 500000}') ?? 500000;
          _listenOnly = data['listen_only'] == true;
          _loadingBus = false;
        });
      } else {
        setState(() { _busError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})'; _loadingBus = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _busError = 'หมดเวลาเชื่อมต่อ'; _loadingBus = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _busError = 'เกิดข้อผิดพลาด: $e'; _loadingBus = false; });
    }
  }

  Future<void> _saveBusSettings() async {
    setState(() => _savingBus = true);
    final body = {
      "tx_pin":             int.tryParse(_txPinController.text.trim())            ?? 5,
      "rx_pin":             int.tryParse(_rxPinController.text.trim())            ?? 4,
      "bitrate":            _bitrate,
      "listen_only":        _listenOnly,
      "poll_interval_ms":   int.tryParse(_pollIntervalController.text.trim())     ?? 200,
      "request_timeout_ms": int.tryParse(_requestTimeoutController.text.trim())   ?? 200,
    };
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/input/can'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึกการตั้งค่า CAN Bus สำเร็จ — ตั้งใหม่มีผลทันทีโดยไม่ต้อง restart'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingBus = false);
    }
  }

  // =====================================================
  // แปลง Map<String, dynamic> (จาก /frames) <-> List<_CanFrameRow>
  // =====================================================
  List<_CanFrameRow> _parseFrames(Map<String, dynamic> data) {
    final rows = <_CanFrameRow>[];
    data.forEach((label, value) {
      final v = value as Map<String, dynamic>;
      rows.add(_CanFrameRow(
        label:           label,
        id:              v['id']?.toString()          ?? '',
        extended:        v['extended'] == true,
        byteOffset:      '${v['byte_offset']           ?? 0}',
        type:            v['type']?.toString()        ?? 'uint8',
        scale:           '${v['scale']                 ?? 1}',
        bigEndian:       v['big_endian'] == true,
        requestId:       v['request_id']?.toString()   ?? '',
        requestData:     v['request_data']?.toString() ?? '',
        requestExtended: v['request_extended'] == true,
      ));
    });
    return rows;
  }

  Map<String, dynamic> _encodeFrames(List<_CanFrameRow> rows) {
    final Map<String, dynamic> body = {};
    for (final row in rows) {
      final label = row.labelController.text.trim();
      final id = row.idController.text.trim();
      if (label.isEmpty || id.isEmpty) continue;
      body[label] = {
        "id":               id,
        "extended":         row.extended,
        "byte_offset":      int.tryParse(row.byteOffsetController.text.trim()) ?? 0,
        "type":             row.type,
        "scale":            double.tryParse(row.scaleController.text.trim()) ?? 1.0,
        "big_endian":       row.bigEndian,
        "request_id":       row.requestIdController.text.trim(),
        "request_data":     row.requestDataController.text.trim(),
        "request_extended": row.requestExtended,
      };
    }
    return body;
  }

  // =====================================================
  // API: /api/input/can/frames  (RX mapping)
  // =====================================================
  Future<void> _loadRxFrames() async {
    setState(() { _loadingRxFrames = true; _rxFramesError = null; });
    try {
      final res = await http
          .get(Uri.parse('${widget.baseUrl}/api/input/can/frames'))
          .timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        for (final r in _rxFrameRows) r.dispose();
        _rxFrameRows
          ..clear()
          ..addAll(_parseFrames(data));
        setState(() => _loadingRxFrames = false);
      } else {
        setState(() { _rxFramesError = 'โหลด mapping ไม่สำเร็จ (${res.statusCode})'; _loadingRxFrames = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _rxFramesError = 'หมดเวลาเชื่อมต่อ'; _loadingRxFrames = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _rxFramesError = 'เกิดข้อผิดพลาด: $e'; _loadingRxFrames = false; });
    }
  }

  Future<void> _saveRxFrames() async {
    setState(() => _savingRxFrames = true);
    final body = _encodeFrames(_rxFrameRows);
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/input/can/frames'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึก RX mapping สำเร็จ (${body.length} รายการ)'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingRxFrames = false);
    }
  }

  void _addRxFrameRow() => setState(() => _rxFrameRows.add(_CanFrameRow(label: '', id: '')));
  void _removeRxFrameRow(int index) => setState(() => _rxFrameRows.removeAt(index).dispose());

  // =====================================================
  // API: /api/output/can/frames  (TX mapping)
  // =====================================================
  Future<void> _loadTxFrames() async {
    setState(() { _loadingTxFrames = true; _txFramesError = null; });
    try {
      final res = await http
          .get(Uri.parse('${widget.baseUrl}/api/output/can/frames'))
          .timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        for (final r in _txFrameRows) r.dispose();
        _txFrameRows
          ..clear()
          ..addAll(_parseFrames(data));
        setState(() => _loadingTxFrames = false);
      } else {
        setState(() { _txFramesError = 'โหลด mapping ไม่สำเร็จ (${res.statusCode})'; _loadingTxFrames = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _txFramesError = 'หมดเวลาเชื่อมต่อ'; _loadingTxFrames = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _txFramesError = 'เกิดข้อผิดพลาด: $e'; _loadingTxFrames = false; });
    }
  }

  Future<void> _saveTxFrames() async {
    setState(() => _savingTxFrames = true);
    final body = _encodeFrames(_txFrameRows);
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/output/can/frames'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึก TX mapping สำเร็จ (${body.length} รายการ)'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingTxFrames = false);
    }
  }

  void _addTxFrameRow() => setState(() => _txFrameRows.add(_CanFrameRow(label: '', id: '')));
  void _removeTxFrameRow(int index) => setState(() => _txFrameRows.removeAt(index).dispose());

  // =====================================================
  // API: POST /api/input/can/poll_now
  // =====================================================
  Future<void> _testPollNow() async {
    setState(() { _testing = true; _testResult = null; });
    try {
      final res = await http
          .post(Uri.parse('${widget.baseUrl}/api/input/can/poll_now'))
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
  // API: GET /api/input/can/status — debug ตอนบัส "เงียบ" ไม่มีอะไรรับ/ส่งได้เลย
  // =====================================================
  Future<void> _loadBusStatus() async {
    setState(() => _loadingStatus = true);
    try {
      final res = await http
          .get(Uri.parse('${widget.baseUrl}/api/input/can/status'))
          .timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() => _busStatus = jsonDecode(res.body) as Map<String, dynamic>);
      } else {
        _showMessage('โหลดสถานะบัสไม่สำเร็จ (${res.statusCode})');
      }
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _loadingStatus = false);
    }
  }

  // =====================================================
  // Build
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ตั้งค่า CAN Bus"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll)],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildBusSettingsCard(),
            const SizedBox(height: 16),
            _buildFramesCard(
              title: "RX Mapping (Input — อ่านค่าเข้า)",
              helperText:
                  "รับ frame จาก CAN ID ที่กำหนด แล้วถอดค่าที่ byte offset ที่ตั้งไว้ออกมาเป็น label นี้ "
                  "ถ้า sensor ต้องถูก \"ถาม\" ก่อนถึงจะตอบ ให้ตั้ง Request ID + Request Data ด้วย "
                  "(เว้นว่างไว้ = sensor broadcast ค่าออกมาเอง ไม่ต้องถาม)",
              rows: _rxFrameRows,
              loading: _loadingRxFrames,
              saving: _savingRxFrames,
              error: _rxFramesError,
              isInput: true,
              onAdd: _addRxFrameRow,
              onRemove: _removeRxFrameRow,
              onSave: _saveRxFrames,
            ),
            const SizedBox(height: 16),
            _buildFramesCard(
              title: "TX Mapping (Output — เขียนค่าออก)",
              helperText:
                  "field label ใน payload ที่ตรงกับชื่อนี้จะถูกเข้ารหัสใส่ byte offset ที่กำหนด "
                  "แล้วส่งออกเป็น frame ของ CAN ID นี้ (หลาย label ผสมกันใน id เดียวกันได้)",
              rows: _txFrameRows,
              loading: _loadingTxFrames,
              saving: _savingTxFrames,
              error: _txFramesError,
              isInput: false,
              onAdd: _addTxFrameRow,
              onRemove: _removeTxFrameRow,
              onSave: _saveTxFrames,
            ),
            const SizedBox(height: 16),
            _buildTestCard(),
            const SizedBox(height: 16),
            _buildStatusCard(),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // Card widgets
  // =====================================================
  Widget _buildBusSettingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("การเชื่อมต่อ CAN Bus", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              "ตั้งค่านี้ใช้ร่วมกันทั้ง Input และ Output เพราะ ESP32 มี CAN controller ตัวเดียว "
              "(สายเส้นเดียวกันจริงๆ) ต้องต่อ CAN transceiver (เช่น SN65HVD230) ก่อนใช้งานจริง",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_loadingBus)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_busError != null) ...[
                Text(_busError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Expanded(child: TextField(controller: _txPinController, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "TX Pin", border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _rxPinController, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "RX Pin", border: OutlineInputBorder()))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: DropdownButtonFormField<int>(
                  initialValue: _bitrate,
                  decoration: const InputDecoration(labelText: "Bitrate", border: OutlineInputBorder()),
                  items: _bitrates
                      .map((b) => DropdownMenuItem(value: b, child: Text('${b ~/ 1000} kbps')))
                      .toList(),
                  onChanged: (v) => setState(() => _bitrate = v ?? 500000),
                )),
                const SizedBox(width: 8),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text("Listen Only", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Checkbox(value: _listenOnly, onChanged: (v) => setState(() => _listenOnly = v ?? false)),
                ]),
              ]),
              if (_listenOnly) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Text(
                    "⚠ Listen Only เปิดอยู่ — จะฟังได้อย่างเดียว ส่งอะไรออกบัสไม่ได้เลย "
                    "(request-response และ TX Mapping ทั้งหมดจะไม่ทำงาน) ปิดก่อนถ้าต้องการส่ง",
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(controller: _pollIntervalController, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Poll Interval (ms)",
                    helperText: "ความถี่ในการดูด RX queue มา decode (ใช้เฉพาะฝั่ง Input)",
                    border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _requestTimeoutController, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Request Timeout (ms)",
                    helperText: "เวลารอ response ต่อ request หนึ่งครั้ง (เฉพาะ label ที่ตั้ง Request ID ไว้ — "
                        "ไม่ตอบภายในเวลานี้จะข้ามไปเลย ไม่ retry)",
                    border: OutlineInputBorder())),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingBus ? null : _saveBusSettings,
                  icon: _savingBus
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึกการตั้งค่า Bus"),
                )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFramesCard({
    required String title,
    required String helperText,
    required List<_CanFrameRow> rows,
    required bool loading,
    required bool saving,
    required String? error,
    required bool isInput,
    required VoidCallback onAdd,
    required void Function(int) onRemove,
    required VoidCallback onSave,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                IconButton(icon: const Icon(Icons.add_circle), tooltip: "เพิ่มแถว", onPressed: onAdd),
              ],
            ),
            const SizedBox(height: 4),
            Text(helperText, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (error != null) ...[
                Text(error, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text("ยังไม่มี mapping — กด + เพื่อเพิ่ม", style: TextStyle(color: Colors.grey)),
                ),
              ...rows.asMap().entries.map((e) => _buildFrameRow(e.key, e.value, isInput: isInput, onRemove: () => onRemove(e.key))),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: saving
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

  Widget _buildFrameRow(int index, _CanFrameRow row, {required bool isInput, required VoidCallback onRemove}) {
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
                  decoration: const InputDecoration(labelText: "Label", hintText: "rpm", isDense: true))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextField(controller: row.idController,
                  decoration: const InputDecoration(labelText: "CAN ID", hintText: "0x123", isDense: true))),
              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: onRemove),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: row.type, isExpanded: true,
                decoration: const InputDecoration(labelText: "Type", isDense: true),
                items: _dataTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => row.type = v ?? 'uint8'),
              )),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: row.byteOffsetController, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Byte Offset", hintText: "0-7", isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: row.scaleController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: "Scale", isDense: true))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text("Extended ID (29-bit)", style: TextStyle(fontSize: 12)),
                  value: row.extended,
                  onChanged: (v) => setState(() => row.extended = v ?? false),
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text("Big Endian", style: TextStyle(fontSize: 12)),
                  value: row.bigEndian,
                  onChanged: (v) => setState(() => row.bigEndian = v ?? false),
                ),
              ),
            ]),
            if (isInput) ...[
              const Divider(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Request-Response (เว้นว่างถ้า sensor broadcast เองอยู่แล้ว)",
                  style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: TextField(controller: row.requestIdController,
                    decoration: const InputDecoration(
                        labelText: "Request ID", hintText: "0x200", isDense: true))),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: TextField(controller: row.requestDataController,
                    decoration: const InputDecoration(
                        labelText: "Request Data (hex)", hintText: "01 00", isDense: true))),
              ]),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text("Request ID เป็น Extended (29-bit)", style: TextStyle(fontSize: 12)),
                value: row.requestExtended,
                onChanged: (v) => setState(() => row.requestExtended = v ?? false),
              ),
            ],
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
              "อ่านค่าล่าสุดที่ ESP32 รับได้จากบัส CAN ตาม RX mapping ที่ตั้งไว้ แล้วส่งออกไปยัง "
              "Output ทุกตัวที่เปิดใช้งานไว้ (ตั้งค่าที่หน้า Dashboard/Config Output) — ถ้ายังไม่มี "
              "frame เข้ามาเลยตั้งแต่เปิดเครื่อง ปุ่มนี้จะไม่มีค่าให้อ่าน",
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

  Widget _buildStatusCard() {
    final status = _busStatus;
    final state = status?['state']?.toString();
    final isBusOff = state == 'BUS_OFF';
    final isRunning = state == 'RUNNING';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("สถานะบัส (Debug)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(icon: const Icon(Icons.refresh), tooltip: "รีเฟรช", onPressed: _loadBusStatus),
              ],
            ),
            const Text(
              "ใช้เช็คตอนที่ส่ง/รับอะไรไม่ได้เลย — ถ้า state เป็น BUS_OFF คือสัญญาณชัดเจนของ "
              "ปัญหา physical layer (สาย CAN_H/CAN_L สลับกัน, ไม่มี GND ร่วมระหว่างบอร์ด, "
              "bitrate ไม่ตรงกัน, ไม่มีตัวต้านทานปลายสาย 120Ω) ไม่ใช่ปัญหาที่ mapping/request",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_loadingStatus)
              const Center(child: CircularProgressIndicator())
            else if (status == null)
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loadBusStatus,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text("เช็คสถานะบัส"),
                ))
            else ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isBusOff ? Colors.red.shade50 : (isRunning ? Colors.green.shade50 : Colors.grey.shade100),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isBusOff ? Colors.red : (isRunning ? Colors.green : Colors.grey)),
                ),
                child: Row(children: [
                  Icon(isBusOff ? Icons.error : (isRunning ? Icons.check_circle : Icons.help_outline),
                      color: isBusOff ? Colors.red : (isRunning ? Colors.green : Colors.grey)),
                  const SizedBox(width: 8),
                  Text("State: ${state ?? '-'}", style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 16, runSpacing: 4, children: [
                Text("TX error: ${status['tx_error_count'] ?? '-'}"),
                Text("RX error: ${status['rx_error_count'] ?? '-'}"),
                Text("TX failed: ${status['tx_failed_count'] ?? '-'}"),
                Text("RX missed: ${status['rx_missed_count'] ?? '-'}"),
                Text("Bus error: ${status['bus_error_count'] ?? '-'}"),
              ]),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _loadBusStatus,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text("รีเฟรชอีกครั้ง"),
              ),
            ],
          ],
        ),
      ),
    );
  }
}