import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// =====================================================
// OutputSetupPage — ตั้งค่ารายละเอียดของ Output ที่ "เปิดใช้งาน" ไว้แล้ว
// (เปิด/ปิด output ทำที่หน้า Dashboard ผ่าน /api/mode ไม่ใช่หน้านี้)
//
// หน้านี้ใช้ร่วมกันได้ไม่ว่า Input จะเป็น RS485, TCP, หรือชนิดอื่นในอนาคต — เพราะ
// output (HTTP/MQTT/App) เป็นอิสระจาก input โดยสิ้นเชิงตาม ModeConfig ฝั่ง ESP32
// (input เลือกได้ทีละอย่าง, output เปิดได้พร้อมกันหลายตัว)
//
// API paths:
//   GET      /api/mode                ← เอาไว้รู้ว่า output ตัวไหนเปิดอยู่ (read-only ในหน้านี้)
//   GET/POST /api/output/api
//   GET/POST /api/output/mqtt
//   GET      /api/output/app/latest   ← การ์ดผลลัพธ์ล่าสุด (ถ้าเปิด "App" ไว้)
// =====================================================
class OutputSetupPage extends StatefulWidget {
  const OutputSetupPage({super.key, this.baseUrl = 'http://192.168.4.1'});

  final String baseUrl;

  @override
  State<OutputSetupPage> createState() => _OutputSetupPageState();
}

class _HeaderRow {
  _HeaderRow({String key = '', String value = ''})
      : keyController = TextEditingController(text: key),
        valueController = TextEditingController(text: value);

  final TextEditingController keyController;
  final TextEditingController valueController;

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

// แถวของ "write map" (label -> register address) ใช้กับทั้ง RS485 output และ Modbus TCP
// output — ตั้งใจไม่มี type/swapWords เหมือน register ฝั่ง input เพราะ backend (v1) รองรับ
// แค่ write single register แบบ uint16 เท่านั้น (ดูคอมเมนต์ใน RS485Output.h/TCPModbusOutput.h)
class _WriteMapRow {
  _WriteMapRow({required String label, required String address, String scale = '1'})
      : labelController = TextEditingController(text: label),
        addressController = TextEditingController(text: address),
        scaleController = TextEditingController(text: scale);

  final TextEditingController labelController;
  final TextEditingController addressController;
  final TextEditingController scaleController;

  void dispose() {
    labelController.dispose();
    addressController.dispose();
    scaleController.dispose();
  }
}

class _OutputSetupPageState extends State<OutputSetupPage> {
  static const _timeout = Duration(seconds: 5);

  // ── ว่า output ตัวไหนเปิดอยู่บ้าง (อ่านอย่างเดียว — เปิด/ปิดที่ Dashboard) ──
  final Set<String> _enabledOutputs = {};
  bool _loadingMode = true;
  String? _modeError;

  // ── HTTP (api) output ─────────────────────────────
  final _httpUrlController = TextEditingController();
  String _httpMethod = 'POST';
  final List<_HeaderRow> _httpHeaders = [];
  bool _loadingHttpOutput = true;
  bool _savingHttpOutput = false;
  String? _httpOutputError;

  // ── MQTT output ───────────────────────────────────
  final _mqttHostController = TextEditingController();
  final _mqttPortController = TextEditingController(text: '1883');
  final _mqttClientIdController = TextEditingController();
  final _mqttUsernameController = TextEditingController();
  final _mqttPasswordController = TextEditingController();
  final _mqttTopicController = TextEditingController();
  final _mqttCommandTopicController = TextEditingController();
  bool _mqttRetain = false;
  bool _loadingMqttOutput = true;
  bool _savingMqttOutput = false;
  String? _mqttOutputError;

  // ── App result card ───────────────────────────────
  Timer? _appResultTimer;
  bool _appResultHasData = false;
  Map<String, dynamic> _appResultFields = {};
  int? _appResultAgeMs;

  // ── RS485 output (เขียนค่ากลับออก Modbus RTU) ────────
  final _rs485OutRxPinController = TextEditingController();
  final _rs485OutTxPinController = TextEditingController();
  final _rs485OutDePinController = TextEditingController();
  final _rs485OutRePinController = TextEditingController();
  final _rs485OutBaudController = TextEditingController();
  final _rs485OutSlaveIdController = TextEditingController();
  String _rs485OutParity = 'N';
  int _rs485OutStopBits = 1;
  bool _loadingRs485Output = true;
  bool _savingRs485Output = false;
  String? _rs485OutputError;
  final List<_WriteMapRow> _rs485WriteMapRows = [];
  bool _loadingRs485WriteMap = true;
  bool _savingRs485WriteMap = false;
  String? _rs485WriteMapError;

  // ── Modbus TCP output (เขียนค่าออก Modbus TCP) ──
  final _modbusTcpHostController = TextEditingController();
  final _modbusTcpPortController = TextEditingController(text: '502');
  final _modbusTcpUnitIdController = TextEditingController(text: '1');
  bool _loadingModbusTcpOutput = true;
  bool _savingModbusTcpOutput = false;
  String? _modbusTcpOutputError;
  final List<_WriteMapRow> _modbusTcpWriteMapRows = [];
  bool _loadingModbusTcpWriteMap = true;
  bool _savingModbusTcpWriteMap = false;
  String? _modbusTcpWriteMapError;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _appResultTimer = Timer.periodic(const Duration(seconds: 3), (_) => _loadAppResult());
  }

  @override
  void dispose() {
    _httpUrlController.dispose();
    for (final h in _httpHeaders) h.dispose();
    _mqttHostController.dispose();
    _mqttPortController.dispose();
    _mqttClientIdController.dispose();
    _mqttUsernameController.dispose();
    _mqttPasswordController.dispose();
    _mqttTopicController.dispose();
    _mqttCommandTopicController.dispose();
    _rs485OutRxPinController.dispose();
    _rs485OutTxPinController.dispose();
    _rs485OutDePinController.dispose();
    _rs485OutRePinController.dispose();
    _rs485OutBaudController.dispose();
    _rs485OutSlaveIdController.dispose();
    for (final r in _rs485WriteMapRows) r.dispose();
    _modbusTcpHostController.dispose();
    _modbusTcpPortController.dispose();
    _modbusTcpUnitIdController.dispose();
    for (final r in _modbusTcpWriteMapRows) r.dispose();
    _appResultTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadMode(),
      _loadHttpOutput(),
      _loadMqttOutput(),
      _loadAppResult(),
      _loadRs485Output(),
      _loadRs485WriteMap(),
      _loadModbusTcpOutput(),
      _loadModbusTcpWriteMap(),
    ]);
  }

  void _showMessage(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  // =====================================================
  // API: GET /api/mode — รู้ว่า output ตัวไหนเปิดอยู่ (read-only ที่นี่)
  // =====================================================
  Future<void> _loadMode() async {
    setState(() { _loadingMode = true; _modeError = null; });
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/mode')).timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final outputs = (data['outputs'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toSet();
        setState(() {
          _enabledOutputs
            ..clear()
            ..addAll(outputs);
          _loadingMode = false;
        });
      } else {
        setState(() { _modeError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})'; _loadingMode = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _modeError = 'หมดเวลาเชื่อมต่อ'; _loadingMode = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _modeError = 'เกิดข้อผิดพลาด: $e'; _loadingMode = false; });
    }
  }

  // =====================================================
  // API: /api/output/api (HTTP/REST)
  // =====================================================
  Future<void> _loadHttpOutput() async {
    setState(() { _loadingHttpOutput = true; _httpOutputError = null; });
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/output/api')).timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _httpUrlController.text = data['url']?.toString() ?? '';
        for (final h in _httpHeaders) h.dispose();
        _httpHeaders.clear();
        final headers = (data['headers'] as Map<String, dynamic>?) ?? {};
        headers.forEach((k, v) => _httpHeaders.add(_HeaderRow(key: k, value: v?.toString() ?? '')));
        setState(() {
          _httpMethod = (data['method']?.toString().isNotEmpty ?? false) ? data['method'].toString() : 'POST';
          _loadingHttpOutput = false;
        });
      } else {
        setState(() { _httpOutputError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})'; _loadingHttpOutput = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _httpOutputError = 'หมดเวลาเชื่อมต่อ'; _loadingHttpOutput = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _httpOutputError = 'เกิดข้อผิดพลาด: $e'; _loadingHttpOutput = false; });
    }
  }

  Future<void> _saveHttpOutput() async {
    setState(() => _savingHttpOutput = true);
    final Map<String, dynamic> headers = {};
    for (final row in _httpHeaders) {
      final key = row.keyController.text.trim();
      if (key.isEmpty) continue;
      headers[key] = row.valueController.text.trim();
    }
    final body = {
      "url":     _httpUrlController.text.trim(),
      "method":  _httpMethod,
      "headers": headers,
    };
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/output/api'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึกการตั้งค่า HTTP สำเร็จ'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingHttpOutput = false);
    }
  }

  void _addHeaderRow()            => setState(() => _httpHeaders.add(_HeaderRow()));
  void _removeHeaderRow(int index) => setState(() => _httpHeaders.removeAt(index).dispose());

  // =====================================================
  // API: /api/output/mqtt
  // =====================================================
  Future<void> _loadMqttOutput() async {
    setState(() { _loadingMqttOutput = true; _mqttOutputError = null; });
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/output/mqtt')).timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _mqttHostController.text     = data['host']?.toString()      ?? '';
        _mqttPortController.text     = '${data['port']              ?? 1883}';
        _mqttClientIdController.text = data['client_id']?.toString() ?? '';
        _mqttUsernameController.text = data['username']?.toString()  ?? '';
        _mqttTopicController.text    = data['topic']?.toString()     ?? '';
        _mqttCommandTopicController.text = data['command_topic']?.toString() ?? '';
        setState(() {
          _mqttRetain    = data['retain']   == true;
          _loadingMqttOutput = false;
        });
      } else {
        setState(() { _mqttOutputError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})'; _loadingMqttOutput = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _mqttOutputError = 'หมดเวลาเชื่อมต่อ'; _loadingMqttOutput = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _mqttOutputError = 'เกิดข้อผิดพลาด: $e'; _loadingMqttOutput = false; });
    }
  }

  Future<void> _saveMqttOutput() async {
    if (_mqttHostController.text.trim().isEmpty) {
      _showMessage('กรุณากรอก Broker Host');
      return;
    }
    setState(() => _savingMqttOutput = true);
    final body = <String, dynamic>{
      "host":      _mqttHostController.text.trim(),
      "port":      int.tryParse(_mqttPortController.text.trim()) ?? 1883,
      "client_id": _mqttClientIdController.text.trim(),
      "username":  _mqttUsernameController.text.trim(),
      "topic":     _mqttTopicController.text.trim(),
      "command_topic": _mqttCommandTopicController.text.trim(),
      "retain":    _mqttRetain,
      if (_mqttPasswordController.text.isNotEmpty) "password": _mqttPasswordController.text,
    };
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/output/mqtt'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      final success = res.statusCode == 200 && data?['success'] == true;
      if (success) _mqttPasswordController.clear();
      _showMessage(success
          ? 'บันทึกการตั้งค่า MQTT สำเร็จ'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingMqttOutput = false);
    }
  }

  // =====================================================
  // API: /api/output/rs485  (เขียนค่ากลับออก Modbus RTU — คนละชุดกับ RS485 input)
  // =====================================================
  Future<void> _loadRs485Output() async {
    setState(() { _loadingRs485Output = true; _rs485OutputError = null; });
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/api/output/rs485')).timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _rs485OutRxPinController.text   = '${data['rx_pin']   ?? 26}';
        _rs485OutTxPinController.text   = '${data['tx_pin']   ?? 27}';
        _rs485OutDePinController.text   = '${data['de_pin']   ?? -1}';
        _rs485OutRePinController.text   = '${data['re_pin']   ?? -1}';
        _rs485OutBaudController.text    = '${data['baud']     ?? 9600}';
        _rs485OutSlaveIdController.text = '${data['slave_id'] ?? 1}';
        setState(() {
          _rs485OutParity = (data['parity']?.toString().isNotEmpty ?? false) ? data['parity'].toString() : 'N';
          final parsedStop = int.tryParse('${data['stop_bits'] ?? 1}') ?? 1;
          _rs485OutStopBits = [1, 2].contains(parsedStop) ? parsedStop : 1;  // กันค่าแปลกๆ จาก zero-init
          _loadingRs485Output = false;
        });
      } else {
        setState(() { _rs485OutputError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})'; _loadingRs485Output = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _rs485OutputError = 'หมดเวลาเชื่อมต่อ'; _loadingRs485Output = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _rs485OutputError = 'เกิดข้อผิดพลาด: $e'; _loadingRs485Output = false; });
    }
  }

  Future<void> _saveRs485Output() async {
    setState(() => _savingRs485Output = true);
    final body = {
      "rx_pin":    int.tryParse(_rs485OutRxPinController.text.trim())   ?? 26,
      "tx_pin":    int.tryParse(_rs485OutTxPinController.text.trim())   ?? 27,
      "de_pin":    int.tryParse(_rs485OutDePinController.text.trim())   ?? -1,
      "re_pin":    int.tryParse(_rs485OutRePinController.text.trim())   ?? -1,
      "baud":      int.tryParse(_rs485OutBaudController.text.trim())    ?? 9600,
      "parity":    _rs485OutParity,
      "stop_bits": _rs485OutStopBits,
      "slave_id":  int.tryParse(_rs485OutSlaveIdController.text.trim()) ?? 1,
    };
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/output/rs485'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึกการตั้งค่า RS485 output สำเร็จ'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingRs485Output = false);
    }
  }

  Future<void> _loadRs485WriteMap() async {
    setState(() { _loadingRs485WriteMap = true; _rs485WriteMapError = null; });
    try {
      final res = await http
          .get(Uri.parse('${widget.baseUrl}/api/output/rs485/registers'))
          .timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        for (final r in _rs485WriteMapRows) r.dispose();
        _rs485WriteMapRows.clear();
        data.forEach((label, value) {
          final v = value as Map<String, dynamic>;
          _rs485WriteMapRows.add(_WriteMapRow(
            label:   label,
            address: v['address']?.toString() ?? '',
            scale:   '${v['scale'] ?? 1}',
          ));
        });
        setState(() => _loadingRs485WriteMap = false);
      } else {
        setState(() { _rs485WriteMapError = 'โหลด write map ไม่สำเร็จ (${res.statusCode})'; _loadingRs485WriteMap = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _rs485WriteMapError = 'หมดเวลาเชื่อมต่อ'; _loadingRs485WriteMap = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _rs485WriteMapError = 'เกิดข้อผิดพลาด: $e'; _loadingRs485WriteMap = false; });
    }
  }

  Future<void> _saveRs485WriteMap() async {
    setState(() => _savingRs485WriteMap = true);
    final Map<String, dynamic> body = {};
    for (final row in _rs485WriteMapRows) {
      final label   = row.labelController.text.trim();
      final address = row.addressController.text.trim();
      if (label.isEmpty || address.isEmpty) continue;
      body[label] = {
        "address": address,
        "scale":   double.tryParse(row.scaleController.text.trim()) ?? 1.0,
      };
    }
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/output/rs485/registers'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึก Write Map สำเร็จ (${body.length} รายการ)'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingRs485WriteMap = false);
    }
  }

  void _addRs485WriteMapRow() => setState(() => _rs485WriteMapRows.add(_WriteMapRow(label: '', address: '')));
  void _removeRs485WriteMapRow(int index) => setState(() => _rs485WriteMapRows.removeAt(index).dispose());

  // =====================================================
  // API: /api/output/modbus_tcp  (เขียนค่าออก Modbus TCP)
  // =====================================================
  Future<void> _loadModbusTcpOutput() async {
    setState(() { _loadingModbusTcpOutput = true; _modbusTcpOutputError = null; });
    try {
      final res = await http
          .get(Uri.parse('${widget.baseUrl}/api/output/modbus_tcp'))
          .timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _modbusTcpHostController.text   = data['host']?.toString() ?? '';
        _modbusTcpPortController.text   = '${data['port']    ?? 502}';
        _modbusTcpUnitIdController.text = '${data['unit_id'] ?? 1}';
        setState(() => _loadingModbusTcpOutput = false);
      } else {
        setState(() { _modbusTcpOutputError = 'โหลดค่าไม่สำเร็จ (${res.statusCode})'; _loadingModbusTcpOutput = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _modbusTcpOutputError = 'หมดเวลาเชื่อมต่อ'; _loadingModbusTcpOutput = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _modbusTcpOutputError = 'เกิดข้อผิดพลาด: $e'; _loadingModbusTcpOutput = false; });
    }
  }

  Future<void> _saveModbusTcpOutput() async {
    if (_modbusTcpHostController.text.trim().isEmpty) {
      _showMessage('กรุณากรอก Host ของอุปกรณ์ Modbus TCP');
      return;
    }
    setState(() => _savingModbusTcpOutput = true);
    final body = {
      "host":    _modbusTcpHostController.text.trim(),
      "port":    int.tryParse(_modbusTcpPortController.text.trim())   ?? 502,
      "unit_id": int.tryParse(_modbusTcpUnitIdController.text.trim()) ?? 1,
    };
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/output/modbus_tcp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึกการตั้งค่า Modbus TCP output สำเร็จ'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingModbusTcpOutput = false);
    }
  }

  Future<void> _loadModbusTcpWriteMap() async {
    setState(() { _loadingModbusTcpWriteMap = true; _modbusTcpWriteMapError = null; });
    try {
      final res = await http
          .get(Uri.parse('${widget.baseUrl}/api/output/modbus_tcp/registers'))
          .timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        for (final r in _modbusTcpWriteMapRows) r.dispose();
        _modbusTcpWriteMapRows.clear();
        data.forEach((label, value) {
          final v = value as Map<String, dynamic>;
          _modbusTcpWriteMapRows.add(_WriteMapRow(
            label:   label,
            address: v['address']?.toString() ?? '',
            scale:   '${v['scale'] ?? 1}',
          ));
        });
        setState(() => _loadingModbusTcpWriteMap = false);
      } else {
        setState(() { _modbusTcpWriteMapError = 'โหลด write map ไม่สำเร็จ (${res.statusCode})'; _loadingModbusTcpWriteMap = false; });
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() { _modbusTcpWriteMapError = 'หมดเวลาเชื่อมต่อ'; _loadingModbusTcpWriteMap = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _modbusTcpWriteMapError = 'เกิดข้อผิดพลาด: $e'; _loadingModbusTcpWriteMap = false; });
    }
  }

  Future<void> _saveModbusTcpWriteMap() async {
    setState(() => _savingModbusTcpWriteMap = true);
    final Map<String, dynamic> body = {};
    for (final row in _modbusTcpWriteMapRows) {
      final label   = row.labelController.text.trim();
      final address = row.addressController.text.trim();
      if (label.isEmpty || address.isEmpty) continue;
      body[label] = {
        "address": address,
        "scale":   double.tryParse(row.scaleController.text.trim()) ?? 1.0,
      };
    }
    try {
      final res = await http
          .post(
            Uri.parse('${widget.baseUrl}/api/output/modbus_tcp/registers'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (!mounted) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      _showMessage(res.statusCode == 200 && data?['success'] == true
          ? 'บันทึก Write Map สำเร็จ (${body.length} รายการ)'
          : (data?['message']?.toString() ?? 'บันทึกไม่สำเร็จ'));
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('หมดเวลาเชื่อมต่อ');
    } catch (e) {
      if (!mounted) return;
      _showMessage('เกิดข้อผิดพลาด: $e');
    } finally {
      if (mounted) setState(() => _savingModbusTcpWriteMap = false);
    }
  }

  void _addModbusTcpWriteMapRow() => setState(() => _modbusTcpWriteMapRows.add(_WriteMapRow(label: '', address: '')));
  void _removeModbusTcpWriteMapRow(int index) => setState(() => _modbusTcpWriteMapRows.removeAt(index).dispose());

  // =====================================================
  // API: GET /api/output/app/latest
  // =====================================================
  Future<void> _loadAppResult() async {
    if (!_enabledOutputs.contains('app')) return;
    try {
      final res = await http
          .get(Uri.parse('${widget.baseUrl}/api/output/app/latest'))
          .timeout(_timeout);
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() {
          _appResultHasData = data['has_data'] == true;
          _appResultFields = _parseAppResultData(data['data']);
          _appResultAgeMs = data['age_ms'] is int ? data['age_ms'] as int : null;
        });
      }
    } catch (_) {
      // เงียบไว้ ไม่ต้องโชว์ error ทุก 3 วิถ้าเน็ตสะดุดชั่วคราว
    }
  }

  // firmware ส่ง data มาเป็น array [{"deviceName","valueData"}] (Payload.toJson() แบบใหม่)
  // แปลงกลับเป็น Map<label, value> ให้ _buildAppResultCard() ใช้ได้เหมือนเดิม
  // รองรับ firmware format เก่า ({"label": value}) ไว้ด้วยเผื่อยังไม่ได้อัปเดตเฟิร์มแวร์
  Map<String, dynamic> _parseAppResultData(dynamic raw) {
    final Map<String, dynamic> out = {};
    if (raw is List) {
      for (final item in raw) {
        if (item is Map && item['deviceName'] != null) {
          out[item['deviceName'].toString()] = item['valueData'];
        }
      }
    } else if (raw is Map<String, dynamic>) {
      out.addAll(raw);
    }
    return out;
  }

  // =====================================================
  // Build
  // =====================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ตั้งค่า Output"),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll)],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildEnabledSummaryCard(),
            const SizedBox(height: 16),
            if (_enabledOutputs.contains('app')) ...[
              _buildAppResultCard(),
              const SizedBox(height: 16),
            ],
            if (_enabledOutputs.contains('api')) ...[
              _buildHttpOutputCard(),
              const SizedBox(height: 16),
            ],
            if (_enabledOutputs.contains('mqtt')) ...[
              _buildMqttOutputCard(),
              const SizedBox(height: 16),
            ],
            if (_enabledOutputs.contains('rs485')) ...[
              _buildRs485OutputCard(),
              const SizedBox(height: 16),
            ],
            if (_enabledOutputs.contains('modbus_tcp')) ...[
              _buildModbusTcpOutputCard(),
              const SizedBox(height: 16),
            ],
            if (!_loadingMode && _enabledOutputs.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    "ยังไม่ได้เปิดใช้งาน Output ตัวไหนเลย — ไปเปิดที่หน้า Dashboard ก่อน",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // Card widgets
  // =====================================================

  Widget _buildEnabledSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Output ที่เปิดใช้งานอยู่", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              "จะเปิด/ปิด Output ให้ไปที่หน้า Dashboard — หน้านี้ใช้ตั้งค่ารายละเอียดของแต่ละตัวเท่านั้น",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_loadingMode)
              const Center(child: CircularProgressIndicator())
            else if (_modeError != null)
              Text(_modeError!, style: const TextStyle(color: Colors.red))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _enabledOutputs.isEmpty
                    ? [const Text("ไม่มี", style: TextStyle(color: Colors.grey))]
                    : _enabledOutputs.map((t) => Chip(label: Text(t))).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppResultCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("ผลลัพธ์ล่าสุด (App)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: "รีเฟรชตอนนี้",
                  onPressed: _loadAppResult,
                ),
              ],
            ),
            const Text(
              "อัปเดตอัตโนมัติทุก ~3 วินาที จากค่าที่ ESP32 อ่านได้ล่าสุด ไม่ว่า Input ตอนนี้จะเป็น RS485 หรือ TCP",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (!_appResultHasData)
              const Text("ยังไม่มีข้อมูล — รอรอบ poll ถัดไป หรือกดปุ่มทดสอบในหน้า Config Input",
                  style: TextStyle(color: Colors.grey))
            else ...[
              if (_appResultAgeMs != null)
                Text(
                  "อัปเดตเมื่อ ${(_appResultAgeMs! / 1000).toStringAsFixed(0)} วินาทีที่แล้ว",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              const SizedBox(height: 8),
              if (_appResultFields.isEmpty)
                const Text("อ่านได้ 0 field", style: TextStyle(color: Colors.grey))
              else
                ..._appResultFields.entries.map((e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(e.key, style: const TextStyle(color: Colors.grey)),
                          Text("${e.value}", style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHttpOutputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ตั้งค่า HTTP API", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            if (_loadingHttpOutput)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_httpOutputError != null) ...[
                Text(_httpOutputError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              TextField(controller: _httpUrlController, keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: "URL ปลายทาง", hintText: "http://192.168.1.50:3000/api/data",
                    border: OutlineInputBorder())),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _httpMethod,
                decoration: const InputDecoration(labelText: "HTTP Method", border: OutlineInputBorder()),
                items: ['POST', 'PUT', 'PATCH', 'GET']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setState(() => _httpMethod = v ?? 'POST'),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Custom Headers", style: TextStyle(fontWeight: FontWeight.w600)),
                TextButton.icon(onPressed: _addHeaderRow, icon: const Icon(Icons.add, size: 18), label: const Text("เพิ่ม")),
              ]),
              ..._httpHeaders.asMap().entries.map((entry) {
                final i = entry.key;
                final h = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: TextField(controller: h.keyController,
                        decoration: const InputDecoration(labelText: "Key", isDense: true, border: OutlineInputBorder()))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: h.valueController,
                        decoration: const InputDecoration(labelText: "Value", isDense: true, border: OutlineInputBorder()))),
                    IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () => _removeHeaderRow(i)),
                  ]),
                );
              }),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingHttpOutput ? null : _saveHttpOutput,
                  icon: _savingHttpOutput
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึกการตั้งค่า HTTP"),
                )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMqttOutputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ตั้งค่า MQTT", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            if (_loadingMqttOutput)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_mqttOutputError != null) ...[
                Text(_mqttOutputError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Expanded(flex: 3, child: TextField(controller: _mqttHostController,
                    decoration: const InputDecoration(labelText: "Broker Host", hintText: "broker.example.com", border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _mqttPortController, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Port", border: OutlineInputBorder()))),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _mqttClientIdController,
                  decoration: const InputDecoration(labelText: "Client ID (ถ้ามี)", helperText: "เว้นว่าง = ใช้ MAC address อัตโนมัติ", border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _mqttUsernameController,
                  decoration: const InputDecoration(labelText: "Username (ถ้ามี)", border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _mqttPasswordController, obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Password (ถ้ามี)",
                    helperText: "เว้นว่างไว้ = ใช้รหัสเดิม (ไม่แสดงค่าเดิมด้วยเหตุผลด้านความปลอดภัย)",
                    border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _mqttTopicController,
                  decoration: const InputDecoration(labelText: "Topic", hintText: "sensors/farm-box-1", border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: _mqttCommandTopicController,
                  decoration: const InputDecoration(
                    labelText: "Command Topic (ถ้ามี)",
                    hintText: "sensors/farm-box-1/cmd",
                    helperText: 'รอรับคำสั่ง JSON [{"deviceName":"d1","cmd":"10"}] แล้วเขียนค่าลง register ที่ label ตรงกัน',
                    border: OutlineInputBorder())),
              CheckboxListTile(contentPadding: EdgeInsets.zero,
                title: const Text("Retain message"),
                value: _mqttRetain, onChanged: (v) => setState(() => _mqttRetain = v ?? false)),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingMqttOutput ? null : _saveMqttOutput,
                  icon: _savingMqttOutput
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึกการตั้งค่า MQTT"),
                )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRs485OutputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ตั้งค่า RS485 Output", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              "เขียนค่ากลับออกเป็น Modbus RTU holding register (write single register) — ใช้คนละ "
              "UART กับ RS485 Input จึงเปิดพร้อมกับ RS485 Input ได้โดยไม่ชนพอร์ต แต่จะเปิดพร้อม RS485 "
              "Input ไม่ได้ในแง่ routing เพราะเป็น output ชนิดเดียวกับ input (rs485→rs485 ถูกบล็อก)",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_loadingRs485Output)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_rs485OutputError != null) ...[
                Text(_rs485OutputError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Expanded(child: TextField(controller: _rs485OutRxPinController, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "RX Pin", border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _rs485OutTxPinController, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "TX Pin", border: OutlineInputBorder()))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: _rs485OutDePinController, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "DE Pin", helperText: "-1 ถ้าไม่ใช้", border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _rs485OutRePinController, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "RE Pin", border: OutlineInputBorder()))),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _rs485OutBaudController, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Baud Rate", border: OutlineInputBorder())),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(
                  initialValue: _rs485OutParity,
                  decoration: const InputDecoration(labelText: "Parity", border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'N', child: Text("None (N)")),
                    DropdownMenuItem(value: 'E', child: Text("Even (E)")),
                    DropdownMenuItem(value: 'O', child: Text("Odd (O)")),
                  ],
                  onChanged: (v) => setState(() => _rs485OutParity = v ?? 'N'),
                )),
                const SizedBox(width: 8),
                Expanded(child: DropdownButtonFormField<int>(
                  initialValue: _rs485OutStopBits,
                  decoration: const InputDecoration(labelText: "Stop Bits", border: OutlineInputBorder()),
                  items: const [DropdownMenuItem(value: 1, child: Text("1")), DropdownMenuItem(value: 2, child: Text("2"))],
                  onChanged: (v) => setState(() => _rs485OutStopBits = v ?? 1),
                )),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _rs485OutSlaveIdController, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Slave ID", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingRs485Output ? null : _saveRs485Output,
                  icon: _savingRs485Output
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึกการเชื่อมต่อ"),
                )),
            ],
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Write Map", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                IconButton(icon: const Icon(Icons.add_circle), tooltip: "เพิ่มแถว", onPressed: _addRs485WriteMapRow),
              ],
            ),
            const Text(
              "field label ใน payload ที่ตรงกับชื่อนี้จะถูกเขียนไปที่ address ที่กำหนด "
              "(v1: เขียนแบบ uint16 เท่านั้น ค่า float จะถูกปัดเป็นจำนวนเต็ม)",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (_loadingRs485WriteMap)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_rs485WriteMapError != null) ...[
                Text(_rs485WriteMapError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              if (_rs485WriteMapRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text("ยังไม่มี write map — กด + เพื่อเพิ่ม", style: TextStyle(color: Colors.grey)),
                ),
              ..._rs485WriteMapRows.asMap().entries.map((e) => _buildWriteMapRow(
                    e.value,
                    onRemove: () => _removeRs485WriteMapRow(e.key),
                  )),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingRs485WriteMap ? null : _saveRs485WriteMap,
                  icon: _savingRs485WriteMap
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึก Write Map ทั้งหมด"),
                )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModbusTcpOutputCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("ตั้งค่า Modbus TCP Output", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 4),
            const Text(
              "เขียนค่าออกเป็น Modbus TCP holding register (write single register) ไปยังอุปกรณ์ปลายทาง",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_loadingModbusTcpOutput)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_modbusTcpOutputError != null) ...[
                Text(_modbusTcpOutputError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              Row(children: [
                Expanded(flex: 3, child: TextField(controller: _modbusTcpHostController,
                    decoration: const InputDecoration(labelText: "Host / IP อุปกรณ์", hintText: "192.168.1.100", border: OutlineInputBorder()))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _modbusTcpPortController, keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Port", hintText: "502", border: OutlineInputBorder()))),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _modbusTcpUnitIdController, keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Unit ID (Slave ID)", border: OutlineInputBorder())),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingModbusTcpOutput ? null : _saveModbusTcpOutput,
                  icon: _savingModbusTcpOutput
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึกการเชื่อมต่อ"),
                )),
            ],
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Write Map", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                IconButton(icon: const Icon(Icons.add_circle), tooltip: "เพิ่มแถว", onPressed: _addModbusTcpWriteMapRow),
              ],
            ),
            const Text(
              "field label ใน payload ที่ตรงกับชื่อนี้จะถูกเขียนไปที่ address ที่กำหนด "
              "(v1: เขียนแบบ uint16 เท่านั้น ค่า float จะถูกปัดเป็นจำนวนเต็ม)",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (_loadingModbusTcpWriteMap)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (_modbusTcpWriteMapError != null) ...[
                Text(_modbusTcpWriteMapError!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 8),
              ],
              if (_modbusTcpWriteMapRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text("ยังไม่มี write map — กด + เพื่อเพิ่ม", style: TextStyle(color: Colors.grey)),
                ),
              ..._modbusTcpWriteMapRows.asMap().entries.map((e) => _buildWriteMapRow(
                    e.value,
                    onRemove: () => _removeModbusTcpWriteMapRow(e.key),
                  )),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _savingModbusTcpWriteMap ? null : _saveModbusTcpWriteMap,
                  icon: _savingModbusTcpWriteMap
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text("บันทึก Write Map ทั้งหมด"),
                )),
            ],
          ],
        ),
      ),
    );
  }

  // แถว write map ใช้ร่วมกันทั้ง RS485 output และ Modbus TCP output (label/address/scale เท่านั้น)
  Widget _buildWriteMapRow(_WriteMapRow row, {required VoidCallback onRemove}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          Expanded(flex: 3, child: TextField(controller: row.labelController,
              decoration: const InputDecoration(labelText: "Label", hintText: "fan_speed", isDense: true))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: TextField(controller: row.addressController,
              decoration: const InputDecoration(labelText: "Address", hintText: "M200", isDense: true))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: TextField(controller: row.scaleController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: "Scale", isDense: true))),
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: onRemove),
        ]),
      ),
    );
  }
}
